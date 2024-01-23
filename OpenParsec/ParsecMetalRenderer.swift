/*import MetalKit
import ParsecSDK

class ParsecMetalRenderer:NSObject, MTKViewDelegate
{
	var parent:ParsecMetalViewController
	var onBeforeRender:() -> Void
	var metalDevice:MTLDevice!
	var metalCommandQueue:MTLCommandQueue!
	var metalTexture:MTLTexture!
	var metalTexturePtr:UnsafeMutableRawPointer?
	
	var lastWidth:CGFloat = 1.0

	init(_ parent:ParsecMetalViewController, _ beforeRender:@escaping () -> Void)
	{
		self.parent = parent;
		onBeforeRender = beforeRender
		if let metalDevice = MTLCreateSystemDefaultDevice()
		{
			self.metalDevice = metalDevice
		}
		self.metalCommandQueue = metalDevice.makeCommandQueue()
		metalTexture = metalDevice.makeTexture(descriptor:MTLTextureDescriptor())
		metalTexturePtr = createTextureRef(&metalTexture)
		
		super.init()
	}
	
	func mtkView(_ view:MTKView, drawableSizeWillChange size:CGSize) { }
	
	func draw(in view:MTKView)
	{
		onBeforeRender()
		let deltaWidth: CGFloat = view.frame.size.width - lastWidth
		if deltaWidth > 0.1 || deltaWidth < -0.1
		{
			CParsec.setFrame(view.frame.size.width, view.frame.size.height, view.contentScaleFactor)
			lastWidth = view.frame.size.width
		}
		CParsec.renderMetalFrame(&metalCommandQueue, &metalTexturePtr)
	}
}*/
