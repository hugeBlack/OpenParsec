import GLKit
import ParsecSDK

class ParsecGLKRenderer:NSObject, GLKViewDelegate, GLKViewControllerDelegate
{
	var glkView:GLKView
	var glkViewController:GLKViewController
	
	var lastWidth:CGFloat = 1.0

	var lastImg: CGImage?
	let updateImage: () -> Void
	
	init(_ view:GLKView, _ viewController:GLKViewController,_ updateImage: @escaping () -> Void)
	{
		self.updateImage = updateImage
		glkView = view
		glkViewController = viewController

		super.init()

		glkView.delegate = self
		glkViewController.delegate = self

	}

	deinit
	{
		glkView.delegate = nil
		glkViewController.delegate = nil
	}

	func glkView(_ view:GLKView, drawIn rect:CGRect)
	{
		let deltaWidth: CGFloat = view.frame.size.width - lastWidth
		if deltaWidth > 0.1 || deltaWidth < -0.1
		{
		    CParsec.setFrame(view.frame.size.width, view.frame.size.height, view.contentScaleFactor)
	        lastWidth = view.frame.size.width
		}
		let startTime = CFAbsoluteTimeGetCurrent()
		CParsec.renderGLFrame(timeout:16)
		let endTime = CFAbsoluteTimeGetCurrent()
		if 1000 * (endTime - startTime) > 16 {
			print("代码执行时长：\((endTime - startTime)*1000) 毫秒")
		}
		
		updateImage()
		

//		glFinish()
		//glFlush()
	}

	func glkViewControllerUpdate(_ controller:GLKViewController) { }
}
