import SwiftUI
import ParsecSDK
import Foundation
import AVFoundation

struct ParsecStatusBar : View {
	@Binding var showMenu : Bool
	@State var metricInfo: String = "Loading..."
	@Binding var showDCAlert: Bool
	@Binding var DCAlertText: String
	@State var parsecViewController: ParsecViewController?
	@State var wasDisconnected: Bool = true
	let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

	init(showMenu: Binding<Bool>, showDCAlert: Binding<Bool>, DCAlertText: Binding<String>, parsecViewController: ParsecViewController) {
		_showMenu = showMenu
		_showDCAlert = showDCAlert
		_DCAlertText = DCAlertText
		self.parsecViewController = parsecViewController
	}
	
	var body: some View {
		// Overlay elements
		if showMenu
		{
			VStack()
			{
				Text(metricInfo)
					.frame(minWidth:200, maxWidth:.infinity, maxHeight:20)
					.multilineTextAlignment(.leading)
					.font(.system(size: 10))
					.lineSpacing(20)
					.lineLimit(nil)
			}
			.background(Rectangle().fill(Color("BackgroundPrompt").opacity(0.75)))
			.foregroundColor(Color("Foreground"))
			.frame(maxHeight: .infinity, alignment: .top)
			.zIndex(1)
			.edgesIgnoringSafeArea(.all)

		}
		EmptyView()
			.onReceive(timer) { p in
				poll()
			}
	}
	
	func poll()
	{
		if showDCAlert
		{
			return // no need to poll if we aren't connected anymore
		}
		
		var pcs = ParsecClientStatus()
		let status = CParsec.getStatusEx(&pcs)
		
		if status != PARSEC_OK
		{
			if ParsecBackgroundManager.shared.isMarkedForReconnect {
				return
			}

			// PiP: connection died (screen lock killed GPU). Kill connection+audio once,
			// subsequent polls exit via isMarkedForReconnect above.
			var pipActive = false
			if #available(iOS 15.0, *) {
				pipActive = PictureInPictureManager.shared.isPiPActive
			}
			if pipActive {
				CParsec.disconnect()
				try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
				ParsecBackgroundManager.shared.connectionDidEnd()
				ParsecBackgroundManager.shared.markForReconnect()
				wasDisconnected = true
				return
			}

			wasDisconnected = true
			DCAlertText = "Disconnected (code \(status.rawValue))"
			showDCAlert = true
			return
		}
		
		if showMenu
		{
			let str = String.fromBuffer(&pcs.decoder.0.name.0, length:16)
			metricInfo = "Decode \(String(format:"%.2f", pcs.`self`.metrics.0.decodeLatency))ms    Encode \(String(format:"%.2f", pcs.`self`.metrics.0.encodeLatency))ms    Network \(String(format:"%.2f", pcs.`self`.metrics.0.networkLatency))ms    Bitrate \(String(format:"%.2f", pcs.`self`.metrics.0.bitrate))Mbps    \(pcs.decoder.0.h265 ? "H265" : "H264") \(pcs.decoder.0.width)x\(pcs.decoder.0.height) \(pcs.decoder.0.color444 ? "4:4:4" : "4:2:0") \(str)"
		}
	}
}

// CRITICAL: This class exists to PERSIST the ParsecViewController instance across SwiftUI view updates.
// Do not remove or change to a struct. If ParsecViewController is recreated, the keyboard responder chain breaks.
class ParsecSession: ObservableObject {
    let controller: ParsecViewController
    
    init() {
        self.controller = ParsecViewController()
    }
}

struct ParsecView: View
{
	var controller:ContentView?
	
	@State var showDCAlert: Bool = false
	@State var DCAlertText: String = "Disconnected (reason unknown)"
	@State var metricInfo: String = "Loading..."
	
	@State var hideOverlay: Bool = false
	@State var showMenu: Bool = false

	@State var showKeyboard: Bool = false
	@State var zoomEnabled: Bool = false

	@State var muted: Bool = false
	@State var preferH265: Bool = true
	@State var constantFps = false
	
	@State var resolutions: [ParsecResolution]
	@State var bitrates: [Int]
	
    // Persist the VC across view updates using StateObject.
    // CRITICAL: Changing this to @State or a simple var will break the keyboard after menu interactions.
	@StateObject var session = ParsecSession()
    
    // Observer shared state for updates
    @ObservedObject var dataModel = DataManager.model
    
    // Computed property for convenience refactoring
    var parsecViewController: ParsecViewController {
        return session.controller
    }


