import SwiftUI
import ParsecSDK

struct ParsecView:View
{
	var controller:ContentView?

	@State var pollTimer:Timer?

	@State var showDCAlert:Bool = false
	@State var DCAlertText:String = "Disconnected (reason unknown)"

	@State var hideOverlay:Bool = false
	@State var showMenu:Bool = false

	@State var muted:Bool = false

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

			// Input handlers
			TouchHandlingView(handleTouch:onTouch, handleTap:onTap)
				.zIndex(1)
			UIViewControllerWrapper(KeyboardViewController())
				.zIndex(-1)

			// Overlay elements
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
								Text("Sound \(muted ? "OFF" : "ON")")
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
						Spacer()
					}
				}
				Spacer()
			}
			.zIndex(1)
		}
		.statusBar(hidden:true)
		.alert(isPresented:$showDCAlert)
		{
			Alert(title:Text(DCAlertText), dismissButton:.default(Text("Close"), action:disconnect))
		}
		.onAppear(perform:startPollTimer)
		.onDisappear(perform:stopPollTimer)
	}

	func startPollTimer()
	{
		if pollTimer != nil { return }
		pollTimer = Timer.scheduledTimer(withTimeInterval:1, repeats:true)
		{ timer in
			let status = CParsec.getStatus()
			if status != PARSEC_OK
			{
				DCAlertText = "Disconnected (code \(status.rawValue))"
				showDCAlert = true
				timer.invalidate()
			}
		}
		CParsec.setMuted(muted)
	}

	func stopPollTimer()
	{
		pollTimer!.invalidate()
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
