import MetalKit
import ParsecSDK
import os

private let nv12Source = """
#include <metal_stdlib>
using namespace metal;
struct VOut { float4 pos [[position]]; float2 uv; };
vertex VOut vs(uint vid [[vertex_id]]) {
	float2 p = float2(float(vid & 1), float(vid >> 1));
	VOut o;
	o.pos = float4(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0.0, 1.0);
	o.uv = p;
	return o;
}
fragment float4 fs(VOut in [[stage_in]], texture2d<float> yt [[texture(0)]], texture2d<float> ct [[texture(1)]], sampler s [[sampler(0)]]) {
	float y = (yt.sample(s, in.uv).r - 0.0625) * 1.164;
	float2 c = ct.sample(s, in.uv).rg - 0.5;
	return float4(y + 1.793 * c.y, y - 0.213 * c.x - 0.533 * c.y, y + 2.112 * c.x, 1.0);
}
"""

private let frameCallback: ParsecFrameCallback = { frame, image, opaque in
	guard let frame = frame, let image = image, let opaque = opaque else { return }
	Unmanaged<ParsecMetalRenderer>.fromOpaque(opaque).takeUnretainedValue().upload(frame.pointee, image)
}

extension ParsecFrame {
	var isWholeNV12: Bool {
		let w = Int(width), h = Int(height), stride = Int(fullWidth), rows = Int(fullHeight)
		return format == FORMAT_NV12 && w > 0 && h > 0 && stride >= 2 * ((w + 1) / 2) && rows >= h && Int(size) >= stride * rows + stride * ((h + 1) / 2)
	}
}

class ParsecMetalRenderer: NSObject, MTKViewDelegate {
	private let queue: MTLCommandQueue
	private let pipeline: MTLRenderPipelineState
	private let sampler: MTLSamplerState
	private let inFlight = DispatchSemaphore(value: 3)
	private var planes: [(y: MTLTexture, c: MTLTexture)?] = [nil, nil, nil]
	private var current = -1
	private var frameSize = CGSize.zero
	let updateImage: () -> Void

	var device: MTLDevice { queue.device }

	private var lastWidth: CGFloat = 1.0
	private var lastScale: CGFloat = 0
	private var drawnFrames = 0
	private var lastRateSample = CACurrentMediaTime()
	private var lastDrawAt: CFTimeInterval = 0
	private var drawIntervals: [CFTimeInterval] = []

	init?(_ device: MTLDevice, _ updateImage: @escaping () -> Void) {
		guard let queue = device.makeCommandQueue() else { return nil }
		let pipeline: MTLRenderPipelineState
		do {
			let library = try device.makeLibrary(source: nv12Source, options: nil)
			let desc = MTLRenderPipelineDescriptor()
			desc.vertexFunction = library.makeFunction(name: "vs")
			desc.fragmentFunction = library.makeFunction(name: "fs")
			desc.colorAttachments[0].pixelFormat = .bgra8Unorm
			pipeline = try device.makeRenderPipelineState(descriptor: desc)
		} catch {
			os_log("%{public}@", log: sdkLog, type: .error, "metal: \(error)")
			return nil
		}
		let sd = MTLSamplerDescriptor()
		sd.minFilter = .linear
		sd.magFilter = .linear
		guard let sampler = device.makeSamplerState(descriptor: sd) else { return nil }
		self.queue = queue
		self.pipeline = pipeline
		self.sampler = sampler
		self.updateImage = updateImage
		super.init()
	}

	func reset() {
		planes = [nil, nil, nil]
		current = -1
		lastDrawAt = 0
		drawIntervals.removeAll()
	}

	fileprivate func upload(_ f: ParsecFrame, _ image: UnsafeRawPointer) {
		let w = Int(f.width), h = Int(f.height), stride = Int(f.fullWidth), rows = Int(f.fullHeight)
		guard f.isWholeNV12 else { return }
		let slot = (current + 1) % planes.count
		if planes[slot]?.y.width != w || planes[slot]?.y.height != h {
			planes[slot] = makePlanes(w, h)
		}
		guard let p = planes[slot] else { return }
		p.y.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: image, bytesPerRow: stride)
		p.c.replace(region: MTLRegionMake2D(0, 0, (w + 1) / 2, (h + 1) / 2), mipmapLevel: 0, withBytes: image + stride * rows, bytesPerRow: stride)
		current = slot
		frameSize = CGSize(width: w, height: h)
		if #available(iOS 15.0, *) {
			PictureInPictureManager.shared.feedFrame(f, image)
		}
	}

	private func makePlanes(_ w: Int, _ h: Int) -> (y: MTLTexture, c: MTLTexture)? {
		let yd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: w, height: h, mipmapped: false)
		let cd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg8Unorm, width: (w + 1) / 2, height: (h + 1) / 2, mipmapped: false)
		guard let y = queue.device.makeTexture(descriptor: yd), let c = queue.device.makeTexture(descriptor: cd) else { return nil }
		return (y, c)
	}

	func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }

	func draw(in view: MTKView) {
		let deltaWidth: CGFloat = view.frame.size.width - lastWidth
		if deltaWidth > 0.1 || deltaWidth < -0.1 || abs(view.contentScaleFactor - lastScale) > 0.01 {
			CParsec.setFrame(view.frame.size.width, view.frame.size.height, view.contentScaleFactor)
			lastWidth = view.frame.size.width
			lastScale = view.contentScaleFactor
		}
		let size = CGSize(width: (view.bounds.width * view.contentScaleFactor).rounded(), height: (view.bounds.height * view.contentScaleFactor).rounded())
		if view.drawableSize != size {
			view.drawableSize = size
		}

		let tickAt = CACurrentMediaTime()
		if lastDrawAt > 0 {
			drawIntervals.append(tickAt - lastDrawAt)
			if drawIntervals.count > 32 {
				drawIntervals.removeFirst()
			}
		}
		lastDrawAt = tickAt
		var fps = view.preferredFramesPerSecond > 0 ? view.preferredFramesPerSecond : 60
		if drawIntervals.count == 32, let tick = drawIntervals.min(), tick > 0 {
			fps = max(Int((1 / tick).rounded()), 30)
		}
		let timeout = UInt32(max(1000 / fps, 8))

		inFlight.wait()
		CParsec.pollFrame(timeout: timeout, callback: frameCallback, opaque: Unmanaged.passUnretained(self).toOpaque())

		guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
			  let cb = queue.makeCommandBuffer(), let enc = cb.makeRenderCommandEncoder(descriptor: pass) else {
			inFlight.signal()
			return
		}
		if current >= 0, let p = planes[current] {
			let d = view.drawableSize
			let s = min(d.width / frameSize.width, d.height / frameSize.height)
			let w = frameSize.width * s
			let h = frameSize.height * s
			enc.setViewport(MTLViewport(originX: Double((d.width - w) / 2), originY: Double((d.height - h) / 2), width: Double(w), height: Double(h), znear: 0, zfar: 1))
			enc.setRenderPipelineState(pipeline)
			enc.setFragmentTexture(p.y, index: 0)
			enc.setFragmentTexture(p.c, index: 1)
			enc.setFragmentSamplerState(sampler, index: 0)
			enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
		}
		enc.endEncoding()
		cb.present(drawable)
		let sem = inFlight
		cb.addCompletedHandler { _ in sem.signal() }
		cb.commit()

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

		updateImage()
	}
}
