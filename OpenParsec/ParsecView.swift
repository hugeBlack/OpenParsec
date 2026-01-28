import SwiftUI
import ParsecSDK
import Foundation

import OSLog
import Combine

struct ParsecStatusBar : View {
	@Binding var showMenu : Bool
	@State var metricInfo: String = "Loading..."
	@Binding var showDCAlert: Bool
	@Binding var DCAlertText: String

	@State var parsecViewController: ParsecViewController?

	@State private var timerCancellable: AnyCancellable?

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
					.frame(minWidth:200, maxWidth:.infinity)
					.multilineTextAlignment(.leading)
					.font(.system(size: 10))
					.lineSpacing(4)
					.lineLimit(nil)
			}
			.background(Rectangle().fill(Color("BackgroundPrompt").opacity(0.75)))
			.foregroundColor(Color("Foreground"))
			.frame(maxHeight: .infinity, alignment: .top)
			.zIndex(1)
			.edgesIgnoringSafeArea(.all)
			.onAppear {
				timerCancellable = Timer
					.publish(every: 0.2, on: .main, in: .common)
					.autoconnect()
					.sink { _ in
						poll()
					}
			}
			.onDisappear {
				timerCancellable?.cancel()
				timerCancellable = nil
			}
			
		}
		EmptyView()


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
			DCAlertText = "Disconnected (code \(status.rawValue))"
			showDCAlert = true
			return
		}

		// FIXME: This may cause memory leak?
		
		if showMenu
		{
			
			let decodeLatency = String(format: "%.2f", pcs.`self`.metrics.0.decodeLatency)
            let encodeLatency = String(format: "%.2f", pcs.`self`.metrics.0.encodeLatency)
            let networkLatency = String(format: "%.2f", pcs.`self`.metrics.0.networkLatency)
            let bitrate = String(format: "%.2f", pcs.`self`.metrics.0.bitrate)

            let codec = pcs.decoder.0.h265 ? "H265" : "H264"

			
            let resolution = "\(pcs.decoder.0.width)x\(pcs.decoder.0.height)"
            let colorFormat = pcs.decoder.0.color444 ? "4:4:4" : "4:2:0"

			let decoderName = String.fromBuffer(&pcs.decoder.0.name.0, length: 16)
			
			// ✅ 新增 FPS 參數（舉例，你的 GLK FPS）
			let glkFPS = SettingsHandler.preferredFramesPerSecond
            let glkCFPS = ParsecRenderCenter.shared.currentFPS()
			// 查增量實際 FPS（可每秒刷新）
			let deltaFPS = ParsecRenderCenter.shared.deltaFPS()



			

			let metricsArray = [
			    "Decode \(decodeLatency)ms",
			    "Encode \(encodeLatency)ms",
			    "Network \(networkLatency)ms",
			    "Bitrate \(bitrate)Mbps",
			    "\(codec) \(resolution) \(colorFormat)",
			    decoderName,
			    "\nCFPS \(glkCFPS)",   // 如果 glkCFPS 是 optional
			    "GLK FPS \(glkFPS)",
				"deltaFPS \(String(format: "%.2f", deltaFPS))",
			]

			metricInfo = metricsArray.joined(separator: " ")

		

			
		}

//		if let pc = parsecViewController {
//			// Logic handled in ParsecViewController.scrollView
//		}
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
	
	init(_ controller:ContentView?)
	{
		self.controller = controller
		// parsecViewController logic moved to ParsecSession
        
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
								ParsecRenderCenter.shared.getHostUserData()
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
							Button(action:disconnect)
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
			Alert(title: Text(DCAlertText), dismissButton:.default(Text("Close"), action:disconnect))
		}
		.onAppear(perform:post)
		.edgesIgnoringSafeArea(.all)

	}
	
	func post()
	{

	
		hideOverlay = SettingsHandler.noOverlay

        // Setup callback to update local state
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
		ParsecRenderCenter.shared.setMuted(muted)
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
	
	func disconnect()
	{
		ParsecRenderCenter.shared.shutdown()

		parsecViewController.keyboardVisible = false

		parsecViewController.scrollView.zoomScale = 1.0
		parsecViewController.scrollView.contentOffset = .zero

		if let c = controller
		{
			c.setView(.main)
		}
	}
	
	func changeResolution(res: ParsecResolution) {
		DataManager.model.resolutionX = res.width
		DataManager.model.resolutionY = res.height

		ParsecRenderCenter.shared.requestResolutionUpdate()
		ParsecRenderCenter.shared.applyIfPossible()

	}

	func changeBitRate(bitrate: Int) {
		DataManager.model.bitrate = bitrate

		ParsecRenderCenter.shared.requestBitrateUpdate()
	}
	
	func toggleConstantFps() {
		DispatchQueue.main.async {
			DataManager.model.constantFps.toggle()
			constantFps = DataManager.model.constantFps
			CParsec.updateHostVideoConfig()
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
		}
	}
	
	func changeDisplay(displayId: String) {
		DispatchQueue.main.async {
			DataManager.model.output = displayId
			CParsec.updateHostVideoConfig()
		}
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
