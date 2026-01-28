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

class ParsecGLKViewController : ParsecPlayground{

	var glkView: GLKView!
	let glkViewController = GLKViewController()
	var glkRenderer: ParsecGLKRenderer!
	let updateImage:() -> Void
	
	let viewController: UIViewController
	
	required init(viewController: UIViewController, updateImage: @escaping () -> Void) {
		self.viewController = viewController
		self.updateImage = updateImage
	}

	public func loadViewIfNeeded() {
		guard glkView == nil else { return }


		glkView = GLKView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height))


		glkRenderer = ParsecGLKRenderer(glkView, glkViewController, updateImage)

		setupGLKViewController()
		

	}
	
	var renderView: UIView {
		glkView
	}



	private func setupGLKViewController() {
		glkView.context = EAGLContext(api: .openGLES3)!
		EAGLContext.setCurrent(glkView.context)


		glkViewController.view = glkView


		// Use configured FPS or device max (for ProMotion displays)
		let fps = SettingsHandler.preferredFramesPerSecond

		
		if fps == 0 {
			// Use device's maximum refresh rate (120Hz on ProMotion iPads)
			glkViewController.preferredFramesPerSecond = Int(UIScreen.main.maximumFramesPerSecond)
		} else {
			glkViewController.preferredFramesPerSecond = fps
		}

		// ✅ 開始渲染
		glkViewController.isPaused = false





		glkViewController.view.frame = viewController.view.bounds
		glkViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

		self.viewController.addChild(glkViewController)
		self.viewController.view.addSubview(glkViewController.view)


		self.glkViewController.didMove(toParent: self.viewController)



		print("GLK VC view window:", glkViewController.view.window as Any)

	}

	
	func cleanUp() {
		guard let glkView = glkView else { return }

		print("🧹 GLK cleanUp start")

		// 1️⃣ 停止 render loop
		glkViewController.isPaused = true
		glkViewController.preferredFramesPerSecond = 0

		// 2️⃣ 解除 delegate / renderer
		glkView.delegate = nil
		glkRenderer = nil

		// 3️⃣ 從 parent VC 移除（如果有加）
		if glkViewController.parent != nil {
			glkViewController.willMove(toParent: nil)
			glkViewController.view.removeFromSuperview()
			glkViewController.removeFromParent()
		}

		// 4️⃣ 解除 current EAGLContext（⚠️ 只能 setCurrent(nil)，不能 context = nil）
		if EAGLContext.current() === glkView.context {
			EAGLContext.setCurrent(nil)
		}

		// 5️⃣ 釋放 view
		glkView.removeFromSuperview()
		self.glkView = nil

		CParsec.clearGL()
		
		print("🧹 GLK cleanUp done")
	}


	func updateSize(width: CGFloat, height: CGFloat) {

		guard let glkView = glkView else {
			// renderer 還沒 load view，不要動
			return
		}

		let scale = glkView.contentScaleFactor

		print("w:\(width) h:\(height) scale:\(scale)")


		glkView.frame.size.width = width
		glkView.frame.size.height = height

	}

	
}
