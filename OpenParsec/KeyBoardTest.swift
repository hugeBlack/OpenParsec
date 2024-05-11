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

struct TestView : View {
	var controller:ContentView?

	init(_ controller:ContentView?)
	{
		self.controller = controller
	}
	
	var body:some View
	{
		ZStack(){
			
			UIViewControllerWrapper(KeyboardTestController())
				.zIndex(3)
		}
	}
}

class KeyboardTestController:UIViewController
{
	var id = 0
	override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		self.id += 1
		print("KEY EVENT!\(self.id)")
	}
	
	override func viewDidLoad() {
		let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
				
		// Set the minimum number of touches required
		panGesture.minimumNumberOfTouches = 2
				
		// Add the gesture recognizer to your view
		view.addGestureRecognizer(panGesture)
	}
	
	
	@objc func handlePan(_ gesture: UIPanGestureRecognizer){
		if gesture.numberOfTouches == 2 {
			let translation = gesture.translation(in: view)
			
			if gesture.velocity(in: view).y < 0 && translation.y < -50 {
				// Run your function when the user uses two fingers and swipes upwards
				print("Sweep UP!")
			} else if gesture.velocity(in: view).y > 0 && translation.y > 50 {
				print("Sweep DOWN!")
			}
		}
	}
}