	//@State var showDisplays: Bool = false
	
	init(_ controller: ContentView?)
	{
		self.controller = controller

		let save = SettingsHandler.saveSessionSettings
		_muted = State(initialValue: save ? SettingsHandler.savedMuted : false)
		_zoomEnabled = State(initialValue: save ? SettingsHandler.savedZoomEnabled : false)
		_constantFps = State(initialValue: save ? SettingsHandler.savedConstantFps : false)
		_resolutions = State(initialValue: ParsecResolution.resolutions)
		_bitrates = State(initialValue: ParsecResolution.bitrates)

    }
	    
    // We need to set up the callback somewhere safer than init.
    // 'onAppear' is a good place, or inside the init of ParsecSession if possible (but it doesn't have access to binding).
    // Let's use onAppear/post.

	var body: some View
	{
		ZStack()
		{
			
			UIViewControllerWrapper(self.parsecViewController)
				.zIndex(1)
				.prefersPersistentSystemOverlaysHidden()
			
			ParsecStatusBar(showMenu: $showMenu, showDCAlert: $showDCAlert, DCAlertText: $DCAlertText, parsecViewController: parsecViewController)
			
			VStack()
			{
				if !hideOverlay
				{
					HStack()
					{
						Button(action:{
							if showMenu {
								showMenu = false
							} else {
								showMenu = true
								getHostUserData()
							}
						})
						{
							Image("IconTransparent")
								.resizable()
								.aspectRatio(contentMode: .fit)
								.frame(width:48, height:48)
								.background(Rectangle().fill(Color("BackgroundPrompt").opacity(showMenu ? 0.75 : 1)))
								.cornerRadius(8)
								.opacity(showMenu ? 1 : 0.25)
						}
						.padding()
						.edgesIgnoringSafeArea(.all)
						Spacer()
					}
					if SettingsHandler.showKeyboardButton {
						HStack()
						{
							Button(action: toggleKeyboard)
							{
								Image(systemName: "keyboard")
									.resizable()
									.aspectRatio(contentMode: .fit)
									.frame(width:32, height:32)
									.foregroundColor(Color("Foreground"))
									.padding(8)
									.background(Rectangle().fill(Color("BackgroundPrompt").opacity(showKeyboard ? 0.75 : 0.5)))
									.cornerRadius(8)
							}
							.padding(.leading)
							.edgesIgnoringSafeArea(.all)
							Spacer()
						}
					}

				}
				if showMenu
				{	
					HStack()
					{
						VStack(spacing:3)
						{
							Button(action:disableOverlay)
							{
								Text("Hide Overlay")
									.padding(8)
									.frame(maxWidth:.infinity)
									.multilineTextAlignment(.center)
							}
							Button(action: toggleMute)
							{
								Text("Sound: \(muted ? "OFF" : "ON")")
									.padding(8)
									.frame(maxWidth:.infinity)
									.multilineTextAlignment(.center)
							}
							Menu() {
								ForEach(resolutions, id: \.self) { resolution in
									Button(action: {
										changeResolution(res: resolution)
									}) {
										if resolution.width == dataModel.resolutionX && resolution.height == dataModel.resolutionY {
											Label(resolution.desc, systemImage: "checkmark")
										} else {
											Text(resolution.desc)
										}
									}
								}
							} label: {
								Text("Resolution")
									.padding(8)
									.frame(maxWidth:.infinity)
									.multilineTextAlignment(.center)
							}
							Menu() {
								ForEach(bitrates, id: \.self) { bitrate in
									Button(action: {
										changeBitRate(bitrate: bitrate)
									}) {
                                        if bitrate == dataModel.bitrate {
                                            Label("\(bitrate) Mbps", systemImage: "checkmark")
                                        } else {
                                            Text("\(bitrate) Mbps")
                                        }
									}
								}
							} label: {
								Text("Bitrate")
									.padding(8)
									.frame(maxWidth:.infinity)
									.multilineTextAlignment(.center)
							}
							if (DataManager.model.displayConfigs.count > 1) {
								Menu() {
									Button("Auto") {
										changeDisplay(displayId: "none")
									}
									ForEach(DataManager.model.displayConfigs, id: \.self) { config in
										Button("\(config.name) \(config.adapterName)") {
											changeDisplay(displayId: config.id)
										}
									}
								} label: {
									Text("Switch Display")
										.padding(8)
										.frame(maxWidth:.infinity)
										.multilineTextAlignment(.center)
								}
							}

							Button(action: toggleConstantFps)
							{
								Text("Constant FPS: \(constantFps ? "ON" : "OFF")")
									.padding(8)
									.frame(maxWidth:.infinity)
									.multilineTextAlignment(.center)
							}
							Button(action: toggleZoom)
							{
								Text("Zoom: \(zoomEnabled ? "ON" : "OFF")")
									.padding(8)
									.frame(maxWidth:.infinity)
									.multilineTextAlignment(.center)
							}
							Rectangle()
								.fill(Color("Foreground"))
								.opacity(0.25)
								.frame(height:1)
							Button(action: { disconnect()})
							{
								Text("Disconnect")
									.foregroundColor(.red)
									.padding(8)
									.frame(maxWidth:.infinity)
									.multilineTextAlignment(.center)
							}
						}
						.background(Rectangle().fill(Color("BackgroundPrompt").opacity(0.75)))
						.foregroundColor(Color("Foreground"))
						.frame(maxWidth:175)
						.cornerRadius(8)
						.padding(.horizontal)
						//.edgesIgnoringSafeArea(.all)
						Spacer()
					}
				}
				Spacer()
			}
			.zIndex(2)
		}
		.statusBarHidden(SettingsHandler.hideStatusBar)
		.alert(isPresented:$showDCAlert)
		{
			Alert(title: Text(DCAlertText), dismissButton:.default(Text("Close"), action:{disconnect()}))
		}
		.onAppear(perform:post)
		.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ParsecBackgroundDisconnect"))) { _ in
			if #available(iOS 15.0, *) {
				if PictureInPictureManager.shared.isPiPActive {
					return
				}
			}
			disconnect(isBackgroundDisconnect: true)
		}
		.edgesIgnoringSafeArea(.all)

	}
	
	func post()
	{
		ParsecBackgroundManager.shared.onShouldDisconnect = {
			NotificationCenter.default.post(name: NSNotification.Name("ParsecBackgroundDisconnect"), object: nil)
		}
		if #available(iOS 15.0, *) {
			PictureInPictureManager.shared.onPiPStopped = { [self] in
				if UIApplication.shared.applicationState != .active {
					// Synchronous — DispatchQueue.main.async may never execute if iOS suspends the app
					CParsec.disconnect()
					try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
					ParsecBackgroundManager.shared.markForReconnect()
					DispatchQueue.main.async {
						self.disconnect(isBackgroundDisconnect: true)
					}
				} else {
					if ParsecBackgroundManager.shared.isReconnecting {
						return
					}
					// Check actual Parsec status — timers don't reliably fire in background
					var pcs = ParsecClientStatus()
					let currentStatus = CParsec.getStatusEx(&pcs)
					if currentStatus != PARSEC_OK || ParsecBackgroundManager.shared.isMarkedForReconnect {
						CParsec.disconnect()
						try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
						ParsecBackgroundManager.shared.markForReconnect()
						DispatchQueue.main.async {
							self.disconnect(isBackgroundDisconnect: true)
						}
					}
				}
			}
			PictureInPictureManager.shared.onPiPStartFailed = { [self] in
				if UIApplication.shared.applicationState != .active {
					ParsecBackgroundManager.shared.markForReconnect()
					DispatchQueue.main.async {
						self.disconnect(isBackgroundDisconnect: true)
					}
				}
			}
		}

		CParsec.applyConfig()
		CParsec.setMuted(muted)
		parsecViewController.setZoomEnabled(zoomEnabled)

		if SettingsHandler.saveSessionSettings {
			DataManager.model.constantFps = constantFps
		}

		let screenSize: CGSize = self.parsecViewController.view.frame.size
		let scaleFactor = UIScreen.main.nativeScale
		ParsecResolution.updateClientResolution(width: Int(screenSize.width * scaleFactor), height: Int(screenSize.height * scaleFactor))

		getHostUserData()

		hideOverlay = SettingsHandler.noOverlay

        parsecViewController.onKeyboardVisibilityChanged = { visible in
            showKeyboard = visible
        }

		parsecViewController.setKeyboardVisible(showKeyboard)
	}
	
	
	func disableOverlay()
	{
		hideOverlay = true
		showMenu = false
	}
	
	func toggleMute()
	{
		muted.toggle()
		CParsec.setMuted(muted)
		if SettingsHandler.saveSessionSettings { SettingsHandler.savedMuted = muted }
	}

		/*func genDisplaySheet() -> ActionSheet
	{
		let len:Int = 16
		var outputs = [ParsecOutput?](repeating:nil, count:len)
		ParsecGetOutputs(&outputs, UInt32(len))
		print("Listing \(outputs.count) displays")

		func getDeviceName(_ output:ParsecOutput) -> String
		{
			return withUnsafePointer(to:output.device)
			{
				$0.withMemoryRebound(to: UInt8.self, capacity:MemoryLayout.size(ofValue:$0))
				{
					String(cString:$0)
				}
			}
		}

		let buttons = outputs.enumerated().map
		{ i, output in
			Alert.Button.default(Text("\(i) - \(getDeviceName(output))"), action:{print("Selected device \(i)")})
		}
		return ActionSheet(title: Text("Select a Display:"), buttons:buttons + [Alert.Button.cancel()])
	}*/

	func disconnect(isBackgroundDisconnect: Bool = false)
	{
		if !isBackgroundDisconnect {
			ParsecBackgroundManager.shared.disableAutoReconnect()
		}

		if #available(iOS 15.0, *) {
			PictureInPictureManager.shared.teardown()
		}

		CParsec.disconnect()
		self.parsecViewController.glkView.cleanUp()

		parsecViewController.scrollView.zoomScale = 1.0
		parsecViewController.scrollView.contentOffset = .zero

		if let c = controller
		{
			c.setView(.main)
		}
	}
	
	func changeResolution(res: ParsecResolution) {
		SettingsHandler.resolution = res
		DispatchQueue.main.async {
			DataManager.model.resolutionX = res.width
			DataManager.model.resolutionY = res.height
		}

		// Parsec's host honours bitrate / FPS / output via setVideoConfig
		// user-data, but NOT resolution — that field is only read at
		// ParsecClientConnect time. To actually change the streaming
		// resolution we have to disconnect + reconnect with the new
		// ParsecClientConfig. If we don't have a peer to reconnect to
		// (shouldn't happen mid-session), fall back to just pushing the
		// user-data update.
		guard let peerID = CParsec.lastConnectedPeerID else {
			DispatchQueue.main.async {
				CParsec.updateHostVideoConfig()
			}
			return
		}

		DispatchQueue.main.async {
			self.parsecViewController.glkView.cleanUp()
			CParsec.disconnect()
		}
		// Brief pause to let the SDK fully tear down before re-issuing
		// ParsecClientConnect with the new resolution. 300 ms matches the
		// debounce we already use elsewhere.
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
			_ = CParsec.connect(peerID)
			CParsec.applyConfig()
		}
	}

	func changeBitRate(bitrate: Int) {
		SettingsHandler.bitrate = bitrate

		DispatchQueue.main.async {
			DataManager.model.bitrate = bitrate
			CParsec.updateHostVideoConfig()
		}
	}
	
	func toggleConstantFps() {
		DispatchQueue.main.async {
			DataManager.model.constantFps.toggle()
			constantFps = DataManager.model.constantFps
			CParsec.updateHostVideoConfig()
			if SettingsHandler.saveSessionSettings { SettingsHandler.savedConstantFps = constantFps }
		}
	}

	func toggleKeyboard() {
		DispatchQueue.main.async {
			showKeyboard.toggle()
			parsecViewController.setKeyboardVisible(showKeyboard)
		}
	}
	
	func toggleZoom() {
		DispatchQueue.main.async {
			zoomEnabled.toggle()
			parsecViewController.setZoomEnabled(zoomEnabled)
			if SettingsHandler.saveSessionSettings { SettingsHandler.savedZoomEnabled = zoomEnabled }
		}
	}
	
	func changeDisplay(displayId: String) {
		DispatchQueue.main.async {
			DataManager.model.output = displayId
			// Persist so the next connect can auto-restore this choice once
			// the host enumerates displays (user-data event 12). "none" is
			// the "Auto" pseudo-id and isn't worth remembering.
			SettingsHandler.savedDisplayOutput = (displayId == "none") ? "" : displayId
			CParsec.updateHostVideoConfig()
		}
	}
	
	func getHostUserData() {
		let data = "".data(using: .utf8)!
		CParsec.sendUserData(type: .getVideoConfig, message: data)
		CParsec.sendUserData(type: .getAdapterInfo, message: data)
	}

}

// from https://github.com/utmapp/UTM/blob/117e3a962f2f46f7d847632d65fa7a85a2bb0cfa/Platform/iOS/VMWindowView.swift#L314
private extension View {
	func prefersPersistentSystemOverlaysHidden() -> some View {
		if #available(iOS 16, *) {
			return self.persistentSystemOverlays(.hidden)
		} else {
			return self
		}
	}
}


