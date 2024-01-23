/*import SwiftUI
import MetalKit

struct ParsecMetalViewController:UIViewRepresentable
{
	let onBeforeRender:() -> Void
	
	func makeCoordinator() -> ParsecMetalRenderer
	{
		ParsecMetalRenderer(self, onBeforeRender)
	}
	
	func makeUIView(context:UIViewRepresentableContext<ParsecMetalViewController>) -> MTKView
	{
		let metalView = MTKView()
		metalView.delegate = context.coordinator
		metalView.preferredFramesPerSecond = 60
		metalView.enableSetNeedsDisplay = true
		
		if let metalDevice = MTLCreateSystemDefaultDevice()
		{
			metalView.device = metalDevice
		}
		
		metalView.framebufferOnly = false
		metalView.drawableSize = metalView.frame.size
		return metalView
	}
	
	func updateUIView(_ uiView:MTKView, context:UIViewRepresentableContext<ParsecMetalViewController>) { }
}*/
