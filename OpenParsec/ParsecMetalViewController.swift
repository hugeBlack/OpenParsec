import UIKit
import MetalKit

extension MTKView: RenderLoop {}

class ParsecMetalViewController: ParsecPlayground {

	var metalView: MTKView!
	let metalRenderer: ParsecMetalRenderer?
	let updateImage: () -> Void
	weak var viewController: UIViewController?

	var renderView: UIView { metalView }

	required init(viewController: UIViewController, updateImage: @escaping () -> Void) {
		self.viewController = viewController
		self.updateImage = updateImage
		metalRenderer = MTLCreateSystemDefaultDevice().flatMap { ParsecMetalRenderer($0, updateImage) }
	}

	public func viewDidLoad() {
		metalView = MTKView(frame: DuoSupport.isDuo ? (viewController?.view.bounds ?? .zero) : UIScreen.main.bounds, device: metalRenderer?.device)
		metalView.colorPixelFormat = .bgra8Unorm
		metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
		metalView.autoResizeDrawable = false
		let fps = SettingsHandler.preferredFramesPerSecond
		metalView.preferredFramesPerSecond = fps == 0 ? (DuoSupport.isDuo ? (viewController?.view.window?.windowScene?.screen.maximumFramesPerSecond ?? 60) : UIScreen.main.maximumFramesPerSecond) : fps
		metalView.delegate = metalRenderer
		ParsecBackgroundManager.shared.glkViewController = metalView
	}

	func cleanUp() {
		metalView?.isPaused = true
		metalRenderer?.reset()
	}

	func updateSize(width: CGFloat, height: CGFloat) {
		metalView.frame.size.width = width
		metalView.frame.size.height = height
	}
}
