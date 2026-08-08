import GLKit
import ParsecSDK

class ParsecGLKRenderer: NSObject, GLKViewDelegate, GLKViewControllerDelegate {
	var glkView: GLKView
	var glkViewController: GLKViewController

	var lastWidth: CGFloat = 1.0
	var lastScale: CGFloat = 0

	var lastImg: CGImage?
	let updateImage: () -> Void

	private var drawnFrames = 0
	private var lastRateSample = CACurrentMediaTime()

	init(_ view: GLKView, _ viewController: GLKViewController, _ updateImage: @escaping () -> Void) {
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

	func glkView(_ view: GLKView, drawIn rect: CGRect) {
		if glkViewController.isPaused { return }
		let deltaWidth: CGFloat = view.frame.size.width - lastWidth
		if deltaWidth > 0.1 || deltaWidth < -0.1 || abs(view.contentScaleFactor - lastScale) > 0.01 {
			CParsec.setFrame(view.frame.size.width, view.frame.size.height, view.contentScaleFactor)
			lastWidth = view.frame.size.width
			lastScale = view.contentScaleFactor
		}

		// timeout in ms: 16ms = ~60fps, 8ms = ~120fps
		let fps = glkViewController.framesPerSecond > 0 ? glkViewController.framesPerSecond : 60
		let timeout = UInt32(max(1000 / fps, 8)) // minimum 8ms for 120Hz

		CParsec.renderGLFrame(timeout: timeout)

		drawnFrames += 1
		let now = CACurrentMediaTime()
		let elapsed = now - lastRateSample
		if elapsed >= 1 {
			if elapsed <= 2 {
				CParsec.drawRate = Double(drawnFrames) / elapsed
			}
			drawnFrames = 0
			lastRateSample = now
		}

		if #available(iOS 15.0, *) {
			PictureInPictureManager.shared.captureFrame(
				viewWidth: GLsizei(view.drawableWidth),
				viewHeight: GLsizei(view.drawableHeight),
				streamWidth: GLsizei(CParsec.hostWidth),
				streamHeight: GLsizei(CParsec.hostHeight)
			)
		}

		updateImage()

//		glFinish()
		// glFlush()
	}

	func glkViewControllerUpdate(_ controller: GLKViewController) { }
}
