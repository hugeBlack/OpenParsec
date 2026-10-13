import AVKit
import AVFoundation
import CoreVideo
import OpenGLES
import GLKit
import CoreMedia
import os
import ParsecSDK

private let kGL_BGRA: GLenum = 0x80E1

@available(iOS 15.0, *)
class PictureInPictureManager: NSObject {
	static let shared = PictureInPictureManager()

	private var pipController: AVPictureInPictureController?
	private var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer?
	private var pipSourceView: UIView?

	private var textureCache: CVOpenGLESTextureCache?
	private var pixelBuffer: CVPixelBuffer?
	private var cvTexture: CVOpenGLESTexture?
	private var captureFBO: GLuint = 0
	private var captureWidth: GLsizei = 0
	private var captureHeight: GLsizei = 0
	private var glContext: EAGLContext?

	private var nv12Pool: CVPixelBufferPool?
	private var nv12Width = 0
	private var nv12Height = 0
	private var lastFeed: CFTimeInterval = 0
	private let feedLock = NSLock()
	private var pump: DispatchSourceTimer?
	var isPumping: Bool { pump != nil }
	private let pumpQueue = DispatchQueue(label: "pip.pump")

	private static let frameCallback: ParsecFrameCallback = { frame, image, _ in
		guard let frame = frame, let image = image else { return }
		PictureInPictureManager.shared.feedFrame(frame.pointee, image)
	}

	private var cachedFormatDescription: CMVideoFormatDescription?
	private var displayLayerFlushes = 0
	private var displayLayerGaveUp = false

	private(set) var isPiPActive = false
	private var isSetup = false
	private(set) var isStarting = false
	private var frameCount: Int = 0
	private let captureEveryNthFrame: Int = 2

	private var lastValidStreamWidth: GLsizei = 0
	private var lastValidStreamHeight: GLsizei = 0

	var onPiPStopped: (() -> Void)?
	var onPiPStartFailed: (() -> Void)?
	var onRestoreUserInterface: (() -> Void)?

	private override init() {
		super.init()
	}

	// MARK: - Setup

	func setup(sourceView: UIView, glContext: EAGLContext?) {
		guard !isSetup else { return }
		guard AVPictureInPictureController.isPictureInPictureSupported() else { return }

		self.glContext = glContext

		try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
		try? AVAudioSession.sharedInstance().setActive(true)

		let layer = AVSampleBufferDisplayLayer()
		layer.videoGravity = .resizeAspect

		let containerView = UIView(frame: sourceView.bounds)
		containerView.isUserInteractionEnabled = false
		containerView.alpha = 0
		containerView.layer.addSublayer(layer)
		layer.frame = containerView.bounds
		sourceView.addSubview(containerView)

		self.sampleBufferDisplayLayer = layer
		self.pipSourceView = containerView
		resetDisplayLayerFailureState()

		let contentSource = AVPictureInPictureController.ContentSource(
			sampleBufferDisplayLayer: layer,
			playbackDelegate: self
		)
		let controller = AVPictureInPictureController(contentSource: contentSource)
		controller.setValue(1, forKey: "controlsStyle")
		controller.delegate = self
		controller.canStartPictureInPictureAutomaticallyFromInline = false
		self.pipController = controller

		if let glContext = glContext {
			setupTextureCache(glContext: glContext)
		}

		isSetup = true
	}

	private func setupTextureCache(glContext: EAGLContext) {
		var cache: CVOpenGLESTextureCache?
		let status = CVOpenGLESTextureCacheCreate(
			kCFAllocatorDefault,
			nil,
			glContext,
			nil,
			&cache
		)
		if status == kCVReturnSuccess {
			textureCache = cache
		}
	}

	// MARK: - Capture Surface

