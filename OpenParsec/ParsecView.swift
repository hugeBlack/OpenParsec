import SwiftUI
import ParsecSDK

struct ParsecView:View
{
	var controller:ContentView?

	@State var pollTimer:Timer?
	//@State var audioPollTimer:Timer?
	
	@State var showDCAlert:Bool = false
	@State var DCAlertText:String = "Disconnected (reason unknown)"
    @State var MetricInfo1:String = "None"
	
	@State var hideOverlay:Bool = false
	@State var showMenu:Bool = false

	@State var muted:Bool = false
    @State var preferH265:Bool = true
	
	init(_ controller:ContentView?)
	{
		self.controller = controller
	}

	var body:some View
	{
		ZStack()
		{
			// Stream view controller
			ParsecGLKViewController()
				.zIndex(0)
                .edgesIgnoringSafeArea(.all)
				//.onAppear(perform:startAudioPollTimer)
				//.onDisappear(perform:stopAudioPollTimer)
				
				
			// Input handlers
			TouchHandlingView(handleTouch:onTouch, handleTap:onTap)
				.zIndex(2)
			UIViewControllerWrapper(KeyboardViewController())
				.zIndex(-1)
            UIViewControllerWrapper(GamepadViewController())
			    .zIndex(-2)
				
			// Overlay elements
			if showMenu
            {
                VStack()
                {
                    Text("\(MetricInfo1)")
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
			
			VStack()
			{
				if !hideOverlay
				{
					HStack()
					{
						Button(action:{ showMenu.toggle() })
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
						VStack(spacing:4)
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
							Button(action:toggleH265)
							{
								Text("Decoder: \(preferH265 ? "prefer H265" : "H264")")
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
		.statusBar(hidden:true)
		.alert(isPresented:$showDCAlert)
		{
			Alert(title:Text(DCAlertText), dismissButton:.default(Text("Close"), action:disconnect))
		}
		.onAppear(perform:startPollTimer)
		.onDisappear(perform:stopPollTimer)
		.edgesIgnoringSafeArea(.all)
	}

    func FromBuf(ptr: UnsafeMutablePointer<CChar>, length len: Int) -> String {
        // convert the bytes using the UTF8 encoding
        //let theString = NSString(bytes: ptr, length: len, encoding: NSUTF8StringEncoding)
		let theString = NSString(bytes: ptr, length: len, encoding: NSASCIIStringEncoding)
        return theString as! String
    }
	
	func startPollTimer()
	{
		if pollTimer != nil { return }
		
		pollTimer = Timer.scheduledTimer(withTimeInterval:1, repeats:true)
		{ timer in
		
		    if showMenu == false
			{
			    //var pcs = ParsecClientStatus()
		        let status = CParsec.getStatus()
		        if status != PARSEC_OK
		        {
		        	DCAlertText = "Disconnected (code \(status.rawValue))"
		        	showDCAlert = true
		        	timer.invalidate()
		        }
			}
			else
			{
			    var pcs = ParsecClientStatus()
			    let status = CParsec.getStatusEx(pcs:&pcs)
			    if status != PARSEC_OK
			    {
			    	DCAlertText = "Disconnected (code \(status.rawValue))"
			    	showDCAlert = true
			    	timer.invalidate()
			    }
			    
	            let str = FromBuf(ptr: &pcs.decoder.0.name.0, length: 16)
			    MetricInfo1 = "Decode \(String(format:"%.2f", pcs.`self`.metrics.0.decodeLatency))ms    Encode \(String(format:"%.2f", pcs.`self`.metrics.0.encodeLatency))ms    Network \(String(format:"%.2f", pcs.`self`.metrics.0.networkLatency))ms    Bitrate \(String(format:"%.2f", pcs.`self`.metrics.0.bitrate))Mbps    \(pcs.decoder.0.h265 ? "H265" : "H264") \(pcs.decoder.0.width)x\(pcs.decoder.0.height) \(pcs.decoder.0.color444 ? "4:4:4" : "4:2:0") \(str)"	    
			}
		}
        
        CParsec.setMuted(muted)
	}

	func stopPollTimer()
	{
		pollTimer!.invalidate()
	}
	
	/*func startAudioPollTimer()
	{
		if audioPollTimer != nil { return }
		
		audioPollTimer = Timer.scheduledTimer(withTimeInterval:0.01666667, repeats:true)
		{ timer in
		
		    CParsec.pollAudio()
		}
	}

	func stopAudioPollTimer()
	{
		audioPollTimer!.invalidate()
	}*/
	
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

    func toggleH265()
	{
		preferH265.toggle()
		CParsec.setH265(preferH265)
	}
	
	func disconnect()
	{
		CParsec.disconnect()

		if let c = controller
		{
			c.setView(.main)
		}
	}

	func onTouch(typeOfTap:ParsecMouseButton, location:CGPoint, state:UIGestureRecognizer.State)
	{
		// Log the touch location
		print("Touch location: \(location)")
		print("Touch type: \(typeOfTap)")
		print("Touch state: \(state)")

		// print("Touch finger count:" \(pointerId))
		// Convert the touch location to the host's coordinate system
		let screenWidth = UIScreen.main.bounds.width
		let screenHeight = UIScreen.main.bounds.height
		let x = Int32(location.x * CGFloat(CParsec.hostWidth) / screenWidth)
		let y = Int32(location.y * CGFloat(CParsec.hostHeight) / screenHeight)

		// Log the screen and host dimensions and calculated coordinates
		print("Screen dimensions: \(screenWidth) x \(screenHeight)")
		print("Host dimensions: \(CParsec.hostWidth) x \(CParsec.hostHeight)")
		print("Calculated coordinates: (\(x), \(y))")

		// Send the mouse input to the host
		switch state
		{
			case .began:
				CParsec.sendMouseMessage(typeOfTap, x, y, true)
			case .changed:
				CParsec.sendMousePosition(x, y)
			case .ended, .cancelled:
				CParsec.sendMouseMessage(typeOfTap, x, y, false)
			default:
				break
		}
	}

	func onTap(typeOfTap:ParsecMouseButton, location:CGPoint)
	{
		// Log the touch location
		print("Touch location: \(location)")
		print("Touch type: \(typeOfTap)")

		// print("Touch finger count:" \(pointerId))
		// Convert the touch location to the host's coordinate system
		let screenWidth = UIScreen.main.bounds.width
		let screenHeight = UIScreen.main.bounds.height
		let x = Int32(location.x * CGFloat(CParsec.hostWidth) / screenWidth)
		let y = Int32(location.y * CGFloat(CParsec.hostHeight) / screenHeight)

		// Log the screen and host dimensions and calculated coordinates
		print("Screen dimensions: \(screenWidth) x \(screenHeight)")
		print("Host dimensions: \(CParsec.hostWidth) x \(CParsec.hostHeight)")
		print("Calculated coordinates: (\(x), \(y))")

		// Send the mouse input to the host
		CParsec.sendMouseMessage(typeOfTap, x, y, true)
		CParsec.sendMouseMessage(typeOfTap, x, y, false)
	}

	func handleKeyCommand(sender:UIKeyCommand)
	{
		CParsec.sendKeyboardMessage(sender:sender)
	}
}
