import Foundation
import UIKit
import ParsecSDK
import QuartzCore

protocol ParsecPlayground {
	init(viewController: UIViewController, updateImage: @escaping () -> Void)
	func viewDidLoad()
	func cleanUp()
	func updateSize(width: CGFloat, height: CGFloat)
}

class ParsecViewController: UIViewController, UIScrollViewDelegate, ParsecTouchInputDelegate {
	var glkView: ParsecPlayground!
	var gamePadController: GamepadController!
	var touchController: TouchController!
	var u: UIImageView?
	var lastImg: CGImage?
    var lastMouseX: Int32 = -1
    var lastMouseY: Int32 = -1
    var lastCursorHidden: Bool = false
	var zoomEnabled = false
	var appliedRenderScale: CGFloat = 0       // last contentScaleFactor applied (avoids redundant reallocations)
	let maxRenderScale: CGFloat = 6.0         // cap on drawable density
	var clickHoldActive = false        // left button held via long-press (file drag)
	// Flick-to-glide momentum (tuned constants, not user settings).
	var momentumLink: CADisplayLink?
	var cursorMomentumActive = false
	var scrollMomentumActive = false
	var cursorVelocity: CGPoint = .zero     // content points / sec
	var scrollVelocity: Float = 0.0         // wheel units / sec
	var lastCursorMoveTime: CFTimeInterval = 0
	var lastScrollMoveTime: CFTimeInterval = 0
	let flingMinSpeed: CGFloat = 80.0       // min release speed (content pts/sec) to start a cursor glide
	let cursorStopSpeed: CGFloat = 40.0     // end the glide below this speed (lower = gentler, less abrupt)
	let cursorDecayPerSec: Double = 0.08    // fraction of speed left after 1s (bigger = longer glide)
	let scrollStartSpeed: Float = 800.0     // min release speed (wheel units/sec) to start a scroll glide
	let scrollStopSpeed: Float = 200.0
	let scrollDecayPerSec: Double = 0.004
	// A left click fires only if the finger barely moved (else it's a cursor nudge).
	var cursorDidMoveThisTouch = false
	var singleTouchStartScreen: CGPoint = .zero
	let tapMoveSlop: CGFloat = 4.0          // finger movement (pts) above which a touch is a drag, not a tap
	let staleTouchThreshold: TimeInterval = 1.5   // a touch idle this long vs an actively-moving one is a ghost
	let staleMoveSlop: CGFloat = 24.0        // the moving finger must travel this far before a ghost is swept
	var twoFingerDidMove = false            // true once a 2-finger gesture became a pinch/scroll (suppresses right-click)

	var mouseSensitivity: Float = Float(SettingsHandler.mouseSensitivity)
	// Two-finger scroll-wheel accumulation, kept separate from cursor movement.
	var lastScrollTranslation: CGPoint = .zero
	var accumulatedScrollY: Float = 0.0
	var scrollWheelSpeed: Float { Float(SettingsHandler.scrollSensitivity) * 2.3 }

	// Input-driven cursor + viewport state (manual touch handling via TouchOverlayView).
	var touchOverlay: TouchOverlayView!
	var cursorContentPos: CGPoint = .zero
	var isDragging = false
	var twoFingerResidual = false       // leftover finger after a 2-finger gesture; inert until full lift
	var activeTouches: [UITouch] = []   // ordered; first two drive pinch / scroll
	var touchOrigins: [UITouch: CGPoint] = [:]   // begin location per touch, for ghost-sweep movement test

	enum TwoFingerMode { case undecided, zoom, scroll }
	var twoFingerMode: TwoFingerMode = .undecided
	var startPinchDistance: CGFloat = 0
	var lastPinchDistance: CGFloat = 0
	var startTwoFingerMidpoint: CGPoint = .zero
	var lastTwoFingerMidpoint: CGPoint = .zero

	var keyboardAccessoriesView: UIView?
	var keyboardHeight: CGFloat = 0.0
	var keyboardVisible: Bool = false
	var onKeyboardVisibilityChanged: ((Bool) -> Void)?
	var scrollView: UIScrollView!
	var contentView: UIView!
	var lastLaidOutWidth: CGFloat = 0
	var lastLaidOutHeight: CGFloat = 0

	override var prefersPointerLocked: Bool {
		return true
	}

	override var prefersHomeIndicatorAutoHidden: Bool {
		return true
	}

