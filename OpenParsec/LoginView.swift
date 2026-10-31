import SwiftUI
import os

struct LoginView: View {
	var controller: ContentView?

	@State var inputEmail: String = ""
	@State var inputPassword: String = ""
	@State var inputTFA: String = ""
	@State var isTFAOn: Bool = false
	@State private var presentTFAAlert = false
	@State var isLoading: Bool = false
	@State var showAlert: Bool = false
	@State var alertText: String = ""

	init(_ controller: ContentView?) {
		self.controller = controller
	}

	var body: some View {
		NavigationStack {
			Form {
				Section {
					HStack {
						Spacer()
						Image("IconTransparent")
							.resizable()
							.aspectRatio(contentMode: .fit)
							.frame(height: 72)
							.accessibilityHidden(true)
						Spacer()
					}
					.listRowBackground(Color.clear)
				}
				Section("Parsec Account") {
					TextField("Email", text: $inputEmail)
						.disableAutocorrection(true)
						.textInputAutocapitalization(.never)
						.keyboardType(.emailAddress)
						.textContentType(.emailAddress)
					SecureField("Password", text: $inputPassword, onCommit: { authenticate() })
						.disableAutocorrection(true)
						.textInputAutocapitalization(.never)
						.textContentType(.password)
				}
				Section {
					Button(action: { authenticate() }) {
						Group {
							if isLoading && !presentTFAAlert {
								ProgressView()
							} else {
								Text("Sign In")
							}
						}
						.frame(maxWidth: .infinity)
					}
					.buttonStyle(.glassProminent)
					.controlSize(.large)
					.listRowBackground(Color.clear)
					.listRowInsets(EdgeInsets())
				}
			}
			.navigationTitle("OpenParsec")
			.disabled(isLoading)
			.accessibilityElement(children: .contain)
		}
		.sheet(isPresented: $presentTFAAlert) {
			NavigationStack {
				Form {
					Section {
						SecureField("2FA Code", text: $inputTFA, onCommit: { authenticate(inputTFA) })
							.disableAutocorrection(true)
							.textInputAutocapitalization(.never)
							.textContentType(.oneTimeCode)
					} footer: {
						Text("Enter the code from your authenticator app.")
					}
					if isLoading {
						Section {
							HStack(spacing: 12) {
								ProgressView()
								Text("Verifying...")
							}
							.accessibilityElement(children: .combine)
						}
					}
				}
				.navigationTitle("Two-Factor Code")
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .cancellationAction) {
						Button("Cancel") { presentTFAAlert = false }
					}
					ToolbarItem(placement: .confirmationAction) {
						Button("Confirm") { authenticate(inputTFA) }
							.disabled(inputTFA.isEmpty || isLoading)
					}
				}
				.disabled(isLoading)
			}
			.presentationDetents([.medium])
		}
		.alert("Login Failed", isPresented: $showAlert) {
			Button("OK", role: .cancel) {}
		} message: {
			Text(alertText)
		}
		.onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in retryRestore() }
		.onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in retryRestore() }
	}

	func retryRestore() {
		if !isLoading && !presentTFAAlert, let c = controller {
			c.retryRestore()
		}
	}

	func saveToKeychain(data: Data, key: String) {
		SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key] as CFDictionary)
		let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key, kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
		let status = SecItemAdd(query as CFDictionary, nil)
		guard status == errSecSuccess else {
			print("Error saving to Keychain: \(status)")
			return
		}
		print("Data saved to Keychain.")
	}

	func authenticate(_ tfa: String? = "") {
		#if DEBUG
		if inputEmail == "test@example.com" { // skip authentication (DEBUG ONLY)
			if let c = controller {
				c.setView(.main)
			}
			return
		}
		#endif

		withAnimation { isLoading = true }

		let apiURL = URL(string: "https://kessel-api.parsec.app/v1/auth")!

		var request = URLRequest(url: apiURL)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("parsec/150-93b Windows/11 libmatoya/4.0", forHTTPHeaderField: "User-Agent")
		request.httpBody = try? JSONSerialization.data(withJSONObject:
		[
			"email": inputEmail,
			"password": inputPassword,
			"tfa": tfa
		], options: [])

		let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
			DispatchQueue.main.async {
				isLoading = false
				if let data = data {
					guard let statusCode = (response as? HTTPURLResponse)?.statusCode else {
						alertText = "Bad response from the server"
						showAlert = true
						return
					}
					let decoder = JSONDecoder()

					if statusCode == 201 { // 201 Created
						// store it and recover it from the next app opening, so people won't swear
						guard let info: ClientInfo = try? decoder.decode(ClientInfo.self, from: data) else {
							alertText = "Bad response from the server"
							showAlert = true
							return
						}
						NetworkHandler.clinfo = info

						saveToKeychain(data: data, key: GLBDataModel.shared.SessionKeyChainKey)

						if let c = controller {
							print("*** Login succeeded! ***")
							c.setView(.main)
						}
					} else if statusCode >= 400 { // 4XX client errors
						guard let info: ErrorInfo = try? decoder.decode(ErrorInfo.self, from: data) else {
							alertText = "Login failed (HTTP \(statusCode))"
							showAlert = true
							return
						}

						let json = try? JSONSerialization.jsonObject(with: data, options: [])
						if let dict = json as? [String: Any], let isTFARequired = dict["tfa_required"] as? Bool {
							print("Code output:")
							print(dict)
							if isTFARequired {
								presentTFAAlert = true
							} else {
								alertText = "Error: \(info)"
								showAlert = true
							}
						} else {
							alertText = info.error
							showAlert = true
						}
					} else {
						alertText = "Login failed (HTTP \(statusCode))"
						showAlert = true
					}
				} else {
					alertText = error?.localizedDescription ?? "Could not reach the server"
					showAlert = true
				}
			}
		}
		task.resume()
	}
}

struct LoginView_Previews: PreviewProvider {
	static var previews: some View {
		LoginView(nil)
	}
}
