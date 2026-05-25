import Foundation
import UIKit
import ParsecSDK


protocol ParsecPlayground {
	init(viewController: UIViewController, updateImage: @escaping () -> Void)
	func viewDidLoad()
	func cleanUp()
	func updateSize(width: CGFloat, height: CGFloat)
}


class ParsecViewController: UIViewController, UIScrollViewDelegate {
	var glkView: ParsecPlayground!
	var gamePadController: GamepadController!
	var touchController: TouchController!
	var u: UIImageView?
	var lastImg: CGImage?
    var lastMouseX: Int32 = -1
    var lastMouseY: Int32 = -1
    var lastCursorHidden: Bool = false
	var isPinching = false
	var zoomEnabled = false
	var lastLongPressPoint : CGPoint = CGPoint()
	var accumulatedDeltaX: Float = 0.0
	var accumulatedDeltaY: Float = 0.0
	var lastPanLocation: CGPoint = .zero
	var lastPanTranslation: CGPoint = .zero

	// Trackpad / mouse-wheel scroll accumulators (separate from the touchscreen
	// 2-finger pan path, which keeps using velocity-based wheel messages for
	// direct-touch swipes).
	var accumulatedScrollX: Float = 0.0
	var accumulatedScrollY: Float = 0.0
	var lastScrollTranslation: CGPoint = .zero

	// Layout sync — fires a hotkey at the host when the iPad's hardware-keyboard
	// input language changes (e.g. Caps Lock toggle on Magic Keyboard).
	var languageSync: LanguageSyncCoordinator?
	
	var mouseSensitivity: Float = Float(SettingsHandler.mouseSensitivity)
	var activatedPanFingerNumber: Int = 0
	
	var keyboardAccessoriesView : UIView?
	var keyboardHeight : CGFloat = 0.0
	var keyboardVisible : Bool = false
	var onKeyboardVisibilityChanged: ((Bool) -> Void)?
	var scrollView: UIScrollView!
	var contentView: UIView!

	override var prefersPointerLocked: Bool {
		return true
	}
	
