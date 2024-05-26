//
//  PoinerRegion.swift
//  OpenParsec
//
//  Created by s s on 2024/5/11.
//

import Foundation
import UIKit


protocol ParsecPlayground {
	init(viewController: UIViewController, updateImage: @escaping () -> Void)
	func viewDidLoad()
	func cleanUp()
}


class ParsecViewController :UIViewController, UIPointerInteractionDelegate, UIGestureRecognizerDelegate{
	var glkView: ParsecPlayground!
	var gamePadController: GamepadController!
	var touchController: TouchController!
	var u:UIImageView?
	var lastImg: CGImage?
	override var prefersPointerLocked: Bool {
		return true
	}
	
	init() {
		super.init(nibName: nil, bundle: nil)
		
		switch SettingsHandler.streamProtocol {
		case .stcp:
			self.glkView = ParsecWebPlayground(viewController: self, updateImage: updateImage)
			break
		case .bud:
			self.glkView = ParsecGLKViewController(viewController: self, updateImage: updateImage)
			break
		}
		
		self.gamePadController = GamepadController(viewController: self)
		self.touchController = TouchController(viewController: self)
		
		
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	func updateImage() {
		if CParsec.mouseInfo.cursorImg != nil && !CParsec.mouseInfo.cursorHidden {
			if lastImg != CParsec.mouseInfo.cursorImg{
				u!.image = UIImage(cgImage: CParsec.mouseInfo.cursorImg!)
				lastImg = CParsec.mouseInfo.cursorImg!
			}

			u?.frame = CGRect(x: Int(CParsec.mouseInfo.mouseX) - CParsec.mouseInfo.cursorHotX / 2,
							  y: Int(CParsec.mouseInfo.mouseY) - CParsec.mouseInfo.cursorHotY / 2,
							  width: CParsec.mouseInfo.cursorWidth / 2,
							  height: CParsec.mouseInfo.cursorHeight / 2)
			
		} else {
			u?.image = nil
		}
	}
	
	override func viewDidLoad() {
		glkView.viewDidLoad()
		touchController.viewDidLoad()
		gamePadController.viewDidLoad()
		
		u = UIImageView(frame: CGRect(x: 0,y: 0,width: 100, height: 100))
		view.addSubview(u!)
		
		becomeFirstResponder()
		setNeedsUpdateOfPrefersPointerLocked()
		
		let pointerInteraction = UIPointerInteraction(delegate: self)
		view.addInteraction(pointerInteraction)
		
		view.isMultipleTouchEnabled = true
		view.isUserInteractionEnabled = true

		let panGestureRecognizer = UIPanGestureRecognizer(target:self, action:#selector(self.handlePanGesture(_:)))
		panGestureRecognizer.delegate = self
		view.addGestureRecognizer(panGestureRecognizer)

		
		
		// Add tap gesture recognizer for single-finger touch
		let singleFingerTapGestureRecognizer = UITapGestureRecognizer(target:self, action:#selector(handleSingleFingerTap(_:)))
		singleFingerTapGestureRecognizer.numberOfTouchesRequired = 1
		singleFingerTapGestureRecognizer.allowedTouchTypes = [0]
		view.addGestureRecognizer(singleFingerTapGestureRecognizer)

		// Add tap gesture recognizer for two-finger touch
		let twoFingerTapGestureRecognizer = UITapGestureRecognizer(target:self, action:#selector(handleTwoFingerTap(_:)))
		twoFingerTapGestureRecognizer.numberOfTouchesRequired = 2
		view.addGestureRecognizer(twoFingerTapGestureRecognizer)
//		view.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
//		view.backgroundColor = UIColor(red: 0x66, green: 0xcc, blue: 0xff, alpha: 1.0)
		
	}
	
	override func viewWillAppear(_ animated: Bool) {
		if let parent = parent {
			parent.setChildForHomeIndicatorAutoHidden(self)
			parent.setChildViewControllerForPointerLock(self)
		}
		setNeedsUpdateOfPrefersPointerLocked()
	}
	
	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		if let parent = parent {
			parent.setChildForHomeIndicatorAutoHidden(nil)
			parent.setChildViewControllerForPointerLock(nil)
		}
	}
	
	
	override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		
		for press in presses {
			CParsec.sendKeyboardMessage(event:KeyBoardKeyEvent(input: press.key, isPressBegin: true) )
		}
			
	}
	
	override func pressesEnded (_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		
		for press in presses {
			CParsec.sendKeyboardMessage(event:KeyBoardKeyEvent(input: press.key, isPressBegin: false) )
		}
			
	}
	
	@objc func handlePanGesture(_ gestureRecognizer:UIPanGestureRecognizer)
	{
		if gestureRecognizer.numberOfTouches == 2 {
			let translation = gestureRecognizer.translation(in: gestureRecognizer.view)
			
			if abs( gestureRecognizer.velocity(in: gestureRecognizer.view).y) > 2 && abs(translation.y) > 10 {
				// Run your function when the user uses two fingers and swipes upwards
				CParsec.sendWheelMsg(x: 0, y: Int32(translation.y / 2))
				return
			}
			let location = gestureRecognizer.location(in:gestureRecognizer.view)
			touchController.onTouch(typeOfTap: 1, location: location, state: gestureRecognizer.state)
		}
		

	}

	@objc func handleSingleFingerTap(_ gestureRecognizer:UITapGestureRecognizer)
	{
		let location = gestureRecognizer.location(in:gestureRecognizer.view)
		touchController.onTap(typeOfTap: 1, location: location)

	}

	@objc func handleTwoFingerTap(_ gestureRecognizer:UITapGestureRecognizer)
	{
		let location = gestureRecognizer.location(in: gestureRecognizer.view)
		touchController.onTap(typeOfTap: 3, location: location)
	}
	
	func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
		return UIPointerStyle.hidden()
	}


	func pointerInteraction(_ inter: UIPointerInteraction, regionFor request: UIPointerRegionRequest, defaultRegion: UIPointerRegion) -> UIPointerRegion? {
		let loc = request.location
		if let iv = view!.hitTest(loc, with: nil) {
			let rect = view!.convert(iv.bounds, from: iv)
			let region = UIPointerRegion(rect: rect, identifier: iv.tag)
			return region
		}
		return nil
	}
	
	override func viewDidDisappear(_ animated: Bool) {
		
	}
	
}
