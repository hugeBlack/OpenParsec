//
//  ParsecWebPlayground.swift
//  OpenParsec
//
//  Created by s s on 2024/5/19.
//

import Foundation
import UIKit


class ParsecWebPlayground : ParsecPlayground {
	let viewController : UIViewController
	let updateImage : () -> Void
	let imgView: UIImageView
	var updateTimer: Timer?
	weak var parsec : ParsecWeb?
	
	required init(viewController: UIViewController, updateImage: @escaping () -> Void) {
		self.viewController = viewController
		self.updateImage = updateImage
		
		imgView = UIImageView()

		self.parsec = (CParsec.getImpl() as! ParsecWeb)
	}
	
	func viewDidLoad() {
		CParsec.setFrame(UIScreen.main.bounds.width, UIScreen.main.bounds.height, 1.0)
		updateTimer = Timer.scheduledTimer(timeInterval: 0.016, target: self, selector: #selector(updateFrame), userInfo: nil, repeats: true)
		
		imgView.contentMode = .scaleAspectFit
		let frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
		imgView.frame = frame

		viewController.view.addSubview(imgView)
	}
	
	@objc func updateFrame() {
		
		if let data = parsec?.buffer.decodedVideoBuffer.dequeue() {
			imgView.image = data.image
			updateImage()
		}
	}
	
	func cleanUp() {
		updateTimer?.invalidate()
	}
	
	
}