	override var prefersHomeIndicatorAutoHidden : Bool {
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
	
	func updateImage() {
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
			if lastImg != currentImg{
				u!.image = UIImage(cgImage: currentImg!)
				lastImg = currentImg!
			}

            // Using tracked values for bounds
			u?.frame = CGRect(x: Int(currentMouseX) - Int(Double(CParsec.mouseInfo.cursorHotX) * SettingsHandler.cursorScale),
							  y: Int(currentMouseY) - Int(Double(CParsec.mouseInfo.cursorHotY) * SettingsHandler.cursorScale),
							  width: Int(Double(CParsec.mouseInfo.cursorWidth) * SettingsHandler.cursorScale),
							  height: Int(Double(CParsec.mouseInfo.cursorHeight) * SettingsHandler.cursorScale))
            
			// Check bounds and pan if needed
			// Only pan if we are zoomed in OR if the keyboard is visible (to allow scrolling up)
			if scrollView.zoomScale > 1.0 || (keyboardVisible && scrollView.contentInset.bottom > 0) {
				let margin: CGFloat = 50.0
                
                // Convert cursor frame to screen coordinates (relative to the ViewController's view)
                // This accounts for zoom and current contentOffset automatically.
                let cursorFrameInScreen = contentView.convert(u!.frame, to: view)
                let viewBounds = view.bounds
                
                var targetOffsetX = scrollView.contentOffset.x
                var targetOffsetY = scrollView.contentOffset.y
                var shouldScroll = false
                
                // Check Left Edge
                if cursorFrameInScreen.minX < margin {
                    // We want the cursor to be at 'margin', so we shift contentOffset.
                    // NewOffset = CurrentOffset - (Margin - CurrentPos)
                    let diff = margin - cursorFrameInScreen.minX
                    targetOffsetX -= diff
                    shouldScroll = true
                }
                
                // Check Right Edge
                if cursorFrameInScreen.maxX > viewBounds.width - margin {
                    let diff = cursorFrameInScreen.maxX - (viewBounds.width - margin)
                    targetOffsetX += diff
                    shouldScroll = true
                }
                
                // Check Top Edge
                if cursorFrameInScreen.minY < margin {
                    let diff = margin - cursorFrameInScreen.minY
                    targetOffsetY -= diff
                    shouldScroll = true
                }
                
                // Check Bottom Edge
                // If keyboard is visible, the "bottom" is the top of the keyboard.
                let bottomInset = keyboardVisible ? keyboardHeight : 0.0
                let effectiveViewHeight = viewBounds.height - bottomInset
                
                if cursorFrameInScreen.maxY > effectiveViewHeight - margin {
                    let diff = cursorFrameInScreen.maxY - (effectiveViewHeight - margin)
                    targetOffsetY += diff
                    shouldScroll = true
                }
                
                if shouldScroll {
                    // Clamp to valid scroll range
                    // Including contentInset.bottom in calculation to allow scrolling past the original content size
                    let maxOffsetX = max(0, scrollView.contentSize.width - scrollView.bounds.width + scrollView.contentInset.right)
                    let maxOffsetY = max(0, scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom)
                    
                    targetOffsetX = max(-scrollView.contentInset.left, min(targetOffsetX, maxOffsetX))
                    targetOffsetY = max(-scrollView.contentInset.top, min(targetOffsetY, maxOffsetY))
                    
                    // Use a slightly smoother animation or immediate update? 
                    // 'updateImage' might be called frequently. animated: true might stack animations.
                    // For direct control, 'animated: false' is often snappier and prevents lag, 
                    // but 'true' is smoother visually. User asked for "image moves as mouse moves".
                    // Given high frequency, false is safer, or manual interpolation.
                    // Actually, standard UIScrollView behavior is usually direct setContentOffset.
                    scrollView.setContentOffset(CGPoint(x: targetOffsetX, y: targetOffsetY), animated: false)
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
		scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        /*
         We set minimumNumberOfTouches to 2 for the scroll view's pan gesture
         so that 1-finger drags are passed through to our custom gesture recognizers
         (for moving the mouse).
         Standard 2-finger pan will scroll the view.
         */
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
			if let parsecGLK = glkView as? ParsecGLKViewController,
			   let eaglContext = parsecGLK.eaglContext {
				PictureInPictureManager.shared.setup(sourceView: view, glContext: eaglContext, glkViewController: parsecGLK.glkViewController)
			}
		}

		touchController.viewDidLoad()
		gamePadController.viewDidLoad()

		u = UIImageView(frame: CGRect(x: 0,y: 0,width: 100, height: 100))
		contentView.addSubview(u!) // Add Cursor to ContentView
		
		setNeedsUpdateOfPrefersPointerLocked()
		
		let pointerInteraction = UIPointerInteraction(delegate: self)
		view.addInteraction(pointerInteraction)
		
		view.isMultipleTouchEnabled = true
		view.isUserInteractionEnabled = true

		let panGestureRecognizer = UIPanGestureRecognizer(target: self, action:#selector(self.handlePanGesture(_:)))
		panGestureRecognizer.delegate = self
		// Important: Allow our pan gesture to work alongside scrollview's?
		// No, we want 1 finger for this pan, 2 fingers for scrollview.
		// So they are distinct by touch count.
		// Exclude .indirectPointer (Magic Keyboard trackpad / iPad pointer) — those
		// events are handled directly via touchesMoved below to avoid the latency
		// of the gesture-recognizer state machine (issue #47: sticky cursor).
		panGestureRecognizer.allowedTouchTypes = [
			NSNumber(value: UITouch.TouchType.direct.rawValue),
			NSNumber(value: UITouch.TouchType.pencil.rawValue)
		]
		view.addGestureRecognizer(panGestureRecognizer)

		// Dedicated recognizer for trackpad / mouse-wheel scroll events
		// (iPadOS 13.4+, available unconditionally at deployment target 14).
		// maximumNumberOfTouches = 0 makes it respond ONLY to scroll-wheel events,
		// not to fingers — so touchscreen 2-finger swipes still flow through the
		// main pan recognizer with allowedTouchTypes = direct + pencil.
		let trackpadScrollRecognizer = UIPanGestureRecognizer(target: self, action: #selector(self.handleTrackpadScroll(_:)))
		trackpadScrollRecognizer.delegate = self
		trackpadScrollRecognizer.allowedScrollTypesMask = .all
		trackpadScrollRecognizer.maximumNumberOfTouches = 0
		view.addGestureRecognizer(trackpadScrollRecognizer)

		// Remove custom Pinch logic, ScrollView handles it.
		// But we might want to know isPinching status?
        // Let's rely on ScrollView delegate for updates.
		
		// Add tap gesture recognizer for single-finger touch
		let singleFingerTapGestureRecognizer = UITapGestureRecognizer(target: self, action:#selector(handleSingleFingerTap(_:)))
		singleFingerTapGestureRecognizer.numberOfTouchesRequired = 1
		singleFingerTapGestureRecognizer.allowedTouchTypes = [0, 2]
		view.addGestureRecognizer(singleFingerTapGestureRecognizer)

		// Add tap gesture recognizer for two-finger touch
		let twoFingerTapGestureRecognizer = UITapGestureRecognizer(target: self, action:#selector(handleTwoFingerTap(_:)))
		twoFingerTapGestureRecognizer.numberOfTouchesRequired = 2
		twoFingerTapGestureRecognizer.allowedTouchTypes = [0]
		view.addGestureRecognizer(twoFingerTapGestureRecognizer)
		//		view.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
		//		view.backgroundColor = UIColor(red: 0x66, green: 0xcc, blue: 0xff, alpha: 1.0)
		
		let threeFingerTapGestureRecognizer = UITapGestureRecognizer(target: self, action:#selector(handleThreeFinderTap(_:)))
		threeFingerTapGestureRecognizer.numberOfTouchesRequired = 3
		threeFingerTapGestureRecognizer.allowedTouchTypes = [0]
		view.addGestureRecognizer(threeFingerTapGestureRecognizer)
		
		let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action:#selector(handleLongPress(_:)))
		longPressGestureRecognizer.numberOfTouchesRequired = 1
		longPressGestureRecognizer.allowedTouchTypes = [0, 2]
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
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		if let parent = parent {
			parent.setChildForHomeIndicatorAutoHidden(self)
			parent.setChildViewControllerForPointerLock(self)
		}
		if keyboardVisible {
			becomeFirstResponder()
		}
		scrollView.pinchGestureRecognizer?.isEnabled = zoomEnabled
		startLanguageSyncIfNeeded()
	}
	
	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		if let parent = parent {
			parent.setChildForHomeIndicatorAutoHidden(nil)
			parent.setChildViewControllerForPointerLock(nil)
		}
		NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
		NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
		stopLanguageSync()
	}
	
	
	// Direct trackpad pointer handling (issue #47). With prefersPointerLocked = true,
	// iPadOS delivers Magic Keyboard trackpad motion as UITouches with
	// type == .indirectPointer. Routing those through a UIPanGestureRecognizer
	// imposes a recognition threshold and a state-machine churn between strokes,
	// which is what users experience as the "sticky / juddery" cursor.
	//
	// The main pan recognizer's allowedTouchTypes excludes .indirectPointer
	// (see viewDidLoad), so those touches reach this override unobstructed.
	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		super.touchesBegan(touches, with: event)
		for touch in touches where touch.type == .indirectPointer {
			accumulatedDeltaX = 0.0
			accumulatedDeltaY = 0.0
			break
		}
	}

	override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
		super.touchesMoved(touches, with: event)
		for touch in touches where touch.type == .indirectPointer {
			if SettingsHandler.cursorMode == .direct {
				let pos = touch.preciseLocation(in: view)
				let adjusted = contentView.convert(pos, from: view)
				CParsec.sendMousePosition(Int32(adjusted.x), Int32(adjusted.y))
			} else {
				let prev = touch.precisePreviousLocation(in: view)
				let cur = touch.preciseLocation(in: view)
				accumulatedDeltaX += Float(cur.x - prev.x) * mouseSensitivity
				accumulatedDeltaY += Float(cur.y - prev.y) * mouseSensitivity
				let dx = Int32(accumulatedDeltaX)
				let dy = Int32(accumulatedDeltaY)
				if dx != 0 || dy != 0 {
					CParsec.sendMouseDelta(dx, dy)
					accumulatedDeltaX -= Float(dx)
					accumulatedDeltaY -= Float(dy)
				}
			}
		}
	}

	override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {

		for press in presses {
			CParsec.sendKeyboardMessage(event:KeyBoardKeyEvent(input: press.key, isPressBegin: true) )
		}

	}
	
	override func pressesEnded (_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		
		for press in presses {
			CParsec.sendKeyboardMessage(event:KeyBoardKeyEvent(input: press.key, isPressBegin: false) )
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

extension ParsecViewController : UIGestureRecognizerDelegate {

	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		return true
	}

	@objc func handlePinchGesture(_ gestureRecognizer: UIPinchGestureRecognizer) {
		// Pinch is handled by UIScrollView
	}

	@objc func handlePanGesture(_ gestureRecognizer: UIPanGestureRecognizer)
	{
		//		print("number = \(gestureRecognizer.numberOfTouches) status = \(gestureRecognizer.state.rawValue)")
		// lock activatedPanFingerNumber in case user not releasing both finger at the same time
		if gestureRecognizer.numberOfTouches == 0 {
			if gestureRecognizer.state == .ended || gestureRecognizer.state == .cancelled {
				activatedPanFingerNumber = 0
				// Reset accumulators
				accumulatedDeltaX = 0.0
				accumulatedDeltaY = 0.0
				lastPanTranslation = .zero

				if SettingsHandler.cursorMode == .direct {
					let button = ParsecMouseButton.init(rawValue: 1)
					CParsec.sendMouseClickMessage(button, false)
				}
			}
		} else if activatedPanFingerNumber == 2 || (gestureRecognizer.numberOfTouches == 2 && activatedPanFingerNumber == 0) {
            // Native UIScrollView handles 2-finger pan for scrolling.
            // We disable the mouse wheel for now to avoid conflict, or we can check gesture state.
            // If user wants wheel, we might need a specific mode or 3 fingers.
			if zoomEnabled {
				return
			}
			activatedPanFingerNumber = 2
			let velocity = gestureRecognizer.velocity(in: gestureRecognizer.view)
			
			if abs(velocity.y) > 2 {
				// Run your function when the user uses two fingers and swipes upwards
				CParsec.sendWheelMsg(x: 0, y: Int32(Float(velocity.y) / 20 * mouseSensitivity))
				return
			}
			if SettingsHandler.cursorMode == .direct {
				let location = gestureRecognizer.location(in:gestureRecognizer.view)
				touchController.onTouch(typeOfTap: 1, location: location, state: gestureRecognizer.state)
			}
		} else if activatedPanFingerNumber == 1 || (gestureRecognizer.numberOfTouches == 1 && activatedPanFingerNumber == 0) {
			activatedPanFingerNumber = 1
			// move mouse
			if SettingsHandler.cursorMode == .direct {
                // Map screen tap to content coordinates
				let position = gestureRecognizer.location(in: gestureRecognizer.view)
                // Convert to content coordinates
				let adjustedPosition = contentView.convert(position, from: view)
				CParsec.sendMousePosition(Int32(adjustedPosition.x), Int32(adjustedPosition.y))
			} else {
				// Simple translation-based movement with sub-pixel accumulation
				let currentTranslation = gestureRecognizer.translation(in: gestureRecognizer.view)

				if gestureRecognizer.state == .began {
					lastPanTranslation = .zero
					accumulatedDeltaX = 0.0
					accumulatedDeltaY = 0.0
				}

				// Calculate delta since last update
				let deltaX = Float(currentTranslation.x - lastPanTranslation.x) * mouseSensitivity
				let deltaY = Float(currentTranslation.y - lastPanTranslation.y) * mouseSensitivity

				lastPanTranslation = currentTranslation

				// Accumulate for sub-pixel precision
				accumulatedDeltaX += deltaX
				accumulatedDeltaY += deltaY

				// Send movement when we have at least 1 pixel
				let intDeltaX = Int32(accumulatedDeltaX)
				let intDeltaY = Int32(accumulatedDeltaY)

				if intDeltaX != 0 || intDeltaY != 0 {
					CParsec.sendMouseDelta(intDeltaX, intDeltaY)
					accumulatedDeltaX -= Float(intDeltaX)
					accumulatedDeltaY -= Float(intDeltaY)
				}
			}

			if gestureRecognizer.state == .began && SettingsHandler.cursorMode == .direct {
				let button = ParsecMouseButton.init(rawValue: 1)
				CParsec.sendMouseClickMessage(button, true)
			}

		}
	}
	
	// Trackpad / mouse-wheel scroll handler, separated from handlePanGesture so it
	// can use translation deltas (smooth) instead of velocity (rough wheel
	// messages). Hooked up by a UIPanGestureRecognizer with
	// allowedScrollTypesMask = .all and maximumNumberOfTouches = 0 in viewDidLoad,
	// so it only sees scroll-wheel / trackpad-scroll events, never finger touches.
	@objc func handleTrackpadScroll(_ gestureRecognizer: UIPanGestureRecognizer) {
		switch gestureRecognizer.state {
		case .began:
			lastScrollTranslation = .zero
			accumulatedScrollX = 0.0
			accumulatedScrollY = 0.0
		case .changed:
			let translation = gestureRecognizer.translation(in: gestureRecognizer.view)
			let deltaX = Float(translation.x - lastScrollTranslation.x) * mouseSensitivity
			let deltaY = Float(translation.y - lastScrollTranslation.y) * mouseSensitivity
			lastScrollTranslation = translation
			accumulatedScrollX += deltaX
			accumulatedScrollY += deltaY
			let intX = Int32(accumulatedScrollX)
			let intY = Int32(accumulatedScrollY)
			if intX != 0 || intY != 0 {
				CParsec.sendWheelMsg(x: intX, y: intY)
				accumulatedScrollX -= Float(intX)
				accumulatedScrollY -= Float(intY)
			}
		case .ended, .cancelled, .failed:
			lastScrollTranslation = .zero
			accumulatedScrollX = 0.0
			accumulatedScrollY = 0.0
		default:
			break
		}
	}

	@objc func handleSingleFingerTap(_ gestureRecognizer: UITapGestureRecognizer) {

		let location = gestureRecognizer.location(in:gestureRecognizer.view)
		let adjustedLocation = contentView.convert(location, from: view)
		touchController.onTap(typeOfTap: 1, location: adjustedLocation)
	}
	
	@objc func handleTwoFingerTap(_ gestureRecognizer: UITapGestureRecognizer) {
		
		let location : CGPoint;
		switch SettingsHandler.rightClickPosition {
		case .firstFinger:
			location = gestureRecognizer.location(ofTouch: 0, in: gestureRecognizer.view)
			break;
		case .secondFinger:
			location = gestureRecognizer.location(ofTouch: 1, in: gestureRecognizer.view)
			break
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
		let button = ParsecMouseButton.init(rawValue: 1)

		if gestureRecognizer.state == .began{
			CParsec.sendMouseClickMessage(button, true)
			let location = gestureRecognizer.location(in: gestureRecognizer.view)
			lastLongPressPoint = contentView.convert(location, from: view)
		} else if gestureRecognizer.state == .ended {
			CParsec.sendMouseClickMessage(button, false)
		} else if gestureRecognizer.state == .changed {
			let newLocation = gestureRecognizer.location(in: gestureRecognizer.view)
            let adjustedNewLocation = contentView.convert(newLocation, from: view)
			CParsec.sendMouseDelta(
				Int32(Float(adjustedNewLocation.x - lastLongPressPoint.x) * mouseSensitivity),
				Int32(Float(adjustedNewLocation.y - lastLongPressPoint.y) * mouseSensitivity)
			)
			lastLongPressPoint = adjustedNewLocation
		}
	}
	
    // UIScrollViewDelegate
	func viewForZooming(in scrollView: UIScrollView) -> UIView? {
		return contentView
	}

	func scrollViewDidZoom(_ scrollView: UIScrollView) {
		// Update isPinching if needed, or other logic
	}
	
	func setZoomEnabled(_ enabled: Bool) {
		zoomEnabled = enabled
		scrollView.pinchGestureRecognizer?.isEnabled = enabled
	}
	
}
	
extension ParsecViewController : UIPointerInteractionDelegate {
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
extension ParsecViewController : UIKeyInput, UITextInputTraits {
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
		// Yield FR to the VC so the soft keyboard can attach. Symmetric to the
		// path in setKeyboardVisible.
		languageSync?.yieldFirstResponder()
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
                // Cede first-responder so the soft keyboard can attach to the
                // view controller (the hidden language-sync field holds it
                // otherwise).
                self.languageSync?.yieldFirstResponder()
                let success = self.becomeFirstResponder()
                if !success {
                   // Fallback: try again? or just log (can't log).
                   // Maybe ensure user interaction is on on window?
                }
            }
		} else {
			resignFirstResponder()
			// Reclaim so we keep getting currentInputModeDidChangeNotification
			// while the soft keyboard is hidden.
			languageSync?.reclaimFirstResponder()
		}
	}

}

// MARK: - Language sync (Mac ↔ iPad keyboard layout)
//
// Goal: when the user switches the iPad's hardware-keyboard input language
// (Caps Lock toggle on Magic Keyboard / Ctrl+Space / Globe key), fire a hotkey
// at the host so its input source switches in lock-step.
//
// Why a hotkey and not a "real" Unicode-text path: Parsec's iOS SDK only sends
// MESSAGE_KEYBOARD with HID scancodes (see ParsecSDKBridge.sendKeyboardMessage).
// There is no documented MESSAGE_CHAR / UTF-8 path that would let us bypass
// the host layout. So we ask the host to switch its own layout. Default
// hotkey is Ctrl+Space (macOS built-in "select previous input source"); user
// can pick something else if their host config differs.
//
// Detecting the language change requires a UIResponder that accepts text
// input to be first responder (Apple's `currentInputModeDidChangeNotification`
// only fires in that case). We use a 1×1 alpha-0 UITextField with an empty
// inputView so the soft keyboard never appears; the field forwards
// pressesBegan/Ended to the view controller so hardware-keyboard scancodes
// continue to flow through the existing pipeline.
extension ParsecViewController {
	func startLanguageSyncIfNeeded() {
		guard SettingsHandler.syncKeyboardLayout, languageSync == nil else { return }
		let coordinator = LanguageSyncCoordinator(host: self, keyForwardTarget: self)
		coordinator.onLanguageChange = { [weak self] _ in
			self?.sendLayoutSyncHotkey()
		}
		coordinator.start()
		languageSync = coordinator
	}

	func stopLanguageSync() {
		languageSync?.stop()
		languageSync = nil
	}

	func sendLayoutSyncHotkey() {
		let hotkey = SettingsHandler.layoutSyncHotkey
		switch hotkey {
		case .none:
			return
		case .ctrlSpace:
			tapKey(modifierKey: "CONTROL", normalKey: "SPACE")
		case .cmdSpace:
			tapKey(modifierKey: "LGUI", normalKey: "SPACE")
		case .altSpace:
			tapKey(modifierKey: "LALT", normalKey: "SPACE")
		case .altShift:
			tapModifierChord(firstModifier: "LALT", secondModifier: "SHIFT")
		}
	}

	// Press modifier → press+release normal key → release modifier. The
	// release of the normal key is async (+20ms) inside CParsec, so we delay
	// the modifier release by ~50ms to keep the chord intact on the host.
	private func tapKey(modifierKey: String, normalKey: String) {
		CParsec.sendVirtualKeyboardInput(text: modifierKey, isOn: true)
		CParsec.sendVirtualKeyboardInput(text: normalKey)
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
			CParsec.sendVirtualKeyboardInput(text: modifierKey, isOn: false)
		}
	}

	// Two modifiers held + released as a chord (e.g. Alt+Shift on Windows).
	private func tapModifierChord(firstModifier: String, secondModifier: String) {
		CParsec.sendVirtualKeyboardInput(text: firstModifier, isOn: true)
		CParsec.sendVirtualKeyboardInput(text: secondModifier, isOn: true)
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
			CParsec.sendVirtualKeyboardInput(text: secondModifier, isOn: false)
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
			CParsec.sendVirtualKeyboardInput(text: firstModifier, isOn: false)
		}
	}
}

// Hidden field that owns first-responder status so that
// UITextInputMode.currentInputModeDidChangeNotification keeps firing. It
// forwards all UIPress events to the host view controller without consuming
// them — that way hardware-keyboard scancodes continue to flow through
// ParsecViewController.pressesBegan/Ended unchanged.
final class LanguageSyncTextField: UITextField {
	weak var keyForwardTarget: UIResponder?

	override var canBecomeFirstResponder: Bool { return true }

	// Returning an empty UIView for inputView suppresses the on-screen keyboard
	// while the field is first responder, even without a connected hardware
	// keyboard. Returning the field's existing inputAccessoryView (none) keeps
	// the accessory chrome empty too.
	private let _emptyInputView = UIView()
	override var inputView: UIView? {
		get { return _emptyInputView }
		set { /* ignore — we want the soft kb suppressed unconditionally */ }
	}

	// By NOT calling super, we prevent UITextField's legacy text-input path
	// from consuming printable keys via UIKeyInput.insertText. Same trick
	// Moonlight uses in StreamView.m pressesBegan/pressesEnded.
	override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		keyForwardTarget?.pressesBegan(presses, with: event)
	}
	override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		keyForwardTarget?.pressesEnded(presses, with: event)
	}
	override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		keyForwardTarget?.pressesChanged(presses, with: event)
	}
	override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		keyForwardTarget?.pressesCancelled(presses, with: event)
	}
}

