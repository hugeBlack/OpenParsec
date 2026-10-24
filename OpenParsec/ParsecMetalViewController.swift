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
		metalView = MTKView(frame: .zero, device: metalRenderer?.device)
		metalView.colorPixelFormat = .bgra8Unorm
		metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
		metalView.autoResizeDrawable = false
		let fps = SettingsHandler.preferredFramesPerSecond
		metalView.preferredFramesPerSecond = fps == 0 ? (viewController?.view.window?.screen.maximumFramesPerSecond ?? 60) : fps
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
		let maximum = viewController?.view.window?.screen.maximumFramesPerSecond ?? 60
		let requested = SettingsHandler.preferredFramesPerSecond
		metalView.preferredFramesPerSecond = requested == 0 ? maximum : min(requested, maximum)
	}
}
