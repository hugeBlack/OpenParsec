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
			.ignoresSafeArea(.all, edges: .all)
	}
}

class KeyboardTestController:UIViewController
{
	var id = 0
	
	
	init() {
		
		super.init(nibName: nil, bundle: nil)
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
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
		
	}
	
	
	
	@objc func handlePan(_ gesture: UIPanGestureRecognizer){
		print("PAN!")
		setNeedsUpdateOfPrefersPointerLocked()
		
	}
	
}


