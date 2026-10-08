import UIKit
import GameController
import ParsecSDK

struct ScrollWheel {
	let x: Int32
	let y: Int32
}

enum GCMouseScrollAxis {
	case x
	case y
}

enum GCMouseScrollMapper {
	static func adjustedDelta(axis: GCMouseScrollAxis, rawValue: Float, naturalScrolling: Bool) -> (x: Float, y: Float) {
		let direction: Float = naturalScrolling ? -1.0 : 1.0
		let adjusted = rawValue * direction
		switch axis {
		case .x:
			return (x: 0, y: adjusted)
		case .y:
			return (x: adjusted, y: 0)
		}
	}
}

struct GCMouseScrollAccumulator {
	private var accumulatedX: Float = 0
	private var accumulatedY: Float = 0

	mutating func consume(
		axis: GCMouseScrollAxis,
		rawValue: Float,
		sensitivity: Float,
		naturalScrolling: Bool
	) -> ScrollWheel {
		let delta = GCMouseScrollMapper.adjustedDelta(
			axis: axis,
			rawValue: rawValue,
			naturalScrolling: naturalScrolling
		)
		return accumulate(deltaX: delta.x * sensitivity, deltaY: delta.y * sensitivity)
	}

	mutating func reset() {
		accumulatedX = 0
		accumulatedY = 0
	}

	private mutating func accumulate(deltaX: Float, deltaY: Float) -> ScrollWheel {
		accumulatedX += deltaX
		accumulatedY += deltaY
		let wheel = ScrollWheel(x: Int32(accumulatedX), y: Int32(accumulatedY))
		accumulatedX -= Float(wheel.x)
		accumulatedY -= Float(wheel.y)
		return wheel
	}
}

enum ScrollWheelMapper {
	private static let wheelDivisor: Float = 20.0

	static func wheelScale(sensitivity: Float, naturalScrolling: Bool) -> Float {
		let direction: Float = naturalScrolling ? -1.0 : 1.0
		return sensitivity * direction / wheelDivisor
	}
}

class GamepadController {

    private let maximumControllerCount: Int = 1
    private(set) var controllers = Set<GCController>()
	private(set) var mice = Set<GCMouse>()
	private var mouseScrollAccumulator = GCMouseScrollAccumulator()
    // private var panRecognizer: UIPanGestureRecognizer!
    weak var delegate: InputManagerDelegate?
	var hasMouseScrollSource: Bool { !mice.isEmpty }

