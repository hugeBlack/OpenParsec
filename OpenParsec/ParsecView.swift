import SwiftUI
import ParsecSDK
import Foundation

struct ParsecStatusBar : View {
	@Binding var showMenu : Bool
	@State var metricInfo:String = "Loading..."
	@Binding var showDCAlert:Bool
	@Binding var DCAlertText:String
	let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
	
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
			DCAlertText = "Disconnected (code \(status.rawValue))"
			showDCAlert = true
			return
		}

		// FIXME: This may cause memory leak?
		
		if showMenu
		{
			let str = String.fromBuffer(&pcs.decoder.0.name.0, length:16)
			metricInfo = "Decode \(String(format:"%.2f", pcs.`self`.metrics.0.decodeLatency))ms    Encode \(String(format:"%.2f", pcs.`self`.metrics.0.encodeLatency))ms    Network \(String(format:"%.2f", pcs.`self`.metrics.0.networkLatency))ms    Bitrate \(String(format:"%.2f", pcs.`self`.metrics.0.bitrate))Mbps    \(pcs.decoder.0.h265 ? "H265" : "H264") \(pcs.decoder.0.width)x\(pcs.decoder.0.height) \(pcs.decoder.0.color444 ? "4:4:4" : "4:2:0") \(str)"
		}
	}
}

struct ParsecView:View
{
	var controller:ContentView?
	
	@State var showDCAlert:Bool = false
	@State var DCAlertText:String = "Disconnected (reason unknown)"
    @State var metricInfo:String = "Loading..."
	
	@State var hideOverlay:Bool = false
	@State var showMenu:Bool = false

	@State var muted:Bool = false
    @State var preferH265:Bool = true
	@State var constantFps = false
	
	@State var resolutions : [ParsecResolution]
	@State var bitrates : [Int]
	
	var parsecViewController : ParsecViewController!
	
	
	//@State var showDisplays:Bool = false
	
	init(_ controller:ContentView?)
	{
		self.controller = controller
		parsecViewController = ParsecViewController()
		_resolutions = State(initialValue: ParsecResolution.resolutions)
		_bitrates = State(initialValue: ParsecResolution.bitrates)
	}

	var body:some View
	{
		ZStack()
		{

			
			// Input handlers
//			TouchHandlingView(handleTouch:onTouch, handleTap:onTap)
//				.zIndex(2)

//            UIViewControllerWrapper(GamepadViewController())
//			    .zIndex(1)
//			
//			// Stream view controller
//			//switch SettingsHandler.renderer
//			//{
//				//case .opengl:
//			UIViewControllerWrapper(ParsecGLKViewController(onBeforeRender:poll))
////			ParsecGLKViewController(onBeforeRender:poll)
//						.zIndex(0)
//						.edgesIgnoringSafeArea(.all)
				//case .metal:
				//	Text("Metal is a work in progress, check back soon!")
				//		.background(Color.black)
				//		.foregroundColor(.white)
					/*ParsecMetalViewController(onBeforeRender:poll)
						.zIndex(0)
						.edgesIgnoringSafeArea(.all)*/
			//}
			
			
			UIViewControllerWrapper(self.parsecViewController)
				.zIndex(1)
			
			ParsecStatusBar(showMenu: $showMenu, showDCAlert: $showDCAlert, DCAlertText: $DCAlertText)
			
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
									.padding(12)
									.frame(maxWidth:.infinity)
									.multilineTextAlignment(.center)
							}
							Button(action:toggleMute)
							{
								Text("Sound: \(muted ? "OFF" : "ON")")
									.padding(12)
									.frame(maxWidth:.infinity)
									.multilineTextAlignment(.center)
							}
							Menu() {
								ForEach(resolutions, id: \.self) { resolution in
									Button(resolution.desc) {
										changeResolution(res: resolution)
									}
								}
							} label: {
								Text("Resolution")
									.padding(12)
									.frame(maxWidth:.infinity)
									.multilineTextAlignment(.center)
							}
							Menu() {
								ForEach(bitrates, id: \.self) { bitrate in
									Button("\(bitrate) Mbps") {
										changeBitRate(bitrate: bitrate)
									}
								}
							} label: {
								Text("Bitrate")
									.padding(12)
									.frame(maxWidth:.infinity)
									.multilineTextAlignment(.center)
							}
							Button(action:toggleConstantFps)
							{
								Text("Constant FPS: \(constantFps ? "ON" : "OFF")")
									.padding(12)
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
									.padding(12)
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
			Alert(title:Text(DCAlertText), dismissButton:.default(Text("Close"), action:disconnect))
		}
		.onAppear(perform:post)
		.edgesIgnoringSafeArea(.all)

	}
	
	func post()
	{
		CParsec.applyConfig()
		CParsec.setMuted(muted)
		
		// set client resolution
		let screenSize: CGSize = self.parsecViewController.view.frame.size
		let scaleFactor = UIScreen.main.nativeScale
		ParsecResolution.resolutions[1].width = Int(screenSize.width * scaleFactor)
		ParsecResolution.resolutions[1].height = Int(screenSize.height * scaleFactor)
		
		getHostUserData()
		
		hideOverlay = SettingsHandler.noOverlay
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
				$0.withMemoryRebound(to:UInt8.self, capacity:MemoryLayout.size(ofValue:$0))
				{
					String(cString:$0)
				}
			}
		}

		let buttons = outputs.enumerated().map
		{ i, output in
			Alert.Button.default(Text("\(i) - \(getDeviceName(output))"), action:{print("Selected device \(i)")})
		}
		return ActionSheet(title:Text("Select a Display:"), buttons:buttons + [Alert.Button.cancel()])
	}*/
	
	func disconnect()
	{
		CParsec.disconnect()
		self.parsecViewController.glkView.cleanUp()

		if let c = controller
		{
			c.setView(.main)
		}
	}
	
	func changeResolution(res: ParsecResolution) {
		DataManager.model.resolutionX = res.width
		DataManager.model.resolutionY = res.height
		CParsec.updateHostVideoConfig()
	}

	func changeBitRate(bitrate: Int) {
		DataManager.model.bitrate = bitrate
		CParsec.updateHostVideoConfig()
	}
	
	func toggleConstantFps() {
		DataManager.model.constantFps.toggle()
		constantFps = DataManager.model.constantFps
		CParsec.updateHostVideoConfig()
	}
	
	func getHostUserData() {
		let data = "".data(using: .utf8)!
		CParsec.sendUserData(type: .getVideoConfig, message: data)
	}


//	func handleKeyCommand(sender:UIKeyCommand)
//	{
//		CParsec.sendKeyboardMessage(sender:sender)
//	}
}