	private func createCaptureSurface(width: GLsizei, height: GLsizei) {
		destroyCaptureSurface()

		guard let textureCache = textureCache else { return }

		captureWidth = width
		captureHeight = height

		let attrs: [String: Any] = [
			kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
			kCVPixelBufferWidthKey as String: Int(width),
			kCVPixelBufferHeightKey as String: Int(height),
			kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
			kCVPixelBufferOpenGLESCompatibilityKey as String: true
		]

		var pb: CVPixelBuffer?
		let pbStatus = CVPixelBufferCreate(
			kCFAllocatorDefault,
			Int(width), Int(height),
			kCVPixelFormatType_32BGRA,
			attrs as CFDictionary,
			&pb
		)
		guard pbStatus == kCVReturnSuccess, let pixelBuffer = pb else {
			return
		}
		self.pixelBuffer = pixelBuffer

		var texture: CVOpenGLESTexture?
		let texStatus = CVOpenGLESTextureCacheCreateTextureFromImage(
			kCFAllocatorDefault,
			textureCache,
			pixelBuffer,
			nil,
			GLenum(GL_TEXTURE_2D),
			GL_RGBA,
			width, height,
			kGL_BGRA,
			GLenum(GL_UNSIGNED_BYTE),
			0,
			&texture
		)
		guard texStatus == kCVReturnSuccess, let cvTex = texture else {
			self.pixelBuffer = nil
			return
		}
		self.cvTexture = cvTex

		let textureName = CVOpenGLESTextureGetName(cvTex)
		glGenFramebuffers(1, &captureFBO)
		glBindFramebuffer(GLenum(GL_FRAMEBUFFER), GLenum(captureFBO))
		glFramebufferTexture2D(
			GLenum(GL_FRAMEBUFFER),
			GLenum(GL_COLOR_ATTACHMENT0),
			GLenum(GL_TEXTURE_2D),
			textureName,
			0
		)

		let fbStatus = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
		if fbStatus != GLenum(GL_FRAMEBUFFER_COMPLETE) {
			destroyCaptureSurface()
			return
		}

		cachedFormatDescription = nil
	}

	private func destroyCaptureSurface() {
		if captureFBO != 0 {
			glDeleteFramebuffers(1, &captureFBO)
			captureFBO = 0
		}
		cvTexture = nil
		pixelBuffer = nil
		captureWidth = 0
		captureHeight = 0
		cachedFormatDescription = nil
	}

	// MARK: - Frame Capture (GL thread)

	func captureFrame(viewWidth: GLsizei, viewHeight: GLsizei, streamWidth: GLsizei, streamHeight: GLsizei) {
		guard isSetup else { return }

		frameCount += 1
		guard frameCount % captureEveryNthFrame == 0 else { return }

		if streamWidth >= 640 && streamHeight >= 480 && streamWidth <= 7680 && streamHeight <= 4320 {
			if streamWidth != lastValidStreamWidth || streamHeight != lastValidStreamHeight {
				lastValidStreamWidth = streamWidth
				lastValidStreamHeight = streamHeight
			}
		}

		let targetWidth = lastValidStreamWidth > 0 ? lastValidStreamWidth : viewWidth
		let targetHeight = lastValidStreamHeight > 0 ? lastValidStreamHeight : viewHeight

		if targetWidth != captureWidth || targetHeight != captureHeight {
			createCaptureSurface(width: targetWidth, height: targetHeight)
		}

		guard pixelBuffer != nil, captureFBO != 0 else { return }

		var currentFBO: GLint = 0
		glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &currentFBO)
		if currentFBO == 0 { return }

		// Calculate the letterboxed stream region within the view
		let sW = Float(lastValidStreamWidth > 0 ? lastValidStreamWidth : viewWidth)
		let sH = Float(lastValidStreamHeight > 0 ? lastValidStreamHeight : viewHeight)
		let vW = Float(viewWidth)
		let vH = Float(viewHeight)
		let streamAspect = sW / max(sH, 1)
		let viewAspect = vW / max(vH, 1)

		var srcX: GLint = 0
		var srcY: GLint = 0
		var srcW: GLint = GLint(viewWidth)
		var srcH: GLint = GLint(viewHeight)

		if lastValidStreamWidth > 0 && lastValidStreamHeight > 0 {
			if streamAspect > viewAspect {
				let renderH = vW / streamAspect
				srcX = 0
				srcY = GLint((vH - renderH) / 2)
				srcW = GLint(vW)
				srcH = GLint(renderH)
			} else if streamAspect < viewAspect {
				let renderW = vH * streamAspect
				srcX = GLint((vW - renderW) / 2)
				srcY = 0
				srcW = GLint(renderW)
				srcH = GLint(vH)
			}
		}

