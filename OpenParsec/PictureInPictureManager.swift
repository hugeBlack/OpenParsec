import AVKit
import AVFoundation
import CoreVideo
import OpenGLES
import GLKit
import CoreMedia

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

	private var cachedFormatDescription: CMVideoFormatDescription?

	private(set) var isPiPActive = false
	private var isSetup = false
	private(set) var isStarting = false
	private var frameCount: Int = 0
	private let captureEveryNthFrame: Int = 2

	private var lastValidStreamWidth: GLsizei = 0
	private var lastValidStreamHeight: GLsizei = 0

	private weak var glkViewController: GLKViewController?

	var onPiPStopped: (() -> Void)?
	var onPiPStartFailed: (() -> Void)?
	var onRestoreUserInterface: (() -> Void)?

	private override init() {
		super.init()
	}

	// MARK: - Setup

	func setup(sourceView: UIView, glContext: EAGLContext, glkViewController: GLKViewController? = nil) {
		guard !isSetup else { return }
		guard AVPictureInPictureController.isPictureInPictureSupported() else { return }

		self.glContext = glContext
		self.glkViewController = glkViewController

		try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
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

		let contentSource = AVPictureInPictureController.ContentSource(
			sampleBufferDisplayLayer: layer,
			playbackDelegate: self
		)
		let controller = AVPictureInPictureController(contentSource: contentSource)
		controller.delegate = self
		controller.canStartPictureInPictureAutomaticallyFromInline = false
		self.pipController = controller

		setupTextureCache(glContext: glContext)

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
			  displayLayer.isReadyForMoreMediaData else { return }

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

	// MARK: - PiP Control

	func startPiP() {
		guard isSetup, let controller = pipController, !isPiPActive, !isStarting else { return }

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
		// Keep GL render loop alive during PiP so frames keep updating
		glkViewController?.isPaused = false
	}

	func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
	}

	func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
	}

	func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
		isPiPActive = false
		onPiPStopped?()
	}

	func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
									restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
		onRestoreUserInterface?()
		completionHandler(true)
	}

	func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
									failedToStartPictureInPictureWithError error: Error) {
		isPiPActive = false
		isStarting = false
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