	init() {
		super.init(nibName: nil, bundle: nil)

		self.glkView = ParsecGLKViewController(viewController: self, updateImage: updateImage)

		self.gamePadController = GamepadController(viewController: self)
		self.touchController = TouchController(viewController: self)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func computeRenderScale() -> CGFloat {
		let nativeScale = UIScreen.main.nativeScale
		guard scrollView.zoomScale > 1.01, let glk = glkView as? ParsecGLKViewController else { return nativeScale }
		let vw = glk.glkView.frame.size.width
		let vh = glk.glkView.frame.size.height
		let sw = CGFloat(CParsec.hostWidth)
		let sh = CGFloat(CParsec.hostHeight)
		guard vw > 0, vh > 0, sw > 0, sh > 0 else { return nativeScale }
		// Match the drawable to the source so zoom stays crisp without rendering wasted pixels.
		let needed = max(sw / vw, sh / vh)
		return min(maxRenderScale, max(nativeScale, needed))
	}

	func updateRenderScale() {
		let target = computeRenderScale()
		if abs(target - appliedRenderScale) > 0.01 {
			appliedRenderScale = target
			DispatchQueue.main.async { [weak self] in
				(self?.glkView as? ParsecGLKViewController)?.glkView.contentScaleFactor = target
			}
		}
	}

	func updateImage() {
		updateRenderScale()
        // Optimization: Snap current valus
        let currentMouseX = CParsec.mouseInfo.mouseX
        let currentMouseY = CParsec.mouseInfo.mouseY
        let currentHidden = CParsec.mouseInfo.cursorHidden
        let currentImg = CParsec.mouseInfo.cursorImg

        // Skip if nothing changed
        if currentMouseX == lastMouseX &&
           currentMouseY == lastMouseY &&
           currentHidden == lastCursorHidden &&
           currentImg == lastImg {
            return
        }

        lastMouseX = currentMouseX
        lastMouseY = currentMouseY
        lastCursorHidden = currentHidden

		if currentImg != nil && !currentHidden {
			if lastImg != currentImg {
				u!.image = UIImage(cgImage: currentImg!)
				lastImg = currentImg!
			}

			// While dragging, the touch handler owns the cursor position and viewport (smooth,
			// input-driven). When idle, follow the host's reported cursor so host- or keyboard-
			// driven moves are reflected and any prediction drift is corrected.
			if !isDragging && !clickHoldActive && !cursorMomentumActive {
				cursorContentPos = CGPoint(x: CGFloat(currentMouseX), y: CGFloat(currentMouseY))
				positionCursorOverlay()
				if scrollView.zoomScale > 1.0 {
					centerViewportOnCursorPos()
				} else if keyboardVisible && scrollView.contentInset.bottom > 0 {
					// Not zoomed: keep the cursor above the on-screen keyboard.
					let margin: CGFloat = 50.0
					let effectiveViewHeight = view.bounds.height - keyboardHeight
					if u!.frame.maxY > effectiveViewHeight - margin {
						let diff = u!.frame.maxY - (effectiveViewHeight - margin)
						let maxOffsetY = max(0, scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom)
						let targetOffsetY = min(scrollView.contentOffset.y + diff, maxOffsetY)
						scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: targetOffsetY), animated: false)
					}
				}
			}
		} else {
			u?.image = nil
		}
	}

	override func viewDidLoad() {
		// ScrollView Setup
		scrollView = UIScrollView(frame: view.bounds)
		scrollView.delegate = self
		scrollView.minimumZoomScale = 1.0
		scrollView.maximumZoomScale = 5.0
		scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		// The scroll view is a programmatically-driven zoom/pan container only. Every touch is
		// owned by touchOverlay (created below); the scroll view's own gestures are disabled so
		// they can never race with or swallow our cursor / pinch / scroll handling.
		scrollView.panGestureRecognizer.isEnabled = false
		scrollView.pinchGestureRecognizer?.isEnabled = false
		scrollView.isScrollEnabled = false
		scrollView.bouncesZoom = false
		view.addSubview(scrollView)

        // ContentView
		contentView = UIView(frame: view.bounds)
		scrollView.addSubview(contentView)
		scrollView.contentSize = view.bounds.size

        // Initialize GLKView
		glkView.viewDidLoad()

		// Move GLKView to ContentView
		// glkView.viewDidLoad() adds the view to 'view', we need to move it.
		if let parsecGLK = glkView as? ParsecGLKViewController {
			parsecGLK.glkView.removeFromSuperview()
			contentView.addSubview(parsecGLK.glkView)
		} else {
			// Fallback if type check fails, try to find the last subview added?
			// Assumption: glkView.viewDidLoad() adds a subview.
		}

		if #available(iOS 15.0, *) {
			if SettingsHandler.enablePiP,
			   let parsecGLK = glkView as? ParsecGLKViewController,
			   let eaglContext = parsecGLK.eaglContext {
				PictureInPictureManager.shared.setup(sourceView: view, glContext: eaglContext, glkViewController: parsecGLK.glkViewController)
			}
		}

		touchController.viewDidLoad()
		gamePadController.viewDidLoad()

		// Touch overlay: a transparent sibling ON TOP of the scroll view (and above the gamepad /
		// touch controllers) that captures every raw touch and routes it deterministically
		// (1 finger = cursor, 2 fingers = pinch / scroll). Added before the cursor image and the
		// keyboard toolbar so those stay on top of it.
		touchOverlay = TouchOverlayView(frame: view.bounds)
		touchOverlay.backgroundColor = .clear
		touchOverlay.isMultipleTouchEnabled = true
		touchOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		touchOverlay.inputDelegate = self
		view.addSubview(touchOverlay)

		// Cursor is a screen-space overlay ON TOP of everything (not inside the scroll view), so the
		// zoom transform never scales it - keeping it crisp and a constant on-screen size.
		u = UIImageView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
		u!.isUserInteractionEnabled = false
		view.addSubview(u!)

		setNeedsUpdateOfPrefersPointerLocked()

		let pointerInteraction = UIPointerInteraction(delegate: self)
		view.addInteraction(pointerInteraction)

		view.isMultipleTouchEnabled = true
		view.isUserInteractionEnabled = true

		// All gestures (cursor, pinch-zoom, two-finger scroll) are handled in the
		// ParsecTouchInputDelegate methods below, driven by touchOverlay's raw touches.

		// Add tap gesture recognizer for single-finger touch
		let singleFingerTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleSingleFingerTap(_:)))
		singleFingerTapGestureRecognizer.numberOfTouchesRequired = 1
		singleFingerTapGestureRecognizer.allowedTouchTypes = [0, 2]
		// Let the overlay see the real touch end so no phantom finger lingers.
		singleFingerTapGestureRecognizer.cancelsTouchesInView = false
		singleFingerTapGestureRecognizer.delaysTouchesEnded = false
		view.addGestureRecognizer(singleFingerTapGestureRecognizer)

		// Add tap gesture recognizer for two-finger touch
		let twoFingerTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
		twoFingerTapGestureRecognizer.numberOfTouchesRequired = 2
		twoFingerTapGestureRecognizer.allowedTouchTypes = [0]
		twoFingerTapGestureRecognizer.cancelsTouchesInView = false
		twoFingerTapGestureRecognizer.delaysTouchesEnded = false
		view.addGestureRecognizer(twoFingerTapGestureRecognizer)
		//		view.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
		//		view.backgroundColor = UIColor(red: 0x66, green: 0xcc, blue: 0xff, alpha: 1.0)

		let threeFingerTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleThreeFinderTap(_:)))
		threeFingerTapGestureRecognizer.numberOfTouchesRequired = 3
		threeFingerTapGestureRecognizer.allowedTouchTypes = [0]
		threeFingerTapGestureRecognizer.cancelsTouchesInView = false
		threeFingerTapGestureRecognizer.delaysTouchesEnded = false
		view.addGestureRecognizer(threeFingerTapGestureRecognizer)

		let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
		longPressGestureRecognizer.numberOfTouchesRequired = 1
		longPressGestureRecognizer.allowedTouchTypes = [0, 2]
		// Don't cancel the overlay's touch, so the click-hold button can be released on lift.
		longPressGestureRecognizer.cancelsTouchesInView = false
		view.addGestureRecognizer(longPressGestureRecognizer)

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(keyboardWillShow),
			name: UIResponder.keyboardWillShowNotification,
			object: nil
		)

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(keyboardWillHide),
			name: UIResponder.keyboardWillHideNotification,
			object: nil
		)

		// Backgrounding / Control Center / system alerts can orphan touches; flush on resign.
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(appWillResignActive),
			name: UIApplication.willResignActiveNotification,
			object: nil
		)

	}

	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)

		let h = size.height
		let w = size.width

		// Reset zoom on rotation
		scrollView.zoomScale = 1.0

		self.glkView.updateSize(width: w, height: h)
		contentView.frame.size = CGSize(width: w, height: h)
		scrollView.contentSize = CGSize(width: w, height: h)
		CParsec.setFrame(w, h, UIScreen.main.scale)

        // Reset accessory view to ensure correct width in new orientation
        keyboardAccessoriesView = nil
        if keyboardVisible {
            reloadInputViews()
        }
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		// glkView/contentView get sized from possibly-stale bounds in viewDidLoad and have no
		// autoresizing, so the stream renders in a corner until a rotation re-applies the size.
		// re-apply once layout settles; skip while zoomed so we dont stomp pan/zoom.
		guard scrollView != nil, scrollView.zoomScale == 1.0 else { return }
		let w = view.bounds.width
		let h = view.bounds.height
		guard w > 0, h > 0, w != lastLaidOutWidth || h != lastLaidOutHeight else { return }
		lastLaidOutWidth = w
		lastLaidOutHeight = h
		glkView.updateSize(width: w, height: h)
		contentView.frame.size = CGSize(width: w, height: h)
		scrollView.contentSize = CGSize(width: w, height: h)
		CParsec.setFrame(w, h, UIScreen.main.scale)
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		if let parent = parent {
			parent.setChildForHomeIndicatorAutoHidden(self)
			parent.setChildViewControllerForPointerLock(self)
		}
		if keyboardVisible {
			becomeFirstResponder()
		}
		// (Pinch-to-zoom is driven manually via touchOverlay; the scroll view's pinch stays off.)
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		stopMomentum()
		if let parent = parent {
			parent.setChildForHomeIndicatorAutoHidden(nil)
			parent.setChildViewControllerForPointerLock(nil)
		}
		NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
		NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
		NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
	}
	
	
	private var repeatTimer: Timer?
	private var repeatKeyCode: Int = -1
	private var optCmdRemapActive = false
	private var altKeyHeld = false

	override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		for press in presses {
			guard let key = press.key else { continue }

			if key.keyCode == .keyboardLeftAlt || key.keyCode == .keyboardRightAlt {
				altKeyHeld = true
			}

			if !isModifierKey(key.keyCode) && (altKeyHeld || key.modifierFlags.contains(.alternate)) {
				if !optCmdRemapActive {
					CParsec.sendKeyboardMessage(keyCode: 226, pressed: false)
					CParsec.sendKeyboardMessage(keyCode: 227, pressed: true)
					optCmdRemapActive = true
				}
				let code = KeyCodeTranslators.uiKeyCodeToInt(key: key.keyCode)
				CParsec.sendKeyboardMessage(keyCode: UInt32(code), pressed: true)
				startKeyRepeat(keyCode: code)
				continue
			}

			CParsec.sendKeyboardMessage(event:KeyBoardKeyEvent(input: press.key, isPressBegin: true))

			if !isModifierKey(key.keyCode) {
				startKeyRepeat(keyCode: KeyCodeTranslators.uiKeyCodeToInt(key: key.keyCode))
			}
		}
	}

	override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		for press in presses {
			guard let key = press.key else { continue }

			if optCmdRemapActive {
				if key.keyCode == .keyboardLeftAlt || key.keyCode == .keyboardRightAlt {
					altKeyHeld = false
					CParsec.sendKeyboardMessage(keyCode: 227, pressed: false)
					optCmdRemapActive = false
					continue
				}
				if !isModifierKey(key.keyCode) {
					let code = KeyCodeTranslators.uiKeyCodeToInt(key: key.keyCode)
					CParsec.sendKeyboardMessage(keyCode: UInt32(code), pressed: false)
					if code == repeatKeyCode { stopKeyRepeat() }
					continue
				}
			}

			if key.keyCode == .keyboardLeftAlt || key.keyCode == .keyboardRightAlt {
				altKeyHeld = false
			}

			CParsec.sendKeyboardMessage(event:KeyBoardKeyEvent(input: press.key, isPressBegin: false))

			let code = KeyCodeTranslators.uiKeyCodeToInt(key: key.keyCode)
			if code == repeatKeyCode {
				stopKeyRepeat()
			}
		}
	}

	private func startKeyRepeat(keyCode: Int) {
		stopKeyRepeat()
		repeatKeyCode = keyCode

		repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
			guard let self = self else { return }
			self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
				guard let self = self else { return }
				CParsec.sendKeyboardMessage(keyCode: UInt32(self.repeatKeyCode), pressed: false)
				CParsec.sendKeyboardMessage(keyCode: UInt32(self.repeatKeyCode), pressed: true)
			}
		}
	}

	private func stopKeyRepeat() {
		repeatTimer?.invalidate()
		repeatTimer = nil
		repeatKeyCode = -1
	}

	func resetKeyState() {
		stopKeyRepeat()
		optCmdRemapActive = false
		altKeyHeld = false
	}

	private func isModifierKey(_ keyCode: UIKeyboardHIDUsage) -> Bool {
		switch keyCode {
		case .keyboardLeftControl, .keyboardLeftShift, .keyboardLeftAlt, .keyboardLeftGUI,
			 .keyboardRightControl, .keyboardRightShift, .keyboardRightAlt, .keyboardRightGUI,
			 .keyboardCapsLock:
			return true
		default:
			return false
		}
	}

	@objc func keyboardWillShow(notification: NSNotification) {
		if let keyboardFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            let height = keyboardFrame.height
			keyboardHeight = height
            keyboardVisible = true

            // Allow scrolling past current bottom to see hidden content
            scrollView.contentInset.bottom = height

            // Automatic scroll up only if mouse is in the bottom half of the screen
            let mouseY = CGFloat(CParsec.mouseInfo.mouseY)
            let screenMidY = view.bounds.height / 2.1

            if mouseY > screenMidY {
                 let maxOffsetY = max(0, scrollView.contentSize.height - scrollView.bounds.height + height)
                 let newOffsetY = min(maxOffsetY, scrollView.contentOffset.y + height / 1.25)

                 scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: newOffsetY), animated: true)

            }
		}
		onKeyboardVisibilityChanged?(true)
	}

	@objc func keyboardWillHide(notification: NSNotification) {
		keyboardHeight = 0.0
        keyboardVisible = false

        // Restore inset
        scrollView.contentInset.bottom = 0

        // Transform cleanup (just in case)
        view.transform = .identity

        // Automatic scroll down in landscape mode (reverse of show)
        if view.bounds.width > view.bounds.height {
             // We subtract, but clamp to 0 (or valid range)
			let newOffsetY = max(0, scrollView.contentOffset.y - ((notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.height ?? 0.0))
             // Or maybe just clamp to valid range without forcing a subtract?
             // User said "bajar la altura", implying a reverse scroll.
             scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: newOffsetY), animated: true)
        }
		onKeyboardVisibilityChanged?(false)
	}

}

