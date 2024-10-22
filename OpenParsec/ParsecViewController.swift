//
//  PoinerRegion.swift
//  OpenParsec
//
//  Created by s s on 2024/5/11.
//

import Foundation
import UIKit
import ParsecSDK


protocol ParsecPlayground {
	init(viewController: UIViewController, updateImage: @escaping () -> Void)
	func viewDidLoad()
	func cleanUp()
}


class ParsecViewController :UIViewController {
	var glkView: ParsecPlayground!
	var gamePadController: GamepadController!
	var touchController: TouchController!
	var u:UIImageView?
	var lastImg: CGImage?
	
	var lastLongPressPoint : CGPoint = CGPoint()
	
	var keyboardAccessoriesView : UIView?
	var keyboardHeight : CGFloat = 0.0
	
	override var prefersPointerLocked: Bool {
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
		if CParsec.mouseInfo.cursorImg != nil && !CParsec.mouseInfo.cursorHidden {
			if lastImg != CParsec.mouseInfo.cursorImg{
				u!.image = UIImage(cgImage: CParsec.mouseInfo.cursorImg!)
				lastImg = CParsec.mouseInfo.cursorImg!
			}

			u?.frame = CGRect(x: Int(CParsec.mouseInfo.mouseX) - Int(Float(CParsec.mouseInfo.cursorHotX) * SettingsHandler.cursorScale),
							  y: Int(CParsec.mouseInfo.mouseY) - Int(Float(CParsec.mouseInfo.cursorHotY) * SettingsHandler.cursorScale),
							  width: Int(Float(CParsec.mouseInfo.cursorWidth) * SettingsHandler.cursorScale),
							  height: Int(Float(CParsec.mouseInfo.cursorHeight) * SettingsHandler.cursorScale))
			
		} else {
			u?.image = nil
		}
	}
	
