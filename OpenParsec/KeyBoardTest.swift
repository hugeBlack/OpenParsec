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
import WebRTC

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
	func webRTCClient(_ client: WebRTCClient, didDiscoverLocalCandidate candidate: RTCIceCandidate) {
		
	}
	
	func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState) {
		
	}
	
	func webRTCClient(_ client: WebRTCClient, didReceiveData data: Data) {
		
	}
	
	var id = 0
	override var prefersPointerLocked: Bool {
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
		
		let p = ParsecWeb()
		p.connect("2fud0XnqknMBmau7n2f8x42IUuT")
		
	}
	
	
	@objc func handlePan(_ gesture: UIPanGestureRecognizer){
		print("PAN!")
		setNeedsUpdateOfPrefersPointerLocked()
	}
	
}