extension ParsecViewController: UIGestureRecognizerDelegate {

	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		return true
	}

	@objc func handlePinchGesture(_ gestureRecognizer: UIPinchGestureRecognizer) {
		// Pinch is handled by UIScrollView
	}

	// MARK: - Manual touch handling (ParsecTouchInputDelegate)
	// touchOverlay delivers raw touches here. One finger drives the mouse cursor; two fingers are
	// classified once per gesture into either pinch-zoom or host scroll-wheel (never both), so the
	// gestures never fight. No UIScrollView gesture recognizer is in the loop.

	func parsecTouchesUpdated(_ touches: Set<UITouch>, moved: Bool) {
		let oldCount = activeTouches.count
		// Rebuild from the event each time (keeping order) so a cancelled touch can't leave a stale one.
		var ordered = activeTouches.filter { touches.contains($0) }
		for t in touches where !ordered.contains(t) {
			ordered.append(t)
			touchOrigins[t] = t.location(in: view)
		}
		// Sweep a ghost (an OS-dropped lift lingering as .stationary) only while another finger actively
		// moves - a resting or just-tapped finger is never swept, so taps and held fingers stay safe.
		var sweptGhost = false
		if ordered.count >= 2 && !clickHoldActive,
		   let newest = ordered.max(by: { $0.timestamp < $1.timestamp }) {
			let origin = touchOrigins[newest] ?? newest.location(in: view)
			let here = newest.location(in: view)
			if hypot(here.x - origin.x, here.y - origin.y) > staleMoveSlop {
				let fresh = ordered.filter { newest.timestamp - $0.timestamp < staleTouchThreshold }
				if fresh.count < ordered.count { ordered = fresh; sweptGhost = true }
			}
		}
		activeTouches = ordered
		touchOrigins = touchOrigins.filter { activeTouches.contains($0.key) }
		if sweptGhost && activeTouches.count == 1 {
			// Recover the surviving finger as a live cursor instead of inert two-finger residual.
			stopMomentum()
			twoFingerResidual = false
			twoFingerMode = .undecided
			startCursor()
		} else if activeTouches.count != oldCount {
			handleTouchCountChange(old: oldCount, new: activeTouches.count)
		}
		if moved { handleActiveTouchesMoved() }
	}

	private func handleTouchCountChange(old: Int, new: Int) {
		if new > old { stopMomentum() }   // any new finger cancels an in-progress glide
		if new == 0 {
			let flingCursor = (old == 1) && isDragging && !twoFingerResidual && !clickHoldActive
			let flingScroll = (old >= 2) && (twoFingerMode == .scroll)
			releaseClickHoldIfNeeded()   // defensive: the left button must never stay stuck down
			endCursorIfNeeded()
			isDragging = false
			twoFingerResidual = false
			twoFingerMode = .undecided
			if flingCursor { startCursorMomentum() }
			if flingScroll { startScrollMomentum() }
		} else if new == 1 {
			if old >= 2 {
				// Leftover finger after a two-finger gesture: stay inert until full lift so it
				// doesn't jump the cursor.
				if twoFingerMode == .scroll { startScrollMomentum() }
				twoFingerResidual = true
				twoFingerMode = .undecided
			} else if old == 0 {
				startCursor()
			}
		} else if new >= 2 {
			releaseClickHoldIfNeeded()   // can't keep the button held during a two-finger gesture
			if isDragging { endCursorIfNeeded(); isDragging = false }
			beginTwoFinger()
		}
	}

	private func releaseClickHoldIfNeeded() {
		if clickHoldActive {
			CParsec.sendMouseClickMessage(ParsecMouseButton.init(rawValue: 1), false)
			clickHoldActive = false
		}
	}

	@objc private func appWillResignActive() { flushAllTouches() }

	// Drop all touch state and release any held button so nothing sticks when backgrounded.
	private func flushAllTouches() {
		stopMomentum()
		releaseClickHoldIfNeeded()
		endCursorIfNeeded()
		isDragging = false
		twoFingerResidual = false
		twoFingerMode = .undecided
		activeTouches = []
	}

	private func startCursor() {
		isDragging = true
		twoFingerResidual = false
		cursorDidMoveThisTouch = false
		singleTouchStartScreen = activeTouches.first?.location(in: view) ?? .zero
		if SettingsHandler.cursorMode == .direct {
			CParsec.sendMouseClickMessage(ParsecMouseButton.init(rawValue: 1), true)
		}
	}

	private func endCursorIfNeeded() {
		if isDragging && SettingsHandler.cursorMode == .direct {
			CParsec.sendMouseClickMessage(ParsecMouseButton.init(rawValue: 1), false)
		}
	}

	private func beginTwoFinger() {
		twoFingerMode = .undecided
		twoFingerDidMove = false
		accumulatedScrollY = 0.0
		let d = twoFingerDistanceAndMidpoint()
		startPinchDistance = d.distance
		lastPinchDistance = d.distance
		startTwoFingerMidpoint = d.midpoint
		lastTwoFingerMidpoint = d.midpoint
	}

	private func twoFingerDistanceAndMidpoint() -> (distance: CGFloat, midpoint: CGPoint) {
		let pts = activeTouches.prefix(2).map { $0.location(in: view) }
		guard pts.count == 2 else { return (0, pts.first ?? .zero) }
		let dx = pts[1].x - pts[0].x
		let dy = pts[1].y - pts[0].y
		let mid = CGPoint(x: (pts[0].x + pts[1].x) / 2, y: (pts[0].y + pts[1].y) / 2)
		return (hypot(dx, dy), mid)
	}

	private func handleActiveTouchesMoved() {
		if (isDragging || clickHoldActive), !twoFingerResidual, activeTouches.count == 1, let t = activeTouches.first {
			moveCursor(with: t)
		} else if activeTouches.count >= 2 {
			handleTwoFinger()
		}
	}

	private func moveCursor(with t: UITouch) {
		let zoom = scrollView.zoomScale
		let loc = t.location(in: view)
		let prev = t.previousLocation(in: view)
		if hypot(loc.x - singleTouchStartScreen.x, loc.y - singleTouchStartScreen.y) > tapMoveSlop {
			cursorDidMoveThisTouch = true
		}

		if CParsec.mouseInfo.mousePositionRelative {
			// Host has captured the pointer (e.g. a game): send true relative motion instead.
			let s = CGFloat(mouseSensitivity) / zoom
			CParsec.sendMouseDelta(Int32((loc.x - prev.x) * s), Int32((loc.y - prev.y) * s))
			return
		}

		if SettingsHandler.cursorMode == .direct {
			cursorContentPos = clampToContent(contentView.convert(loc, from: view))
		} else {
			// Relative finger movement, predicted locally; sensitivity scales down with zoom so the
			// cursor tracks the visible finger.
			let s = CGFloat(mouseSensitivity) / zoom
			let dcx = (loc.x - prev.x) * s
			let dcy = (loc.y - prev.y) * s
			cursorContentPos = clampToContent(CGPoint(x: cursorContentPos.x + dcx, y: cursorContentPos.y + dcy))
			// Smoothed velocity so a quick flick keeps gliding after the finger lifts.
			let now = CACurrentMediaTime()
			let dt = CGFloat(now - lastCursorMoveTime)
			if dt > 0.0005 && dt < 0.1 {
				cursorVelocity = CGPoint(x: cursorVelocity.x * 0.4 + (dcx / dt) * 0.6,
										 y: cursorVelocity.y * 0.4 + (dcy / dt) * 0.6)
			}
			lastCursorMoveTime = now
		}
		// Command the host to the ABSOLUTE predicted position (not a delta) so the host cursor can't
		// crawl behind network round-trips - clicks always land where the cursor is drawn.
		CParsec.sendMousePosition(Int32(cursorContentPos.x), Int32(cursorContentPos.y))
		centerViewportOnCursorPos()
		positionCursorOverlay()
	}

	private func handleTwoFinger() {
		let d = twoFingerDistanceAndMidpoint()
		if twoFingerMode == .undecided {
			let distDelta = abs(d.distance - startPinchDistance)
			let midDelta = hypot(d.midpoint.x - startTwoFingerMidpoint.x, d.midpoint.y - startTwoFingerMidpoint.y)
			let deadZone: CGFloat = 12.0
			if distDelta > deadZone || midDelta > deadZone {
				twoFingerMode = (distDelta > midDelta && zoomEnabled) ? .zoom : .scroll
				twoFingerDidMove = true
			}
		}
		switch twoFingerMode {
		case .zoom:
			if lastPinchDistance > 0 {
				applyZoom(to: scrollView.zoomScale * (d.distance / lastPinchDistance), anchorInView: d.midpoint)
			}
		case .scroll:
			let deltaY = Float(d.midpoint.y - lastTwoFingerMidpoint.y)
			let direction: Float = SettingsHandler.reverseScrollDirection ? -1.0 : 1.0
			let contribution = deltaY * scrollWheelSpeed * direction
			accumulatedScrollY += contribution
			let intScrollY = Int32(accumulatedScrollY)
			if intScrollY != 0 {
				CParsec.sendWheelMsg(x: 0, y: intScrollY)
				accumulatedScrollY -= Float(intScrollY)
			}
			// Track scroll velocity for a little post-flick momentum.
			let snow = CACurrentMediaTime()
			let sdt = Float(snow - lastScrollMoveTime)
			if sdt > 0.0005 && sdt < 0.1 {
				scrollVelocity = scrollVelocity * 0.4 + (contribution / sdt) * 0.6
			}
			lastScrollMoveTime = snow
		case .undecided:
			break
		}
		lastPinchDistance = d.distance
		lastTwoFingerMidpoint = d.midpoint
	}

	private func startCursorMomentum() {
		guard SettingsHandler.cursorMode == .touchpad, !CParsec.mouseInfo.mousePositionRelative else { return }
		guard CACurrentMediaTime() - lastCursorMoveTime < 0.06 else { return }   // finger was still moving at release
		guard hypot(cursorVelocity.x, cursorVelocity.y) > flingMinSpeed else { return }
		// Less glide when zoomed out: at 1x the cursor crosses the screen instead of panning the view.
		let glideScale = min(1.0, 0.3 + 0.7 * (scrollView.zoomScale - 1.0))
		cursorVelocity.x *= glideScale
		cursorVelocity.y *= glideScale
		cursorMomentumActive = true
		ensureMomentumLink()
	}

	private func startScrollMomentum() {
		guard CACurrentMediaTime() - lastScrollMoveTime < 0.06 else { return }
		guard abs(scrollVelocity) > scrollStartSpeed else { return }
		scrollMomentumActive = true
		ensureMomentumLink()
	}

	private func ensureMomentumLink() {
		if momentumLink == nil {
			let link = CADisplayLink(target: self, selector: #selector(momentumTick(_:)))
			link.add(to: .main, forMode: .common)
			momentumLink = link
		}
	}

	func stopMomentum() {
		cursorMomentumActive = false
		scrollMomentumActive = false
		cursorVelocity = .zero
		scrollVelocity = 0
		momentumLink?.invalidate()
		momentumLink = nil
	}

	@objc func momentumTick(_ link: CADisplayLink) {
		let dt = CGFloat(link.targetTimestamp - link.timestamp)
		if dt <= 0 { return }
		var stillActive = false

		if cursorMomentumActive {
			let decay = CGFloat(pow(cursorDecayPerSec, Double(dt)))
			cursorVelocity.x *= decay
			cursorVelocity.y *= decay
			let before = cursorContentPos
			cursorContentPos = clampToContent(CGPoint(x: cursorContentPos.x + cursorVelocity.x * dt,
													  y: cursorContentPos.y + cursorVelocity.y * dt))
			if !CParsec.mouseInfo.mousePositionRelative {
				CParsec.sendMousePosition(Int32(cursorContentPos.x), Int32(cursorContentPos.y))
			}
			centerViewportOnCursorPos()
			positionCursorOverlay()
			let stalled = abs(cursorContentPos.x - before.x) < 0.05 && abs(cursorContentPos.y - before.y) < 0.05
			if hypot(cursorVelocity.x, cursorVelocity.y) < cursorStopSpeed || stalled {
				cursorMomentumActive = false
			} else {
				stillActive = true
			}
		}

		if scrollMomentumActive {
			scrollVelocity *= Float(pow(scrollDecayPerSec, Double(dt)))
			accumulatedScrollY += scrollVelocity * Float(dt)
			let i = Int32(accumulatedScrollY)
			if i != 0 {
				CParsec.sendWheelMsg(x: 0, y: i)
				accumulatedScrollY -= Float(i)
			}
			if abs(scrollVelocity) < scrollStopSpeed {
				scrollMomentumActive = false
			} else {
				stillActive = true
			}
		}

		if !stillActive { stopMomentum() }
	}

	// Manually zoom the scroll view around a screen-space anchor (the pinch midpoint), keeping the
	// content point under the anchor fixed. Replaces the scroll view's own pinch recognizer.
	private func applyZoom(to targetScale: CGFloat, anchorInView anchor: CGPoint) {
		let oldZoom = scrollView.zoomScale
		let newZoom = min(max(targetScale, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
		guard abs(newZoom - oldZoom) > 0.0001 else { return }
		let off = scrollView.contentOffset
		let contentX = (anchor.x + off.x) / oldZoom
		let contentY = (anchor.y + off.y) / oldZoom
		scrollView.zoomScale = newZoom
		var newOff = CGPoint(x: contentX * newZoom - anchor.x, y: contentY * newZoom - anchor.y)
		let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
		let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
		newOff.x = min(max(0, newOff.x), maxX)
		newOff.y = min(max(0, newOff.y), maxY)
		scrollView.setContentOffset(newOff, animated: false)
		// Park the cursor at the viewport centre after zooming so a later drag doesn't snap the view.
		let bottomInset = keyboardVisible ? keyboardHeight : 0.0
		let centerX = (scrollView.bounds.width / 2 + scrollView.contentOffset.x) / newZoom
		let centerY = ((scrollView.bounds.height - bottomInset) / 2 + scrollView.contentOffset.y) / newZoom
		cursorContentPos = clampToContent(CGPoint(x: centerX, y: centerY))
		if !CParsec.mouseInfo.mousePositionRelative {
			CParsec.sendMousePosition(Int32(cursorContentPos.x), Int32(cursorContentPos.y))
		}
		positionCursorOverlay()
	}

	private func clampToContent(_ p: CGPoint) -> CGPoint {
		let w = view.bounds.width
		let h = view.bounds.height
		return CGPoint(x: min(max(0, p.x), w), y: min(max(0, p.y), h))
	}

	// Places the cursor overlay at the cursor's content position projected into screen space,
	// drawn at full Cursor Scale (no zoom division) so it stays crisp and constant-sized.
	func positionCursorOverlay() {
		guard let u = u else { return }
		let zoom = scrollView.zoomScale
		let off = scrollView.contentOffset
		let screenX = cursorContentPos.x * zoom - off.x
		let screenY = cursorContentPos.y * zoom - off.y
		let cs = CGFloat(SettingsHandler.cursorScale)
		let hotX = CGFloat(CParsec.mouseInfo.cursorHotX) * cs
		let hotY = CGFloat(CParsec.mouseInfo.cursorHotY) * cs
		let w = CGFloat(CParsec.mouseInfo.cursorWidth) * cs
		let h = CGFloat(CParsec.mouseInfo.cursorHeight) * cs
		u.frame = CGRect(x: screenX - hotX, y: screenY - hotY, width: w, height: h)
	}

	@objc func handleSingleFingerTap(_ gestureRecognizer: UITapGestureRecognizer) {
		// Only click if the finger stayed put; a moved finger was a cursor nudge, not a tap.
		if cursorDidMoveThisTouch { return }
		let location = gestureRecognizer.location(in: gestureRecognizer.view)
		let adjustedLocation = contentView.convert(location, from: view)
		touchController.onTap(typeOfTap: 1, location: adjustedLocation)
	}

	@objc func handleTwoFingerTap(_ gestureRecognizer: UITapGestureRecognizer) {
		// A two-finger TAP is a right click; if the fingers moved (pinch/scroll) it wasn't a tap.
		if twoFingerDidMove { return }
		let location: CGPoint
		switch SettingsHandler.rightClickPosition {
		case .firstFinger:
			location = gestureRecognizer.location(ofTouch: 0, in: gestureRecognizer.view)
			case .secondFinger:
			location = gestureRecognizer.location(ofTouch: 1, in: gestureRecognizer.view)
		default:
			location = gestureRecognizer.location(in: gestureRecognizer.view)
		}

		let adjustedLocation = contentView.convert(location, from: view)
		touchController.onTap(typeOfTap: 3, location: adjustedLocation)
	}

	@objc func handleThreeFinderTap(_ gestureRecognizer: UITapGestureRecognizer) {
		showKeyboard()
	}

	@objc func handleLongPress(_ gestureRecognizer: UIGestureRecognizer) {
		if SettingsHandler.cursorMode != .touchpad {
			return
		}
		switch gestureRecognizer.state {
		case .began:
			// Click-and-hold (file drag): hold the left button; the overlay keeps moving the cursor.
			clickHoldActive = true
			CParsec.sendMouseClickMessage(ParsecMouseButton.init(rawValue: 1), true)
		case .ended, .cancelled, .failed:
			releaseClickHoldIfNeeded()
		default:
			break
		}
	}

    // UIScrollViewDelegate
	func viewForZooming(in scrollView: UIScrollView) -> UIView? {
		return contentView
	}

	func scrollViewDidZoom(_ scrollView: UIScrollView) {
		// Centering is handled on cursor movement (updateImage) and at the end of a pinch.
	}

	func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
		centerViewportOnCursorPos()
	}

	// Slides the viewport so the host cursor stays centered on screen while zoomed in,
	// clamped so the cursor can still reach the true edges of the host screen.
	func centerViewportOnCursorPos() {
		guard scrollView.zoomScale > 1.0 else { return }
		let zoom = scrollView.zoomScale
		let bottomInset = keyboardVisible ? keyboardHeight : 0.0
		let visibleWidth = view.bounds.width
		let visibleHeight = view.bounds.height - bottomInset
		let cursorX = cursorContentPos.x * zoom
		let cursorY = cursorContentPos.y * zoom
		var targetX = cursorX - visibleWidth / 2
		var targetY = cursorY - visibleHeight / 2
		let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
		let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height + bottomInset)
		targetX = min(max(0, targetX), maxX)
		targetY = min(max(0, targetY), maxY)
		scrollView.setContentOffset(CGPoint(x: targetX, y: targetY), animated: false)
	}

	func setZoomEnabled(_ enabled: Bool) {
		// Pinch is driven manually in touchOverlay; just gate it with this flag.
		zoomEnabled = enabled
	}

}

