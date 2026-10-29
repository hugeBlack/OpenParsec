import SwiftUI
import ParsecSDK

struct MainView: View {
	var controller: ContentView?

	@State private var page: Page = .hosts

	// Host page vars
	@State var hostCountStr: String = "0 hosts"
	@State var refreshTime: String = ""

	@State var hosts: [IdentifiableHostInfo] = []

	// Friend page vars
	@State var friendCountStr: String = "0 friends"

	@State var userInfo: IdentifiableUserInfo?
	@State var friends: [IdentifiableUserInfo] = []

	// Global vars
	@State var showBaseAlert: Bool = false
	@State var baseAlertText: String = ""

	@State var showLogoutAlert: Bool = false

	@State var isConnecting: Bool = false
	@State var waitingForApproval: Bool = false
	@State var retryingConnect: Bool = false
	@State var connectPolls = 0
	@State var connectingToName: String = ""
	@State var pollTimer: Timer?
	@State var approvalStartedAt: Date?
	@State var connectStartedAt = Date()

	@State var isRefreshing: Bool = false
	@State var refreshError: String?

	@State var inSettings: Bool = false
	@State var sessionExpired: Bool = false

	@State private var lastHostShown: String?

	var busy: Bool {
		isConnecting || inSettings
	}

	init(_ controller: ContentView?) {
		self.controller = controller
	}

