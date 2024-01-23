import SwiftUI
import GLKit

struct ParsecGLKViewController:UIViewControllerRepresentable
{
	let glkView = GLKView()
	let glkViewController = GLKViewController()
	let onBeforeRender:() -> Void

	func makeCoordinator() -> ParsecGLKRenderer
	{
		ParsecGLKRenderer(glkView, glkViewController, onBeforeRender)
	}

	func makeUIViewController(context:UIViewControllerRepresentableContext<ParsecGLKViewController>) -> GLKViewController
	{
		glkView.context = EAGLContext(api:.openGLES3)!
		glkViewController.view = glkView
		glkViewController.preferredFramesPerSecond = 60
		return glkViewController
	}

	func updateUIViewController(_ uiViewController:GLKViewController, context:UIViewControllerRepresentableContext<ParsecGLKViewController>) { }
}