extension ParsecViewController: UIPointerInteractionDelegate {
	func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
		return UIPointerStyle.hidden()
	}

	func pointerInteraction(_ inter: UIPointerInteraction, regionFor request: UIPointerRegionRequest, defaultRegion: UIPointerRegion) -> UIPointerRegion? {
		let loc = request.location
		if let iv = view!.hitTest(loc, with: nil) {
			let rect = view!.convert(iv.bounds, from: iv)
			let region = UIPointerRegion(rect: rect, identifier: iv.tag)
			return region
		}
		return nil
	}

}

class KeyboardButton: UIButton {
	let keyText: String
	let isToggleable: Bool
	var isOn = false

	required init(keyText: String, isToggleable: Bool) {
		self.keyText = keyText
		self.isToggleable = isToggleable
		super.init(frame: .zero)
		addTarget(self, action: #selector(handleTouchDown), for: .touchDown)
		addTarget(self, action: #selector(handleTouchUp), for: [.touchUpInside, .touchDragExit, .touchCancel])

	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	// Add a press-down animation for feedback
	@objc private func handleTouchDown() {
		self.alpha = 0.5
	}

	// Restore to normal state when touch ends
	@objc private func handleTouchUp() {
		UIView.animate(withDuration: 0.2) {
			self.alpha = 1.0
		}
	}
}

// MARK: - Virtual Keyboard
extension ParsecViewController: UIKeyInput, UITextInputTraits {
	var hasText: Bool {
		return true
	}

	var keyboardType: UIKeyboardType {
		get {
			return .asciiCapable
		}
		set {

		}
	}

	override var canBecomeFirstResponder: Bool {
		return true
	}

	func insertText(_ text: String) {
		CParsec.sendVirtualKeyboardInput(text: text)
	}

	func deleteBackward() {
		CParsec.sendVirtualKeyboardInput(text: "BACKSPACE")
	}

    // copied from moonlight https://github.com/moonlight-stream/moonlight-ios/blob/022352c1667788d8626b659d984a290aa5c25e17/Limelight/Input/StreamView.m#L393
	override var inputAccessoryView: UIView? {

		if let keyboardAccessoriesView {
			return keyboardAccessoriesView
		}
        // Refactored to UIView with autoresizing mask for better landscape support
        // Using frame-based layout for the container to avoid constraint conflicts with keyboard
		let containerView = UIView(frame: CGRect(x: 0, y: 0, width: self.view.bounds.width, height: 94))
        containerView.autoresizingMask = [.flexibleWidth]
        containerView.backgroundColor = .clear

		// Use a simple UIView instead of UIToolbar to avoid constraint conflicts
		let toolbarBackground = UIView(frame: CGRect(x: 0, y: 50, width: containerView.bounds.width, height: 44))
		toolbarBackground.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
		toolbarBackground.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)

		let scrollView = UIScrollView(frame: CGRect(x: 8, y: 0, width: toolbarBackground.bounds.width - 80, height: 44))
		scrollView.autoresizingMask = [.flexibleWidth]
		scrollView.showsHorizontalScrollIndicator = false

		let buttonStackView = UIStackView()
		buttonStackView.axis = .horizontal
		buttonStackView.distribution = .equalSpacing
		buttonStackView.alignment = .center
		buttonStackView.spacing = 8
		buttonStackView.translatesAutoresizingMaskIntoConstraints = false

		let shiftBarButton = createKeyboardButton(displayText: "⇧", keyText: "SHIFT", isToggleable: true)
		let windowsBarButton = createKeyboardButton(displayText: "⌘", keyText: "LGUI", isToggleable: true)
		let tabBarButton = createKeyboardButton(displayText: "⇥", keyText: "TAB", isToggleable: false)
		let escapeBarButton = createKeyboardButton(displayText: "⎋", keyText: "UIKeyInputEscape", isToggleable: false)
		let controlBarButton = createKeyboardButton(displayText: "⌃", keyText: "CONTROL", isToggleable: true)
		let altBarButton = createKeyboardButton(displayText: "⌥", keyText: "LALT", isToggleable: true)
		let deleteBarButton = createKeyboardButton(displayText: "Del", keyText: "DELETE", isToggleable: false)
		let f1Button = createKeyboardButton(displayText: "F1", keyText: "F1", isToggleable: false)
		let f2Button = createKeyboardButton(displayText: "F2", keyText: "F2", isToggleable: false)
		let f3Button = createKeyboardButton(displayText: "F3", keyText: "F3", isToggleable: false)
		let f4Button = createKeyboardButton(displayText: "F4", keyText: "F4", isToggleable: false)
		let f5Button = createKeyboardButton(displayText: "F5", keyText: "F5", isToggleable: false)
		let f6Button = createKeyboardButton(displayText: "F6", keyText: "F6", isToggleable: false)
		let f7Button = createKeyboardButton(displayText: "F7", keyText: "F7", isToggleable: false)
		let f8Button = createKeyboardButton(displayText: "F8", keyText: "F8", isToggleable: false)
		let f9Button = createKeyboardButton(displayText: "F9", keyText: "F9", isToggleable: false)
		let f10Button = createKeyboardButton(displayText: "F10", keyText: "F10", isToggleable: false)
		let f11Button = createKeyboardButton(displayText: "F11", keyText: "F11", isToggleable: false)
		let f12Button = createKeyboardButton(displayText: "F12", keyText: "F12", isToggleable: false)
		let upButton = createKeyboardButton(displayText: "↑", keyText: "UP", isToggleable: false)
		let downButton = createKeyboardButton(displayText: "↓", keyText: "DOWN", isToggleable: false)
		let leftButton = createKeyboardButton(displayText: "←", keyText: "LEFT", isToggleable: false)
		let rightButton = createKeyboardButton(displayText: "→", keyText: "RIGHT", isToggleable: false)

		let buttons = [tabBarButton, shiftBarButton, controlBarButton, altBarButton, windowsBarButton, escapeBarButton, f1Button, f2Button, f3Button, f4Button, f5Button, f6Button, f7Button, f8Button, f9Button, f10Button, f11Button, f12Button, deleteBarButton, upButton, downButton, leftButton, rightButton]

		for button in buttons {
			buttonStackView.addArrangedSubview(button)
		}

		scrollView.addSubview(buttonStackView)

		// Set constraints for the stack view inside the scroll view
		NSLayoutConstraint.activate([
			buttonStackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
			buttonStackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
			buttonStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
			buttonStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
			buttonStackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
		])

		// Done button with frame-based layout
		let doneButton = UIButton(type: .system)
		doneButton.frame = CGRect(x: toolbarBackground.bounds.width - 70, y: 0, width: 60, height: 44)
		doneButton.autoresizingMask = [.flexibleLeftMargin]
		doneButton.setTitle("Done", for: .normal)
		doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

		toolbarBackground.addSubview(scrollView)
		toolbarBackground.addSubview(doneButton)

		containerView.addSubview(toolbarBackground)

		keyboardAccessoriesView = containerView
		return containerView
	}

	func createKeyboardButton(displayText: String, keyText: String, isToggleable: Bool) -> UIButton {
		let button = KeyboardButton(keyText: keyText, isToggleable: isToggleable)

		// Set the image and button properties
		button.setTitle(displayText, for: .normal)
		button.titleLabel?.font = UIFont(name: "System", size: 10.0)
		button.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
		button.titleLabel?.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
		if let label = button.titleLabel {
			label.textAlignment = .center
		}
		button.backgroundColor = .black
		button.layer.cornerRadius = 3.0

		button.titleLabel?.contentMode = .scaleAspectFit

		// Set target and action for button
		button.addTarget(target, action: #selector(toolbarButtonClicked(_:)), for: .touchUpInside)

		return button
	}

	@objc func toolbarButtonClicked(_ sender: KeyboardButton) {
		let isToggleable = sender.isToggleable
		var isOn = sender.isOn

		if isToggleable {
			isOn.toggle()
			if isOn {
				sender.backgroundColor = .lightGray
			} else {
				sender.backgroundColor = .black
			}
		}

		sender.isOn = isOn
		let keyText = sender.keyText

		if isToggleable {
			if isOn {
				CParsec.sendVirtualKeyboardInput(text: keyText, isOn: true)
			} else {
				CParsec.sendVirtualKeyboardInput(text: keyText, isOn: false)
			}
		} else {
			CParsec.sendVirtualKeyboardInput(text: keyText)
		}

	}

	@objc func doneTapped() {
		// Resign first responder to dismiss the keyboard
		resignFirstResponder()
	}

	@objc func showKeyboard() {
		becomeFirstResponder()
	}

	// CRITICAL: This is the robust way to show the keyboard.
    // 1. Dispatch async to ensure view is attached to window.
    // 2. call reloadInputViews() to ensure updated accessory view (especially for rotation).
    // 3. call becomeFirstResponder().
    // 4. Do NOT simplify this to a synchronous call, or it will fail in some race conditions.
	func setKeyboardVisible(_ visible: Bool) {
		keyboardVisible = visible
		if visible {
            DispatchQueue.main.async {
                self.reloadInputViews()
                let success = self.becomeFirstResponder()
                if !success {
                   // Fallback: try again? or just log (can't log).
                   // Maybe ensure user interaction is on on window?
                }
            }
		} else {
			resignFirstResponder()
		}
	}

}

protocol ParsecTouchInputDelegate: AnyObject {
	// Called on every touch change with the authoritative set of currently-active touches.
	func parsecTouchesUpdated(_ activeTouches: Set<UITouch>, moved: Bool)
}

// A transparent overlay that owns every raw touch and forwards it to the controller. Sitting on
// top of (not inside) the scroll view, it gives deterministic, unfiltered touch delivery with no
// UIScrollView gesture races - the controller decides 1-finger cursor vs 2-finger pinch / scroll.
class TouchOverlayView: UIView {
	weak var inputDelegate: ParsecTouchInputDelegate?

	// Forward the live touch set (excluding ended/cancelled) on every event.
	private func forward(_ event: UIEvent?, moved: Bool) {
		let active = (event?.allTouches ?? []).filter { $0.phase != .ended && $0.phase != .cancelled }
		inputDelegate?.parsecTouchesUpdated(active, moved: moved)
	}
	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { forward(event, moved: false) }
	override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { forward(event, moved: true) }
	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { forward(event, moved: false) }
	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { forward(event, moved: false) }
}