// Owns the hidden field, the change-notification observer, and the
// last-seen-language memo. Cooperates with the view controller's
// becomeFirstResponder / resignFirstResponder lifecycle via yield/reclaim.
final class LanguageSyncCoordinator {
	private weak var host: UIViewController?
	private weak var keyForwardTarget: UIResponder?
	private var hiddenField: LanguageSyncTextField?
	private var observer: NSObjectProtocol?
	private var lastLanguage: String?
	var onLanguageChange: ((String?) -> Void)?

	init(host: UIViewController, keyForwardTarget: UIResponder) {
		self.host = host
		self.keyForwardTarget = keyForwardTarget
	}

	func start() {
		guard hiddenField == nil, let hostView = host?.view else { return }

		let field = LanguageSyncTextField(frame: CGRect(x: -100, y: -100, width: 1, height: 1))
		field.alpha = 0
		field.autocorrectionType = .no
		field.autocapitalizationType = .none
		field.spellCheckingType = .no
		field.smartDashesType = .no
		field.smartQuotesType = .no
		field.smartInsertDeleteType = .no
		field.keyForwardTarget = keyForwardTarget
		hostView.addSubview(field)
		field.becomeFirstResponder()
		hiddenField = field

		// Seed with current language so we don't fire a redundant hotkey on
		// first real change.
		lastLanguage = currentLanguage(from: nil)

		observer = NotificationCenter.default.addObserver(
			forName: UITextInputMode.currentInputModeDidChangeNotification,
			object: nil,
			queue: .main
		) { [weak self] note in
			self?.handleChange(note: note)
		}
	}

	func stop() {
		if let obs = observer {
			NotificationCenter.default.removeObserver(obs)
			observer = nil
		}
		hiddenField?.resignFirstResponder()
		hiddenField?.removeFromSuperview()
		hiddenField = nil
	}

	// Step aside so the host view controller can become first responder
	// (e.g. when the soft keyboard is shown via 3-finger tap).
	func yieldFirstResponder() {
		hiddenField?.resignFirstResponder()
	}

	// Re-take first-responder status when the host VC has resigned (typically
	// after the soft keyboard is dismissed).
	func reclaimFirstResponder() {
		hiddenField?.becomeFirstResponder()
	}

	private func handleChange(note: Notification) {
		let lang = currentLanguage(from: note)
		guard lang != lastLanguage else { return }
		lastLanguage = lang
		onLanguageChange?(lang)
	}

	// Prefer the mode advertised by the notification, fall back to whatever
	// the hidden field currently reports. Either may be nil if no responder
	// accepts text input at the moment.
	private func currentLanguage(from note: Notification?) -> String? {
		if let mode = note?.object as? UITextInputMode, let lang = mode.primaryLanguage {
			return lang
		}
		return hiddenField?.textInputMode?.primaryLanguage
	}
}
