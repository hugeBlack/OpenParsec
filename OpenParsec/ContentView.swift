import SwiftUI
import os

enum ViewType {
	case login
	case main
	case parsec
	case test
}

struct ContentView: View {
	@State var curView: ViewType = .login

	let defaultTransition = AnyTransition.move(edge: .trailing)

	var body: some View {
		ZStack {
			switch curView {
				case .login:
					LoginView(self)
				case .main:
					MainView(self)
						.transition(defaultTransition)
				case .parsec:
					ParsecView(self)
			case .test:
				TestView(self)
			 }
		}
		.onAppear(perform: initApp)
		.background(Rectangle().fill(Color.black).edgesIgnoringSafeArea(.all))
	}

	func retryRestore() {
		if curView == .login && NetworkHandler.clinfo == nil {
			initApp()
		}
	}

	func initApp() {

		// Check to see if we have old session data
		if let data = loadFromKeychain(key: GLBDataModel.shared.SessionKeyChainKey) {
			let decoder = JSONDecoder()

			print("Retrieved data from keychain: \(data).\nTrying to restore session.")
			NetworkHandler.clinfo = try? decoder.decode(ClientInfo.self, from: data)
			if NetworkHandler.clinfo != nil {
				curView = .main
				let status = SecItemUpdate([kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: GLBDataModel.shared.SessionKeyChainKey] as CFDictionary, [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock] as CFDictionary)
				if status != errSecSuccess {
					os_log("%{public}@", "[session] keychain update \(status)")
				}
				print("Session restored and moved to the main page.")
			} else {
				print("Unable to restore session, falling back to login page.")
			}
		}

		print("Initialized")
	}

	func loadFromKeychain(key: String) -> Data? {
		let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key, kSecReturnData as String: kCFBooleanTrue!, kSecMatchLimit as String: kSecMatchLimitOne]
		var item: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &item)
		guard status == errSecSuccess else {
			if status != errSecItemNotFound {
				print("Error loading from keychain: \(status)")
			}
			os_log("%{public}@", "[session] keychain read \(status) protected=\(UIApplication.shared.isProtectedDataAvailable)")
			return nil
		}
		guard let data = item as? Data else {
			return nil
		}
		return data
	}

	public func setView(_ t: ViewType) {
		withAnimation(.easeInOut) { curView = t }
	}
}

struct ContentView_Previews: PreviewProvider {
	static var previews: some View {
		ContentView()
	}
}
