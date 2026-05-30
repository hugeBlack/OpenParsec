//import SwiftUI
//import GLKit
//
//struct ParsecGLKViewController: UIViewControllerRepresentable
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
//	func makeUIViewController(context: UIViewControllerRepresentableContext<ParsecGLKViewController>) -> GLKViewController
//	{
//		glkView.context = EAGLContext(api:.openGLES3)!
//		glkViewController.view = glkView
//		glkViewController.preferredFramesPerSecond = 60
//		return glkViewController
//	}
//
//	func updateUIViewController(_ uiViewController:GLKViewController, context: UIViewControllerRepresentableContext<ParsecGLKViewController>) { }
//}

import UIKit
import GLKit

class ParsecGLKViewController : ParsecPlayground {

	var glkView: GLKView!
	let glkViewController = GLKViewController()
	var glkRenderer: ParsecGLKRenderer!
	let updateImage:() -> Void
	
	let viewController: UIViewController
	
	required init(viewController: UIViewController, updateImage: @escaping () -> Void) {
		self.viewController = viewController
		self.updateImage = updateImage
	}

	public func viewDidLoad() {
		glkView = GLKView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height))
		glkRenderer = ParsecGLKRenderer(glkView, glkViewController, updateImage)
		self.viewController.view.addSubview(glkView)
		setupGLKViewController()
		

	}

	private func setupGLKViewController() {
		glkView.context = EAGLContext(api: .openGLES3)!
		// Track the superview's bounds so the drawable can't desync / go
		// zero-size when the view is moved between parents or the layout
		// changes on screen return (R4). updateSize still drives explicit
		// resolution changes; this just keeps the surface pinned otherwise.
		glkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		glkViewController.view = glkView

		// Use configured FPS or device max (for ProMotion displays)
		let fps = SettingsHandler.preferredFramesPerSecond
		if fps == 0 {
			// Use device's maximum refresh rate (120Hz on ProMotion iPads)
			glkViewController.preferredFramesPerSecond = Int(UIScreen.main.maximumFramesPerSecond)
		} else {
			glkViewController.preferredFramesPerSecond = fps
		}

		self.viewController.addChild(glkViewController)
		self.viewController.view.addSubview(glkViewController.view)
		self.glkViewController.didMove(toParent: self.viewController)
	}
	
	var eaglContext: EAGLContext? {
		return glkView?.context
	}

	// Symmetric stop: pause the CADisplayLink-driven render loop so
	// glkView(_:drawIn:) stops being called. Used when the surface is going
	// off screen; resume() reverses it.
	func cleanUp() {
		glkViewController.isPaused = true
	}

	// Idempotent render resume. Safe to call repeatedly. Makes the EAGL
	// context current on the main thread (where GLKViewController renders),
	// unpauses the loop LAST (Apple's ordering rule), then forces one frame
	// so a stale/blank framebuffer repaints immediately instead of waiting
	// for the next streamed frame. This is the core fix for the black screen
	// on screen return: any path that left isPaused == true (changeResolution,
	// PiP, background) is self-healed here.
	func resume() {
		if let ctx = glkView?.context {
			_ = EAGLContext.setCurrent(ctx)
		}
		glkViewController.isPaused = false
		glkView?.setNeedsDisplay()
	}

	func updateSize(width: CGFloat, height: CGFloat) {
		glkView.frame.size.width = width
		glkView.frame.size.height = height
	}

	
}