    public func viewDidLoad() {

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.didConnectController),
                                               name: NSNotification.Name.GCControllerDidConnect,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.didDisconnectController),
                                               name: NSNotification.Name.GCControllerDidDisconnect,
                                               object: nil)

		NotificationCenter.default.addObserver(self,
											   selector: #selector(self.didMouseConnectController),
											   name: NSNotification.Name.GCMouseDidConnect,
											   object: nil)
		NotificationCenter.default.addObserver(self,
											   selector: #selector(self.didMouseDisconnectController),
											   name: NSNotification.Name.GCMouseDidDisconnect,
											   object: nil)

        GCController.startWirelessControllerDiscovery {}
		self.registerControllerHandler()
		self.registerMouseHandler()

    }

    func registerControllerHandler() {
		for controller in GCController.controllers() {
			controllers.insert(controller)
			if controllers.count > 1 { break }

			delegate?.inputManager(self, didConnect: controller)

			controller.extendedGamepad?.dpad.left.pressedChangedHandler =      { [weak self] (_, _, pressed) in self?.buttonChangedHandler(GAMEPAD_BUTTON_DPAD_LEFT, pressed) }
			controller.extendedGamepad?.dpad.right.pressedChangedHandler =     { [weak self] (_, _, pressed) in self?.buttonChangedHandler(GAMEPAD_BUTTON_DPAD_RIGHT, pressed) }
			controller.extendedGamepad?.dpad.up.pressedChangedHandler =        { [weak self] (_, _, pressed) in self?.buttonChangedHandler(GAMEPAD_BUTTON_DPAD_UP, pressed) }
			controller.extendedGamepad?.dpad.down.pressedChangedHandler =      { [weak self] (_, _, pressed) in self?.buttonChangedHandler(GAMEPAD_BUTTON_DPAD_DOWN, pressed) }

			// buttonA is labeled "X" (blue) on PS4 controller
			controller.extendedGamepad?.buttonA.pressedChangedHandler =        { [weak self] (_, _, pressed) in self?.buttonChangedHandler(GAMEPAD_BUTTON_A, pressed) }
			// buttonB is labeled "circle" (red) on PS4 controller
			controller.extendedGamepad?.buttonB.pressedChangedHandler =        { [weak self] (_, _, pressed) in self?.buttonChangedHandler(GAMEPAD_BUTTON_B, pressed) }
			// buttonX is labeled "square" (pink) on PS4 controller
			controller.extendedGamepad?.buttonX.pressedChangedHandler =        { [weak self] (_, _, pressed) in self?.buttonChangedHandler(GAMEPAD_BUTTON_X, pressed) }
			// buttonY is labeled "triangle" (green) on PS4 controller
			controller.extendedGamepad?.buttonY.pressedChangedHandler =        { [weak self] (_, _, pressed) in self?.buttonChangedHandler(GAMEPAD_BUTTON_Y, pressed) }

			// buttonOptions is labeled "SHARE" on PS4 controller
			controller.extendedGamepad?.buttonOptions?.pressedChangedHandler = { [weak self] (_, _, pressed) in self?.buttonChangedHandler(GAMEPAD_BUTTON_BACK, pressed) }
			// buttonMenu is labeled "OPTIONS" on PS4 controller
			controller.extendedGamepad?.buttonMenu.pressedChangedHandler =     { [weak self] (_, _, pressed) in self?.buttonChangedHandler(GAMEPAD_BUTTON_START, pressed) }

			controller.extendedGamepad?.leftShoulder.pressedChangedHandler =   { [weak self] (_, _, pressed) in self?.buttonChangedHandler(GAMEPAD_BUTTON_LSHOULDER, pressed) }
			controller.extendedGamepad?.rightShoulder.pressedChangedHandler =  { [weak self] (_, _, pressed) in self?.buttonChangedHandler(GAMEPAD_BUTTON_RSHOULDER, pressed) }

			// controller.extendedGamepad?.leftTrigger.PressedChangedHandler =    { (button, value, pressed) in self.triggerButtonChangedHandler(GAMEPAD_AXIS_TRIGGERL, pressed) }
			controller.extendedGamepad?.leftTrigger.valueChangedHandler =      { [weak self] (_, value, pressed) in self?.triggerChangedHandler(GAMEPAD_AXIS_TRIGGERL, value, pressed) }
			// controller.extendedGamepad?.rightTrigger.pressedChangedHandler =   { (button, value, pressed) in self.triggerButtonChangedHandler(GAMEPAD_AXIS_TRIGGERR, pressed) }
			controller.extendedGamepad?.rightTrigger.valueChangedHandler =     { [weak self] (_, value, pressed) in self?.triggerChangedHandler(GAMEPAD_AXIS_TRIGGERR, value, pressed) }

			controller.extendedGamepad?.leftThumbstick.valueChangedHandler =   { [weak self] (_, xvalue, yvalue) in self?.thumbLstickChangedHandler(xvalue, yvalue) }
			controller.extendedGamepad?.rightThumbstick.valueChangedHandler =  { [weak self] (_, xvalue, yvalue) in self?.thumbRstickChangedHandler(xvalue, yvalue) }

			controller.extendedGamepad?.leftThumbstickButton?.pressedChangedHandler =  { [weak self] (_, _, pressed) in self?.buttonChangedHandler(GAMEPAD_BUTTON_LSTICK, pressed) }
			controller.extendedGamepad?.rightThumbstickButton?.pressedChangedHandler = { [weak self] (_, _, pressed) in self?.buttonChangedHandler(GAMEPAD_BUTTON_RSTICK, pressed) }
		}

	}

	func registerMouseHandler() {
		for mouse in GCMouse.mice() {
			guard let mouseInput = mouse.mouseInput else { continue }
			mice.insert(mouse)
			mouseInput.leftButton.pressedChangedHandler = {(_: GCControllerButtonInput, _: Float, pressed: Bool) in
				guard ParsecBackgroundManager.shared.hasActiveConnection else { return }
				CParsec.sendMouseClickMessage(MOUSE_L, pressed)
				}
			mouseInput.rightButton?.pressedChangedHandler = {(_: GCControllerButtonInput, _: Float, pressed: Bool) in
				// pointer-lock toggles on the connect/disconnect view swap can synthesize a button edge
				// with no real input — dont forward it unless a session is actually live
				guard ParsecBackgroundManager.shared.hasActiveConnection else { return }
				CParsec.sendMouseClickMessage(MOUSE_R, pressed)
				}
			mouseInput.middleButton?.pressedChangedHandler = {(_: GCControllerButtonInput, _: Float, pressed: Bool) in
				guard ParsecBackgroundManager.shared.hasActiveConnection else { return }
				CParsec.sendMouseClickMessage(MOUSE_MIDDLE, pressed)
				}
			mouseInput.mouseMovedHandler={(_: GCMouseInput, v: Float, v2: Float) in
				CParsec.sendMouseDelta(Int32(v/1.25 * Float(SettingsHandler.mouseSensitivity)), Int32(-v2/1.25 * Float(SettingsHandler.mouseSensitivity)))
				}
			mouseInput.scroll.yAxis.valueChangedHandler = {[weak self] (_: GCControllerAxisInput, value: Float) in
				self?.sendMouseScroll(axis: .y, rawValue: value)
			}
			mouseInput.scroll.xAxis.valueChangedHandler = {[weak self] (_: GCControllerAxisInput, value: Float) in
				self?.sendMouseScroll(axis: .x, rawValue: value)
			}
		}
	}

	private func sendMouseScroll(axis: GCMouseScrollAxis, rawValue: Float) {
		let wheel = mouseScrollAccumulator.consume(
			axis: axis,
			rawValue: rawValue,
			sensitivity: Float(SettingsHandler.scrollSensitivity),
			naturalScrolling: SettingsHandler.naturalScrolling
		)
		if wheel.x != 0 || wheel.y != 0 {
			CParsec.sendWheelMsg(x: wheel.x, y: wheel.y)
		}
	}

	@objc func didMouseConnectController(_ notification: Notification) {
		self.registerMouseHandler()
	}

	@objc func didMouseDisconnectController(_ notification: Notification) {
		guard let mouse = notification.object as? GCMouse else { return }
		mice.remove(mouse)
		if mice.isEmpty {
			mouseScrollAccumulator.reset()
		}
	}

    @objc func didConnectController(_ notification: Notification) {

        // guard controllers.count < maximumControllerCount else { return }
        // let controller = notification.object as! GCController
        self.registerControllerHandler()
    }

    @objc func didDisconnectController(_ notification: Notification) {

        guard let controller = notification.object as? GCController else { return }
        controllers.remove(controller)

        delegate?.inputManager(self, didDisconnect: controller)
		CParsec.sendGameControllerUnplugMessage(controllerId: 1)
    }

	func ButtonFloatToParsecInt(_ value: Float) -> Int16 {
	    let newval: Float = (65535.0*value-1.0)/2.0
		return Int16(newval)
	}

    func buttonChangedHandler(_ button: ParsecGamepadButton, _ pressed: Bool) {
        CParsec.sendGameControllerButtonMessage(controllerId: 1, button, pressed: pressed)
    }

	// func triggerButtonChangedHandler(_ button: ParsecGamepadAxis, _ pressed: Bool) {
        // CParsec.sendGameControllerTriggerButtonMessage(controllerId:1, button, pressed)
    // }

    func triggerChangedHandler(_ button: ParsecGamepadAxis, _ value: Float, _ pressed: Bool) {
        CParsec.sendGameControllerAxisMessage(controllerId: 1, button, ButtonFloatToParsecInt(value))
    }

    func thumbLstickChangedHandler(_ xvalue: Float, _ yvalue: Float) {
        CParsec.sendGameControllerAxisMessage(controllerId: 1, GAMEPAD_AXIS_LX, ButtonFloatToParsecInt(xvalue))
		CParsec.sendGameControllerAxisMessage(controllerId: 1, GAMEPAD_AXIS_LY, ButtonFloatToParsecInt(-yvalue))

    }

	func thumbRstickChangedHandler(_ xvalue: Float, _ yvalue: Float) {
        CParsec.sendGameControllerAxisMessage(controllerId: 1, GAMEPAD_AXIS_RX, ButtonFloatToParsecInt(xvalue))
		CParsec.sendGameControllerAxisMessage(controllerId: 1, GAMEPAD_AXIS_RY, ButtonFloatToParsecInt(-yvalue))
    }

}

protocol InputManagerDelegate: AnyObject {
    func inputManager(_ manager: GamepadController, didConnect controller: GCController)
    func inputManager(_ manager: GamepadController, didDisconnect controller: GCController)
}
