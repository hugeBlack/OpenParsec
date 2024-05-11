//import SwiftUI
//import GLKit
//
//struct ParsecGLKViewController:UIViewControllerRepresentable
//{
//	let glkView = GLKView()
//	let glkViewController = GLKViewController()
//	let onBeforeRender:() -> Void
//
//	func makeCoordinator() -> ParsecGLKRenderer
//	{
//		ParsecGLKRenderer(glkView, glkViewController, onBeforeRender)
//	}
//
//	func makeUIViewController(context:UIViewControllerRepresentableContext<ParsecGLKViewController>) -> GLKViewController
//	{
//		glkView.context = EAGLContext(api:.openGLES3)!
//		glkViewController.view = glkView
//		glkViewController.preferredFramesPerSecond = 60
//		return glkViewController
//	}
//
//	func updateUIViewController(_ uiViewController:GLKViewController, context:UIViewControllerRepresentableContext<ParsecGLKViewController>) { }
//}

import UIKit
import GLKit

class ParsecGLKViewController: UIViewController {

	var glkView: GLKView!
	let glkViewController = GLKViewController()
	var glkRenderer: ParsecGLKRenderer!
	let onBeforeRender:() -> Void

	init(onBeforeRender: @escaping () -> Void) {
		self.onBeforeRender = onBeforeRender
		super.init(nibName: nil, bundle: nil)
		
	}

	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		glkView = GLKView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: self.view.bounds.size.height))
		glkRenderer = ParsecGLKRenderer(glkView, glkViewController, onBeforeRender)
		self.view.addSubview(glkView)
		setupGLKViewController()

	}

	private func setupGLKViewController() {
		glkView.context = EAGLContext(api: .openGLES3)!
		glkViewController.view = glkView
		glkViewController.preferredFramesPerSecond = 60
		addChild(glkViewController)
		view.addSubview(glkViewController.view)
		glkViewController.didMove(toParent: self)
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
	
}