	override func viewDidLoad() {
		glkView.viewDidLoad()
		touchController.viewDidLoad()
		gamePadController.viewDidLoad()
		
		u = UIImageView(frame: CGRect(x: 0,y: 0,width: 100, height: 100))
		view.addSubview(u!)
		
		becomeFirstResponder()
		setNeedsUpdateOfPrefersPointerLocked()
		
		let pointerInteraction = UIPointerInteraction(delegate: self)
		view.addInteraction(pointerInteraction)
		
		view.isMultipleTouchEnabled = true
		view.isUserInteractionEnabled = true

		let panGestureRecognizer = UIPanGestureRecognizer(target:self, action:#selector(self.handlePanGesture(_:)))
		panGestureRecognizer.delegate = self
		view.addGestureRecognizer(panGestureRecognizer)

		
		
		// Add tap gesture recognizer for single-finger touch
		let singleFingerTapGestureRecognizer = UITapGestureRecognizer(target:self, action:#selector(handleSingleFingerTap(_:)))
		singleFingerTapGestureRecognizer.numberOfTouchesRequired = 1
		singleFingerTapGestureRecognizer.allowedTouchTypes = [0, 2]
		view.addGestureRecognizer(singleFingerTapGestureRecognizer)

		// Add tap gesture recognizer for two-finger touch
		let twoFingerTapGestureRecognizer = UITapGestureRecognizer(target:self, action:#selector(handleTwoFingerTap(_:)))
		twoFingerTapGestureRecognizer.numberOfTouchesRequired = 2
		twoFingerTapGestureRecognizer.allowedTouchTypes = [0]
		view.addGestureRecognizer(twoFingerTapGestureRecognizer)
		//		view.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
		//		view.backgroundColor = UIColor(red: 0x66, green: 0xcc, blue: 0xff, alpha: 1.0)
		
		let threeFingerTapGestureRecognizer = UITapGestureRecognizer(target:self, action:#selector(handleThreeFinderTap(_:)))
		threeFingerTapGestureRecognizer.numberOfTouchesRequired = 3
		threeFingerTapGestureRecognizer.allowedTouchTypes = [0]
		view.addGestureRecognizer(threeFingerTapGestureRecognizer)
		
		let longPressGestureRecognizer = UILongPressGestureRecognizer(target:self, action:#selector(handleLongPress(_:)))
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
	
	override func viewWillAppear(_ animated: Bool) {
		if let parent = parent {
			parent.setChildForHomeIndicatorAutoHidden(self)
			parent.setChildViewControllerForPointerLock(self)
		}
		setNeedsUpdateOfPrefersPointerLocked()
	}
	
	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		if let parent = parent {
			parent.setChildForHomeIndicatorAutoHidden(nil)
			parent.setChildViewControllerForPointerLock(nil)
		}
		NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
		NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
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
	
	@objc func keyboardWillShow(_ notification: Notification) {
		if let keyboardFrame: NSValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
			let keyboardRectangle = keyboardFrame.cgRectValue
			keyboardHeight = keyboardRectangle.height - 50 // minus handle button height
		}
	}
	
	@objc func keyboardWillHide(_ notification: Notification) {
		view.frame.origin.y = 0
	}
	
}

extension ParsecViewController : UIGestureRecognizerDelegate {
	
	@objc func handlePanGesture(_ gestureRecognizer:UIPanGestureRecognizer)
	{
		//		print("number = \(gestureRecognizer.numberOfTouches) status = \(gestureRecognizer.state.rawValue)")
		if gestureRecognizer.numberOfTouches == 2 {
			let velocity = gestureRecognizer.velocity(in: gestureRecognizer.view)
			
			if abs(velocity.y) > 2 {
				// Run your function when the user uses two fingers and swipes upwards
				CParsec.sendWheelMsg(x: 0, y: Int32(velocity.y / 20))
				return
			}
			if SettingsHandler.cursorMode == .direct {
				let location = gestureRecognizer.location(in:gestureRecognizer.view)
				touchController.onTouch(typeOfTap: 1, location: location, state: gestureRecognizer.state)
			}

		} else if gestureRecognizer.numberOfTouches == 1 {

			if SettingsHandler.cursorMode == .direct {
				let position = gestureRecognizer.location(in: gestureRecognizer.view)
				CParsec.sendMousePosition(Int32(position.x), Int32(position.y))
			} else {
				let delta = gestureRecognizer.velocity(in: gestureRecognizer.view)
				CParsec.sendMouseDelta(Int32(delta.x / 60), Int32(delta.y / 60))
			}

			
			if gestureRecognizer.state == .began && SettingsHandler.cursorMode == .direct {
				let button = ParsecMouseButton.init(rawValue: 1)
				CParsec.sendMouseClickMessage(button, true)
			}
			
		} else if gestureRecognizer.numberOfTouches == 0 {
			if (gestureRecognizer.state == .ended || gestureRecognizer.state == .cancelled) && SettingsHandler.cursorMode == .direct {
				let button = ParsecMouseButton.init(rawValue: 1)
				CParsec.sendMouseClickMessage(button, false)
			}
		}
		
		
	}
	
	@objc func handleSingleFingerTap(_ gestureRecognizer:UITapGestureRecognizer)
	{
		let location = gestureRecognizer.location(in:gestureRecognizer.view)
		touchController.onTap(typeOfTap: 1, location: location)
		
	}
	
	@objc func handleTwoFingerTap(_ gestureRecognizer:UITapGestureRecognizer)
	{
		let location = gestureRecognizer.location(in: gestureRecognizer.view)
		touchController.onTap(typeOfTap: 3, location: location)
	}
	
	@objc func handleThreeFinderTap(_ gestureRecognizer:UITapGestureRecognizer) {
		showKeyboard()
	}
	
	@objc func handleLongPress(_ gestureRecognizer:UIGestureRecognizer) {
		if SettingsHandler.cursorMode != .touchpad {
			return
		}
		let button = ParsecMouseButton.init(rawValue: 1)
		
		if gestureRecognizer.state == .began{
			CParsec.sendMouseClickMessage(button, true)
			lastLongPressPoint = gestureRecognizer.location(in: gestureRecognizer.view)
		} else if gestureRecognizer.state == .ended {
			CParsec.sendMouseClickMessage(button, false)
		} else if gestureRecognizer.state == .changed {
			let newLocation = gestureRecognizer.location(in: gestureRecognizer.view)
			CParsec.sendMouseDelta(Int32(newLocation.x - lastLongPressPoint.x), Int32(newLocation.y - lastLongPressPoint.y))
			lastLongPressPoint = newLocation
		}
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

class KeyBoardButton : UIButton {
	let keyText : String
	let isToggleable : Bool
	var isOn = false
	
	required init(keyText: String, isToggleable: Bool) {
		self.keyText = keyText
		self.isToggleable = isToggleable
		super.init(frame: .zero)
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
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
		let containerView = UIStackView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 94))
		
		let customToolbarView = UIToolbar(frame: CGRect(x: 0, y: 50, width: self.view.bounds.size.width, height: 44))
		
		let scrollView = UIScrollView()
		scrollView.showsHorizontalScrollIndicator = false
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		
		let buttonStackView = UIStackView()
		buttonStackView.axis = .horizontal
		buttonStackView.distribution = .equalSpacing
		buttonStackView.alignment = .center
		buttonStackView.spacing = 8
		buttonStackView.translatesAutoresizingMaskIntoConstraints = false

		let windowsBarButton = createKeyboardButton(displayText: "⌘", keyText: "LGUI", isToggleable: true)
		let tabBarButton = createKeyboardButton(displayText: "⇥", keyText: "TAB", isToggleable: false)
		let shiftBarButton = createKeyboardButton(displayText: "⇧", keyText: "SHIFT", isToggleable: true)
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
		let f12Button = createKeyboardButton(displayText: "F12", keyText: "F11", isToggleable: false)
		let upButton = createKeyboardButton(displayText: "↑", keyText: "UP", isToggleable: false)
		let downButton = createKeyboardButton(displayText: "↓", keyText: "DOWN", isToggleable: false)
		let leftButton = createKeyboardButton(displayText: "←", keyText: "LEFT", isToggleable: false)
		let rightButton = createKeyboardButton(displayText: "→", keyText: "RIGHT", isToggleable: false)
		

		let buttons = [windowsBarButton, escapeBarButton, tabBarButton, shiftBarButton, controlBarButton, altBarButton, deleteBarButton,
					   f1Button, f2Button, f3Button, f4Button, f5Button, f6Button, f7Button, f8Button, f9Button, f10Button, f11Button, f12Button,
								   upButton, downButton, leftButton, rightButton
		]
		
		for button in buttons {
			buttonStackView.addArrangedSubview(button)
		}
		
		scrollView.addSubview(buttonStackView)
		
		
		
		let scrollViewContainer = UIView()
		scrollViewContainer.translatesAutoresizingMaskIntoConstraints = false
		scrollViewContainer.addSubview(scrollView)

		
		NSLayoutConstraint.activate([
			scrollView.leadingAnchor.constraint(equalTo: scrollViewContainer.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: scrollViewContainer.trailingAnchor),
			scrollView.topAnchor.constraint(equalTo: scrollViewContainer.topAnchor),
			scrollView.bottomAnchor.constraint(equalTo: scrollViewContainer.bottomAnchor)
		])
		
		NSLayoutConstraint.activate([
			scrollViewContainer.heightAnchor.constraint(equalToConstant: 44),
			scrollViewContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 100)
		])

		// 10. Set constraints for the stack view inside the scroll view
		NSLayoutConstraint.activate([
			buttonStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
			buttonStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
			buttonStackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
			buttonStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
			buttonStackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
		])
		
		
		let container2 = UIStackView()
		container2.axis = .horizontal
		container2.distribution = .fill
		container2.alignment = .center
		container2.addArrangedSubview(scrollViewContainer)
		
		let doneButton2 = UIButton()
		doneButton2.setTitle("Done", for: .normal)
		doneButton2.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
		if #available(iOS 15.0, *) {
			doneButton2.setTitleColor(.tintColor,  for: .normal)
		}
		container2.addArrangedSubview(doneButton2)

		let scrollViewBarButton = UIBarButtonItem(customView: container2)
		
		customToolbarView.setItems([scrollViewBarButton], animated: false)
		
		
		// Create a draggable handle button
		let handleButton = UIButton(type: .system)
		handleButton.setTitle("↑↓", for: .normal)
		handleButton.frame.size = CGSize(width: 40, height: 40)
		handleButton.backgroundColor = UIColor.systemGray.withAlphaComponent(0.5)
		handleButton.center = containerView.convert(containerView.center, to: containerView.superview)
		handleButton.frame.origin.y = 0
		
		let panGestureRecognizer = UIPanGestureRecognizer(target:self, action:#selector(self.handleDragGesture(_:)))
		panGestureRecognizer.maximumNumberOfTouches = 1
		handleButton.addGestureRecognizer(panGestureRecognizer)
		
		handleButton.layer.cornerRadius = 20
		containerView.addSubview(handleButton)
		
		containerView.addSubview(customToolbarView)
		
		keyboardAccessoriesView = containerView
		return containerView
	}
	
	func createKeyboardButton(displayText: String, keyText: String, isToggleable: Bool) -> UIButton {
		let button = KeyBoardButton(keyText: keyText, isToggleable: isToggleable)
		
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
	
	@objc func toolbarButtonClicked(_ sender: KeyBoardButton) {
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
	
	@objc func handleDragGesture(_ gestureRecognizer:UIPanGestureRecognizer) {
		let v = view.frame.origin.y + gestureRecognizer.velocity(in: nil).y / 50.0
		let newY = ParsecSDKBridge.clamp(v, minValue: -keyboardHeight, maxValue: 0)
		view.frame.origin.y = newY
	}

	@objc func doneTapped() {
		// Resign first responder to dismiss the keyboard
		resignFirstResponder()
	}
	
	@objc func showKeyboard() {
		becomeFirstResponder()
	}
	
}