		// Blit view FBO → capture FBO with Y-flip
		glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), GLenum(currentFBO))
		glBindFramebuffer(GLenum(GL_DRAW_FRAMEBUFFER), GLenum(captureFBO))
		glBlitFramebuffer(
			srcX, srcY + srcH,
			srcX + srcW, srcY,
			0, 0,
			GLint(captureWidth), GLint(captureHeight),
			GLbitfield(GL_COLOR_BUFFER_BIT),
			GLenum(GL_LINEAR)
		)

		glBindFramebuffer(GLenum(GL_FRAMEBUFFER), GLenum(currentFBO))

		feedSampleBuffer()
	}

	// MARK: - Sample Buffer

	private func feedSampleBuffer() {
		guard let pixelBuffer = pixelBuffer,
			  let displayLayer = sampleBufferDisplayLayer,
			  displayLayerTakesFrames(displayLayer) else { return }
		enqueue(pixelBuffer, on: displayLayer)
	}

	private func displayLayerTakesFrames(_ displayLayer: AVSampleBufferDisplayLayer) -> Bool {
		if displayLayer.status == .failed {
			guard !displayLayerGaveUp else { return false }
			guard displayLayerFlushes < 3 else {
				displayLayerGaveUp = true
				handleTerminalDisplayLayerFailure(displayLayer)
				return false
			}
			displayLayerFlushes += 1
			displayLayer.flush()
			cachedFormatDescription = nil
		} else if displayLayer.status == .rendering {
			displayLayerFlushes = 0
		}
		return displayLayer.isReadyForMoreMediaData
	}

	func feedFrame(_ f: ParsecFrame, _ image: UnsafeRawPointer) {
		guard isSetup else { return }
		feedLock.lock()
		defer { feedLock.unlock() }
		let now = CACurrentMediaTime()
		guard now - lastFeed >= (isPiPActive || isStarting ? 0.03 : 0.5) else { return }
		let w = Int(f.width), h = Int(f.height), stride = Int(f.fullWidth), rows = Int(f.fullHeight)
		guard f.isWholeNV12, let displayLayer = sampleBufferDisplayLayer, displayLayerTakesFrames(displayLayer) else { return }
		if nv12Pool == nil || nv12Width != w || nv12Height != h {
			let attrs: [String: Any] = [
				kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
				kCVPixelBufferWidthKey as String: w,
				kCVPixelBufferHeightKey as String: h,
				kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
			]
			var pool: CVPixelBufferPool?
			CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
			nv12Pool = pool
			nv12Width = w
			nv12Height = h
		}
		guard let pool = nv12Pool else { return }
		var out: CVPixelBuffer?
		guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &out) == kCVReturnSuccess, let pb = out else { return }
		CVPixelBufferLockBaseAddress(pb, [])
		if let y = CVPixelBufferGetBaseAddressOfPlane(pb, 0), let c = CVPixelBufferGetBaseAddressOfPlane(pb, 1) {
			let yRow = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
			let cRow = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
			let cBytes = min(((w + 1) / 2) * 2, stride, cRow)
			for r in 0..<h {
				memcpy(y + r * yRow, image + r * stride, min(w, yRow))
			}
			let uv = image + stride * rows
			for r in 0..<((h + 1) / 2) {
				memcpy(c + r * cRow, uv + r * stride, cBytes)
			}
		}
		CVPixelBufferUnlockBaseAddress(pb, [])
		lastFeed = now
		enqueue(pb, on: displayLayer)
	}

	func startFramePump() {
		guard isSetup, pump == nil else { return }
		let t = DispatchSource.makeTimerSource(queue: pumpQueue)
		t.schedule(deadline: .now(), repeating: .milliseconds(16))
		let opaque = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
		t.setEventHandler {
			_ = CParsec.pollFrame(timeout: 8, callback: PictureInPictureManager.frameCallback, opaque: opaque)
		}
		t.resume()
		pump = t
	}

	@discardableResult
	func stopFramePump() -> Bool {
		guard let t = pump else { return false }
		t.cancel()
		pump = nil
		pumpQueue.sync {}
		return true
	}

	private func enqueue(_ pixelBuffer: CVPixelBuffer, on displayLayer: AVSampleBufferDisplayLayer) {
		if let format = cachedFormatDescription, !CMVideoFormatDescriptionMatchesImageBuffer(format, imageBuffer: pixelBuffer) {
			cachedFormatDescription = nil
		}
		if cachedFormatDescription == nil {
			CMVideoFormatDescriptionCreateForImageBuffer(
				allocator: kCFAllocatorDefault,
				imageBuffer: pixelBuffer,
				formatDescriptionOut: &cachedFormatDescription
			)
		}
		guard let format = cachedFormatDescription else { return }

		let now = CMClockGetTime(CMClockGetHostTimeClock())
		var timingInfo = CMSampleTimingInfo(
			duration: CMTime(value: 1, timescale: 30),
			presentationTimeStamp: now,
			decodeTimeStamp: .invalid
		)

		var sampleBuffer: CMSampleBuffer?
		CMSampleBufferCreateForImageBuffer(
			allocator: kCFAllocatorDefault,
			imageBuffer: pixelBuffer,
			dataReady: true,
			makeDataReadyCallback: nil,
			refcon: nil,
			formatDescription: format,
			sampleTiming: &timingInfo,
			sampleBufferOut: &sampleBuffer
		)

		guard let buffer = sampleBuffer else { return }
		displayLayer.enqueue(buffer)
	}

	private func handleTerminalDisplayLayerFailure(_ displayLayer: AVSampleBufferDisplayLayer) {
		os_log("%{public}@", log: sdkLog, "[pip] display layer failed, status \(displayLayer.status.rawValue), error \(displayLayer.error.map { String(describing: $0) } ?? "none")")
		DispatchQueue.main.async { [weak self, weak displayLayer] in
			guard let self, let displayLayer,
				  self.sampleBufferDisplayLayer === displayLayer else { return }
			self.isStarting = false
			if self.isPiPActive {
				self.pipController?.stopPictureInPicture()
			} else {
				self.onPiPStartFailed?()
			}
		}
	}

	private func resetDisplayLayerFailureState() {
		displayLayerFlushes = 0
		displayLayerGaveUp = false
	}

	// MARK: - PiP Control

	func startPiP() {
		guard isSetup, let controller = pipController, !isPiPActive, !isStarting else { return }
		resetDisplayLayerFailureState()

		isStarting = true
		attemptStartPiP(controller: controller, retryCount: 0)
	}

	private func attemptStartPiP(controller: AVPictureInPictureController, retryCount: Int) {
		if controller.isPictureInPicturePossible {
			sampleBufferDisplayLayer?.flush()
			controller.startPictureInPicture()
		} else if retryCount < 5 {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
				guard let self = self, !self.isPiPActive, self.isStarting else {
					self?.isStarting = false
					return
				}
				self.attemptStartPiP(controller: controller, retryCount: retryCount + 1)
			}
		} else {
			isStarting = false
			stopFramePump()
			appNote("[pip] gave up starting after \(retryCount) retries")
			onPiPStartFailed?()
		}
	}

	func stopPiP() {
		isStarting = false
		guard isPiPActive else { return }
		pipController?.stopPictureInPicture()
	}

	// MARK: - Cleanup

	func teardown() {
		stopFramePump()
		nv12Pool = nil
		stopPiP()
		destroyCaptureSurface()

		if let cache = textureCache {
			CVOpenGLESTextureCacheFlush(cache, 0)
		}
		textureCache = nil
		pipController = nil
		sampleBufferDisplayLayer?.removeFromSuperlayer()
		sampleBufferDisplayLayer = nil
		pipSourceView?.removeFromSuperview()
		pipSourceView = nil
		glContext = nil
		isSetup = false
		isPiPActive = false
		isStarting = false
		lastValidStreamWidth = 0
		lastValidStreamHeight = 0
		cachedFormatDescription = nil
		resetDisplayLayerFailureState()
		onPiPStopped = nil
		onPiPStartFailed = nil
		onRestoreUserInterface = nil

		// Deactivate the audio session so iOS stops keeping the app alive
		// for audio playback in the background
		try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
	}
}

// MARK: - AVPictureInPictureControllerDelegate
@available(iOS 15.0, *)
extension PictureInPictureManager: AVPictureInPictureControllerDelegate {

	func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
		isPiPActive = true
		isStarting = false
	}

	func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
	}

	func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
	}

	func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
		isPiPActive = false
		stopFramePump()
		onPiPStopped?()
	}

	func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
									restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
		onRestoreUserInterface?()
		completionHandler(true)
	}

	func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
									failedToStartPictureInPictureWithError error: Error) {
		let nsError = error as NSError
		appNote("[pip] could not start, \(nsError.domain) \(nsError.code)")
		isPiPActive = false
		isStarting = false
		stopFramePump()
		onPiPStartFailed?()
	}
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate
@available(iOS 15.0, *)
extension PictureInPictureManager: AVPictureInPictureSampleBufferPlaybackDelegate {

	func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
		// Live content — nothing to do
	}

	func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
		return CMTimeRange(start: .zero, duration: .positiveInfinity)
	}

	func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
		return false
	}

	func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
									didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
	}

	func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
									skipByInterval skipInterval: CMTime,
									completion completionHandler: @escaping () -> Void) {
		// Live content — no seeking
		completionHandler()
	}
}