	var body: some View {
		TabView(selection: $page) {
			Tab("Hosts", systemImage: "desktopcomputer", value: Page.hosts) {
				NavigationStack {
					List {
						if sessionExpired {
							Section {
								HStack {
									Label("Your Parsec session expired", systemImage: "exclamationmark.triangle")
									Spacer()
									Button("Sign In", action: logout)
										.buttonStyle(.borderless)
								}
							}
						}
						if let refreshError = refreshError {
							Section {
								HStack {
									Label(refreshError, systemImage: "wifi.exclamationmark")
									Spacer()
									Button("Retry", action: refreshHosts)
										.buttonStyle(.borderless)
								}
							}
						}
						if let lastHost = lastHostShown, !isConnecting {
							Section("Last Connected") {
								HStack {
									Text(lastHost)
									Spacer()
									Button("Reconnect", action: reconnectLastHost)
										.buttonStyle(.glass)
									Button(action: clearLastHost) {
										Image(systemName: "xmark")
									}
									.buttonStyle(.borderless)
									.accessibilityLabel("Clear last host")
								}
								Toggle("Reconnect on app launch", isOn: Binding(
									get: { SettingsHandler.autoConnectOnLaunch },
									set: { SettingsHandler.autoConnectOnLaunch = $0 }
								))
							}
						}
						Section {
							ForEach(hosts) { i in
								Button(action: { connectTo(i) }) {
									HStack(spacing: 12) {
										AsyncImage(url: URL(string: "https://parsecusercontent.com/cors-resize-image/w=88,h=88,fit=crop,background=white,q=90,f=jpeg/avatars/\(String(i.user.id))/avatar")) { image in
								image.resizable().scaledToFill()
							} placeholder: {
								Image(systemName: "person.crop.square").resizable().scaledToFit().foregroundStyle(.secondary).padding(8)
							}
							.frame(width: 44, height: 44)
							.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
							.accessibilityHidden(true)
										VStack(alignment: .leading, spacing: 2) {
											Text(i.hostname).font(.headline)
											Text("\(i.user.name)#\(String(i.user.id))")
												.font(.subheadline)
												.foregroundStyle(.secondary)
										}
										Spacer()
										if i.connections > 0 {
											Label(String(i.connections), systemImage: "person.fill")
												.font(.subheadline)
												.foregroundStyle(.secondary)
										}
									}
								}
								.tint(.primary)
								.accessibilityHint("Connect")
								.contextMenu {
									Button(action: { UIPasteboard.general.string = i.hostname }) {
										Label("Copy Name", systemImage: "doc.on.doc")
									}
								}
							}
						} header: {
							Text(hostCountStr)
						} footer: {
							if isRefreshing {
								HStack(spacing: 8) {
									ProgressView()
									Text("Refreshing hosts...")
								}
							} else if !refreshTime.isEmpty {
								Text(refreshTime)
							}
						}
					}
					.overlay {
						if hosts.isEmpty && !isRefreshing && !sessionExpired && refreshError == nil && lastHostShown == nil {
							ContentUnavailableView("No Hosts Online", systemImage: "desktopcomputer", description: Text("Your available computers appear here. Make sure Parsec is running on your host."))
						}
					}
					.navigationTitle("Hosts")
					.refreshable { refreshHosts() }
					.toolbar { mainToolbar(showRefresh: true) }
				}
			}
			Tab("Friends", systemImage: "person.2.fill", value: Page.friends) {
				NavigationStack {
					List {
						if let user = userInfo {
							Section("You") {
								HStack(spacing: 12) {
									AsyncImage(url: URL(string: "https://parsecusercontent.com/cors-resize-image/w=80,h=80,fit=crop,background=white,q=90,f=jpeg/avatars/\(String(user.id))/avatar")) { image in
								image.resizable().scaledToFill()
							} placeholder: {
								Image(systemName: "person.crop.square").resizable().scaledToFit().foregroundStyle(.secondary).padding(8)
							}
							.frame(width: 40, height: 40)
							.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
							.accessibilityHidden(true)
									Text("\(user.username)#\(String(user.id))")
								}
							}
						}
						if friends.count > 0 {
							Section(friendCountStr) {
								ForEach(friends) { i in
									HStack(spacing: 12) {
										AsyncImage(url: URL(string: "https://parsecusercontent.com/cors-resize-image/w=80,h=80,fit=crop,background=white,q=90,f=jpeg/avatars/\(String(i.id))/avatar")) { image in
								image.resizable().scaledToFill()
							} placeholder: {
								Image(systemName: "person.crop.square").resizable().scaledToFit().foregroundStyle(.secondary).padding(8)
							}
							.frame(width: 40, height: 40)
							.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
							.accessibilityHidden(true)
										Text("\(i.username)#\(String(i.id))")
									}
								}
							}
						}
					}
					.overlay {
						if friends.isEmpty && userInfo == nil {
							ContentUnavailableView("No Friends Yet", systemImage: "person.2", description: Text("Your Parsec friends appear here."))
						}
					}
					.navigationTitle("Friends")
					.toolbar { mainToolbar(showRefresh: false) }
				}
			}
		}
		.onAppear(perform: initView)
		.onDisappear { ParsecBackgroundManager.shared.onShortcutReconnect = nil }
		.alert("Are you sure you want to logout?", isPresented: $showLogoutAlert) {
			Button("Logout", role: .destructive, action: logout)
			Button("Cancel", role: .cancel) {}
		}
		.alert(baseAlertText, isPresented: $showBaseAlert) {
			Button("OK", role: .cancel) {}
		}
		.sheet(isPresented: $inSettings) { SettingsView(visible: $inSettings) }
		.sheet(isPresented: $isConnecting) {
			NavigationStack {
				VStack(spacing: 20) {
					ProgressView()
						.controlSize(.large)
					Text(waitingForApproval ? "Waiting for \(connectingToName) to approve you..." : retryingConnect ? "\(connectingToName) didn't answer, trying again..." : "Requesting connection to \(connectingToName)...")
						.multilineTextAlignment(.center)
						.accessibilityAddTraits(.updatesFrequently)
				}
				.padding()
				.navigationTitle("Connecting")
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .cancellationAction) {
						Button("Cancel", role: .cancel, action: cancelConnection)
					}
				}
			}
			.presentationDetents([.height(260)])
			.interactiveDismissDisabled()
		}
	}

	@ToolbarContentBuilder
	func mainToolbar(showRefresh: Bool) -> some ToolbarContent {
		ToolbarItem(placement: .topBarLeading) {
			Button(action: { showLogoutAlert = true }) {
				Image(systemName: "rectangle.portrait.and.arrow.right")
			}
			.accessibilityLabel("Logout")
		}
		if showRefresh {
			ToolbarItem(placement: .topBarTrailing) {
				Button(action: refreshHosts) {
					Image(systemName: "arrow.clockwise")
				}
				.disabled(isRefreshing)
				.accessibilityLabel("Refresh hosts")
			}
		}
		ToolbarItem(placement: .topBarTrailing) {
			Button(action: { inSettings = true }) {
				Image(systemName: "gear")
			}
			.accessibilityLabel("Settings")
		}
	}

	func initView() {
		lastHostShown = ParsecBackgroundManager.shared.lastPeerId != nil ? ParsecBackgroundManager.shared.lastHostname : nil
		refreshHosts()
		refreshSelf()
		refreshFriends()

		ParsecBackgroundManager.shared.onShouldReconnect = { peerId in
			if let host = hosts.first(where: { $0.id == peerId }) {
				connectTo(host)
			} else {
				refreshHosts()
			}
		}

		NetworkWatcher.shared.onReturn = {
			guard NetworkHandler.clinfo != nil, !ParsecBackgroundManager.shared.hasActiveConnection else { return }
			refreshHosts()
			refreshFriends()
		}
		NetworkWatcher.shared.start()

		ParsecBackgroundManager.shared.onShortcutReconnect = {
			if !isConnecting { reconnectLastHost() }
		}
		let pending = ParsecBackgroundManager.shared.reconnectPending
		ParsecBackgroundManager.shared.reconnectPending = false

		NetworkWatcher.shared.whenKnown {
			if (SettingsHandler.autoConnectOnLaunch && ParsecBackgroundManager.shared.resumeOnLaunch || pending) && !isConnecting && !ParsecBackgroundManager.shared.hasActiveConnection, ParsecBackgroundManager.shared.lastPeerId != nil {
				reconnectLastHost()
			}
		}
	}

	func reconnectLastHost() {
		guard let peerId = ParsecBackgroundManager.shared.lastPeerId else { return }
		let hostname = ParsecBackgroundManager.shared.lastHostname ?? peerId
		let user = UserInfo(id: 0, name: "", warp: false, team_id: "")
		let stub = IdentifiableHostInfo(id: peerId, hostname: hostname, user: user, connections: 0)
		appNote("[connect] last host from the saved id, host list \(hosts.isEmpty ? "not loaded yet" : "loaded")")
		connectTo(stub)
	}

	func clearLastHost() {
		ParsecBackgroundManager.shared.disableAutoReconnect()
		lastHostShown = nil
	}

	func refreshHosts() {
		guard !isRefreshing else { return }
		withAnimation {
			isRefreshing = true

			let clinfo = NetworkHandler.clinfo
			if clinfo == nil {
				isRefreshing = false
				sessionExpired = true
				return
			}

			let apiURL = URL(string: "https://kessel-api.parsec.app/v2/hosts?mode=desktop&public=false")!

			var request = URLRequest(url: apiURL)
			request.httpMethod = "GET"
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.setValue("Bearer \(clinfo!.session_id)", forHTTPHeaderField: "Authorization")
			request.setValue("parsec/150-93b Windows/11 libmatoya/4.0", forHTTPHeaderField: "User-Agent")

			let task = URLSession.shared.dataTask(with: request) { (data, response, _) in
				DispatchQueue.main.async {
					defer { isRefreshing = false }

					if let data = data {
						guard let statusCode = (response as? HTTPURLResponse)?.statusCode else { return }
						if statusCode == 401 {
							refreshError = nil
							sessionExpired = true
							return
						}
						let decoder = JSONDecoder()

						if statusCode == 200 { // 200 OK
							sessionExpired = false
							guard let info: HostInfoList = try? decoder.decode(HostInfoList.self, from: data) else {
								refreshError = "Couldn't refresh hosts: bad response"
								return
							}
							refreshError = nil
							hosts.removeAll()
							if let datas = info.data {
								datas.forEach { h in
									hosts.append(IdentifiableHostInfo(id: h.peer_id, hostname: h.name, user: h.user, connections: h.players))
								}
							}
							if let lastId = ParsecBackgroundManager.shared.lastPeerId, let current = hosts.first(where: { $0.id == lastId }), current.hostname != ParsecBackgroundManager.shared.lastHostname {
								ParsecBackgroundManager.shared.lastHostname = current.hostname
								if lastHostShown != nil { lastHostShown = current.hostname }
							}

							var grammar: String = "hosts"
							if hosts.count == 1 {
								grammar = "host"
							}

							hostCountStr = "\(hosts.count) \(grammar)"

							let formatter = DateFormatter()
							formatter.dateStyle = .short
							formatter.timeStyle = .short
							refreshTime = "Last refreshed at \(formatter.string(from: Date()))"
						} else if statusCode == 403, let info: ErrorInfo = try? decoder.decode(ErrorInfo.self, from: data) { // 403 Forbidden
							refreshError = "Couldn't refresh hosts: \(info.error)"
						} else {
							refreshError = "Couldn't refresh hosts (HTTP \(statusCode))"
						}
					} else {
						refreshError = "Can't reach Parsec"
					}
				}
			}
			task.resume()
		}
	}

	func refreshSelf() {
		withAnimation {
			let clinfo = NetworkHandler.clinfo
			if clinfo == nil {
				return
			}

			let apiURL = URL(string: "https://kessel-api.parsec.app/me")!

			var request = URLRequest(url: apiURL)
			request.httpMethod = "GET"
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.setValue("Bearer \(clinfo!.session_id)", forHTTPHeaderField: "Authorization")
			request.setValue("parsec/150-93b Windows/11 libmatoya/4.0", forHTTPHeaderField: "User-Agent")

			let task = URLSession.shared.dataTask(with: request) { (data, response, _) in
				DispatchQueue.main.async {
					if let data = data {
						guard let statusCode = (response as? HTTPURLResponse)?.statusCode else { return }
						if statusCode == 401 {
							sessionExpired = true
							return
						}
						let decoder = JSONDecoder()

						if statusCode == 200 { // 200 OK
							guard let selfInfo = try? decoder.decode(SelfInfo.self, from: data) else { return }
							userInfo = IdentifiableUserInfo(id: selfInfo.data.id, username: selfInfo.data.name)
						} else {
							guard let info: ErrorInfo = try? decoder.decode(ErrorInfo.self, from: data) else { return }

							baseAlertText = "Error gathering user info: \(info.error)"
							showBaseAlert = true
						}
					}
				}
			}
			task.resume()
		}
	}

	func refreshFriends() {
		withAnimation {
			let clinfo = NetworkHandler.clinfo
			if clinfo == nil {
				return
			}

			let apiURL = URL(string: "https://kessel-api.parsec.app/friendships")!

			var request = URLRequest(url: apiURL)
			request.httpMethod = "GET"
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.setValue("Bearer \(clinfo!.session_id)", forHTTPHeaderField: "Authorization")
			request.setValue("parsec/150-93b Windows/11 libmatoya/4.0", forHTTPHeaderField: "User-Agent")

			let task = URLSession.shared.dataTask(with: request) { (data, response, _) in
				DispatchQueue.main.async {
					if let data = data {
						guard let statusCode = (response as? HTTPURLResponse)?.statusCode else { return }
						if statusCode == 401 {
							sessionExpired = true
							return
						}
						let decoder = JSONDecoder()

						if statusCode == 200 { // 200 OK
							guard let info: FriendInfoList = try? decoder.decode(FriendInfoList.self, from: data) else { return }
							friends.removeAll()
							if let datas = info.data {
								datas.forEach { f in
									friends.append(IdentifiableUserInfo(id: f.user_id, username: f.user_name))
								}
							}

							var grammar: String = "friends"
							if friends.count == 1 {
								grammar = "friend"
							}

							friendCountStr = "\(friends.count) \(grammar)"
						} else {
							guard let info: ErrorInfo = try? decoder.decode(ErrorInfo.self, from: data) else { return }

							baseAlertText = "Error gathering friends: \(info.error)"
							showBaseAlert = true
						}
					}
				}
			}
			task.resume()
		}
	}

	func connectTo(_ who: IdentifiableHostInfo, retried: Bool = false) {
		if NetworkWatcher.shared.noNetwork {
			appNote("[connect] no network, not trying")
			withAnimation {
				isConnecting = false
				waitingForApproval = false
				retryingConnect = false
			}
			baseAlertText = "No network connection"
			showBaseAlert = true
			return
		}

		if let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
			let scale = window.screen.nativeScale
			ParsecResolution.updateClientResolution(width: Int(window.bounds.width * scale), height: Int(window.bounds.height * scale))
		}

		pollTimer?.invalidate()
		pollTimer = nil
		CParsec.initialize()
		DataManager.model.reset()
		ParsecBackgroundManager.shared.reconnectAttempts = 0
		connectingToName = who.hostname
		retryingConnect = retried
		withAnimation { isConnecting = true }

		connectStartedAt = Date()
		let status = CParsec.connect(who.id)
		appNote("[connect] started, status \(status.rawValue)")
		connectPolls = 0
		approvalStartedAt = nil

		// Polling status
		pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
			MainActor.assumeIsolated {
				pollConnect(who)
			}
		}
	}

	func pollConnect(_ who: IdentifiableHostInfo) {
		let status = CParsec.getStatus()
		connectPolls += 1

		if let err = CParsec.setupError, err.at > connectStartedAt, status == PARSEC_CONNECTING || status == CONNECT_WRN_APPROVAL {
			CParsec.setupError = nil
			appNote("[connect] sdk setup failed after \(connectPolls) polls, retried \(retryingConnect): \(err.line)")
			retryOrGiveUp(who)
			return
		}

		if status == PARSEC_CONNECTING { return } // wait

		if status == CONNECT_WRN_APPROVAL {
			if approvalStartedAt == nil {
				appNote("[connect] status \(status.rawValue) after \(connectPolls) polls, retried \(retryingConnect)")
				if connectPolls >= 20 {
					retryOrGiveUp(who)
					return
				}
			}
			let started = approvalStartedAt ?? Date()
			approvalStartedAt = started
			if !waitingForApproval { withAnimation { waitingForApproval = true } }
			if Date().timeIntervalSince(started) < 60 { return }
		}

		withAnimation {
			isConnecting = false
			waitingForApproval = false
			retryingConnect = false
		}
		appNote("[connect] result \(status.rawValue)")

		if status == PARSEC_OK {
			ParsecBackgroundManager.shared.connectionDidGoLive(peerId: who.id, hostname: hosts.first(where: { $0.id == who.id })?.hostname ?? who.hostname)
			if let c = controller {
				c.setView(.parsec)
			}
		} else {
			CParsec.disconnect()
			baseAlertText = status.readable(connecting: true)
			showBaseAlert = true
		}

		pollTimer?.invalidate()
	}

	func retryOrGiveUp(_ who: IdentifiableHostInfo) {
		pollTimer?.invalidate()
		CParsec.disconnect()
		if !retryingConnect {
			connectTo(who, retried: true)
			return
		}
		withAnimation {
			isConnecting = false
			retryingConnect = false
		}
		baseAlertText = "\(who.hostname) didn't answer the connection request"
		showBaseAlert = true
	}

	func cancelConnection() {
		appNote("[connect] cancelled")
		withAnimation {
			isConnecting = false
			waitingForApproval = false
			retryingConnect = false
		}

		CParsec.disconnect()

		pollTimer?.invalidate()
	}

	func logout() {
		removeFromKeychain(key: GLBDataModel.shared.SessionKeyChainKey)
		NetworkHandler.clinfo = nil
		ParsecBackgroundManager.shared.disableAutoReconnect()
		if let c = controller {
			c.setView(.login)
		}
	}

	func removeFromKeychain(key: String) {
		let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
		let status = SecItemDelete(query as CFDictionary)
		if status == errSecSuccess {
			print("Successfully removed data from keychain.")
		}
	}
}

struct MainView_Previews: PreviewProvider {
	static var previews: some View {
		MainView(nil)
	}
}

struct IdentifiableHostInfo: Identifiable {
	var id: String // Peer ID
	var hostname: String // Computer's Display Name
	var user: UserInfo // User Data
	var connections: Int // User's Connected To This Host
}

struct IdentifiableUserInfo: Identifiable {
	var id: Int // User ID
	var username: String // User Display Name
}

private enum Page: Hashable {
	case hosts
	case friends
}
