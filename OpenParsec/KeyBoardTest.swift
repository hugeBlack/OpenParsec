//
//  KeyBoardTest.swift
//  OpenParsec
//
//  Created by s s on 2024/5/10.
//

import Foundation
import ParsecSDK
import UIKit
import SwiftUI
import GameController

struct TestView : View {
	var controller:ContentView?

	init(_ controller:ContentView?)
	{
		self.controller = controller
	}
	
	var body:some View
	{
			
			UIViewControllerWrapper(KeyboardTestController())
	}
}

class KeyboardTestController:UIViewController
{
	var id = 0
	override var prefersPointerLocked: Bool {
		print("Locked!!!")
		return true
	}
	
	override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		self.id += 1
		print("KEY EVENT!\(self.id)")
	}
	
	// Must be placed in viewDidAppear since parent do not exist in viewDidLoad!
	@objc override func viewWillAppear(_ animated: Bool) {
		if let parent = parent {
			parent.setChildForHomeIndicatorAutoHidden(self)
			parent.setChildViewControllerForPointerLock(self)
			print("tryLocked!")
		}
		setNeedsUpdateOfPrefersPointerLocked()
	}
	
	
	@objc override func viewDidLoad() {

		
		let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
		
		let startTime = CFAbsoluteTimeGetCurrent()
		let endTime = CFAbsoluteTimeGetCurrent()
		 
		print("代码执行时长：\((endTime - startTime)*1000) 毫秒")
		setNeedsUpdateOfPrefersPointerLocked()

		// Add the gesture recognizer to your view
		view.addGestureRecognizer(panGesture)
		
//		for mouse in GCMouse.mice() {
//			print("Found Mouse!")
//			mouse.mouseInput?.leftButton.pressedChangedHandler = {(input: GCControllerButtonInput, v: Float, pressed: Bool) in
//				print("leftButtonChanged!")
//				}
//			mouse.mouseInput?.rightButton?.pressedChangedHandler = {(input: GCControllerButtonInput, v: Float, pressed: Bool) in
//				CParsec.sendMouseMessage(<#T##button: ParsecMouseButton##ParsecMouseButton#>, <#T##x: Int32##Int32#>, <#T##y: Int32##Int32#>, <#T##pressed: Bool##Bool#>)
//				}
//			mouse.mouseInput?.mouseMovedHandler={(input: GCMouseInput, v: Float, v2: Float) in
//				print("mouseMoved!")
//				}
//		}
		
	}
	
	
	@objc func handlePan(_ gesture: UIPanGestureRecognizer){
		print("PAN!")
		setNeedsUpdateOfPrefersPointerLocked()
	}
	
	override func motionBegan(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
		print("MotionBegin!")
	}
	
}


