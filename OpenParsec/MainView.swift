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

	@Environment(\.sizeCategory) private var sizeCategory

	private var hostColumns: [GridItem] {
		sizeCategory.isAccessibilityCategory ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 280), spacing: 16)]
	}

	var body: some View {
		ZStack {
			Color("BackgroundGray").edgesIgnoringSafeArea(.all)
			VStack(spacing: 0) {
				header
				ScrollView {
					VStack(alignment: .leading, spacing: 20) {
						if page == .hosts { hostList } else { friendList }
					}
					.frame(maxWidth: 1100)
					.padding(20)
					.frame(maxWidth: .infinity)
				}
				pagePicker
			}
			.disabled(busy)
			.alert(isPresented: $showBaseAlert) { Alert(title: Text(baseAlertText)) }
			SettingsView(visible: $inSettings)
			if isConnecting { connectionPrompt }
		}
		.foregroundColor(Color("Foreground"))
		.buttonStyle(PlainButtonStyle())
		.onAppear(perform: initView)
		.onDisappear { ParsecBackgroundManager.shared.onShortcutReconnect = nil }
	}

	private var header: some View {
		HStack(spacing: 12) {
			Button(action: { showLogoutAlert = true }) {
				Image(systemName: "rectangle.portrait.and.arrow.right")
					.frame(width: 44, height: 44)
			}
			.accessibilityLabel("Sign out")
			.alert(isPresented: $showLogoutAlert) {
				Alert(title: Text("Sign out of Parsec?"), primaryButton: .destructive(Text("Sign Out"), action: logout), secondaryButton: .cancel())
			}
			VStack(alignment: .leading, spacing: 2) {
				Text(page == .hosts ? "Computers" : "Friends")
					.font(.headline)
					.foregroundColor(Color("Foreground"))
				Text(page == .hosts ? hostCountStr : friendCountStr)
					.font(.caption)
					.foregroundColor(Color("ForegroundInactive"))
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			if page == .hosts {
				Button(action: refreshHosts) {
					Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
				}
				.disabled(isRefreshing)
				.accessibilityLabel("Refresh computers")
			}
			Button(action: { withAnimation(.easeInOut(duration: 0.2)) { inSettings = true } }) {
				Image(systemName: "gearshape").frame(width: 44, height: 44)
			}
			.accessibilityLabel("Settings")
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
		.foregroundColor(Color("AccentColor"))
		.background(Color("BackgroundTab"))
	}

	private var hostList: some View {
		VStack(alignment: .leading, spacing: 20) {
			if sessionExpired {
				notice("Your Parsec session expired", action: "Sign In", perform: logout)
			}
			if let error = refreshError {
				notice(error, action: "Retry", perform: refreshHosts)
			}
			if let name = lastHostShown {
				VStack(alignment: .leading, spacing: 12) {
					HStack(alignment: .top, spacing: 12) {
						Image(systemName: "clock.arrow.circlepath")
							.foregroundColor(Color("AccentColor"))
						VStack(alignment: .leading, spacing: 4) {
							Text("Last connected").font(.caption).foregroundColor(Color("ForegroundInactive"))
							Text(name).font(.headline).fixedSize(horizontal: false, vertical: true)
						}
						Spacer(minLength: 0)
						Button(action: clearLastHost) {
							Image(systemName: "xmark").frame(width: 44, height: 44)
						}
						.accessibilityLabel("Forget last computer")
					}
					Button(action: reconnectLastHost) {
						Label("Reconnect", systemImage: "play.fill")
							.font(.subheadline.weight(.semibold))
							.frame(maxWidth: .infinity, minHeight: 44)
							.foregroundColor(.white)
							.background(Color("AccentColor"))
							.cornerRadius(10)
					}
					Toggle("Reconnect on app launch", isOn: Binding(
						get: { SettingsHandler.autoConnectOnLaunch },
						set: { SettingsHandler.autoConnectOnLaunch = $0 }
					))
					.font(.subheadline)
				}
				.padding(16)
				.background(Color("BackgroundCard"))
				.cornerRadius(16)
			}
			if isRefreshing {
				HStack(spacing: 10) {
					ProgressView()
					Text("Refreshing computers…").font(.subheadline)
				}
			} else if hosts.isEmpty && refreshError == nil && !sessionExpired {
				VStack(spacing: 12) {
					Image(systemName: "desktopcomputer").font(.system(size: 36))
					Text("No computers online").font(.headline)
					Text("Open Parsec on your computer and enable hosting, then refresh.")
						.font(.subheadline).multilineTextAlignment(.center)
						.foregroundColor(Color("ForegroundInactive"))
					Button("Refresh", action: refreshHosts).frame(minHeight: 44)
				}
				.frame(maxWidth: .infinity)
				.padding(.vertical, 32)
			}
			LazyVGrid(columns: hostColumns, alignment: .leading, spacing: 16) {
				ForEach(hosts) { host in hostCard(host) }
			}
			if !refreshTime.isEmpty {
				Text(refreshTime).font(.caption).foregroundColor(Color("ForegroundInactive"))
			}
		}
	}

	private func hostCard(_ host: IdentifiableHostInfo) -> some View {
		VStack(alignment: .leading, spacing: 16) {
			HStack {
				avatar(id: host.user.id)
				Spacer()
				if host.connections > 0 {
					Label("\(host.connections)", systemImage: "person.fill").font(.caption)
						.accessibilityLabel("\(host.connections) connected users")
				}
			}
			VStack(alignment: .leading, spacing: 4) {
				Text(host.hostname).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
				Text("\(host.user.name)#\(host.user.id)")
					.font(.subheadline).foregroundColor(Color("ForegroundInactive"))
					.lineLimit(2)
			}
			Button(action: { connectTo(host) }) {
				Label("Connect", systemImage: "play.fill")
					.font(.subheadline.weight(.semibold))
					.frame(maxWidth: .infinity, minHeight: 48)
					.foregroundColor(.white)
					.background(Color("AccentColor"))
					.cornerRadius(10)
			}
			.accessibilityLabel("Connect to \(host.hostname)")
		}
		.padding(20)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.background(Color("BackgroundCard"))
		.cornerRadius(16)
		.contextMenu {
			Button(action: { UIPasteboard.general.string = host.hostname }) {
				Label("Copy Name", systemImage: "doc.on.doc")
			}
		}
	}

	private func avatar(id: Int) -> some View {
		URLImage(url: URL(string: "https://parsecusercontent.com/cors-resize-image/w=96,h=96,fit=crop,background=white,q=90,f=jpeg/avatars/\(id)/avatar"), output: {
			$0.resizable().aspectRatio(contentMode: .fill)
		}, placeholder: {
			Image("IconTransparent").resizable().aspectRatio(contentMode: .fit)
		})
		.frame(width: 48, height: 48)
		.background(Color("BackgroundPrompt"))
		.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
		.accessibilityHidden(true)
	}

	private var friendList: some View {
		VStack(alignment: .leading, spacing: 16) {
			if let user = userInfo {
				Text("You").font(.headline)
				userRow(user)
			}
			Text("Friends").font(.headline)
			if friends.isEmpty {
				Text("Your Parsec friends appear here.").foregroundColor(Color("ForegroundInactive"))
			}
			ForEach(friends) { user in userRow(user) }
		}
		.frame(maxWidth: 720, alignment: .leading)
	}

	private func userRow(_ user: IdentifiableUserInfo) -> some View {
		HStack(spacing: 12) {
			avatar(id: user.id)
			Text("\(user.username)#\(user.id)").font(.subheadline).fixedSize(horizontal: false, vertical: true)
			Spacer(minLength: 0)
		}
		.padding(12)
		.background(Color("BackgroundCard"))
		.cornerRadius(14)
	}

	private func notice(_ text: String, action: String, perform: @escaping () -> Void) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(text).font(.subheadline)
			Button(action, action: perform).frame(minHeight: 44)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(16)
		.background(Color("BackgroundPrompt"))
		.cornerRadius(14)
	}

	private var pagePicker: some View {
		HStack(spacing: 12) {
			pageButton(.hosts, title: "Computers", icon: "desktopcomputer")
			pageButton(.friends, title: "Friends", icon: "person.2")
		}
		.padding(8)
		.frame(maxWidth: 520)
		.frame(maxWidth: .infinity)
		.background(Color("BackgroundTab"))
	}

	private func pageButton(_ target: Page, title: String, icon: String) -> some View {
		Button(action: { page = target }) {
			Label(title, systemImage: icon)
				.font(.subheadline.weight(.semibold))
				.frame(maxWidth: .infinity, minHeight: 48)
				.foregroundColor(Color(page == target ? "AccentColor" : "ForegroundInactive"))
				.background(page == target ? Color("AccentColor").opacity(0.12) : .clear)
				.cornerRadius(12)
		}
		.accessibilityAddTraits(page == target ? .isSelected : [])
	}

	private var connectionPrompt: some View {
		ZStack {
			Color.black.opacity(0.6).edgesIgnoringSafeArea(.all)
			VStack(spacing: 20) {
				ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Color("AccentColor")))
				Text(waitingForApproval ? "Waiting for \(connectingToName) to approve you…" : retryingConnect ? "\(connectingToName) didn't answer, trying again…" : "Connecting to \(connectingToName)…")
					.font(.headline).multilineTextAlignment(.center)
				Button("Cancel", action: cancelConnection).foregroundColor(.red).frame(minHeight: 44)
			}
			.padding(28)
			.frame(maxWidth: 360)
			.background(Color("BackgroundPrompt"))
			.cornerRadius(20)
			.padding(20)
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

private enum Page {
	case hosts
	case friends
}
