import UIKit
import GameController
import ParsecSDK

class GamepadViewController: UIViewController {
    
    private let maximumControllerCount: Int = 1
    private(set) var controllers = Set<GCController>()
    //private var panRecognizer: UIPanGestureRecognizer!
    weak var delegate: InputManagerDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.didConnectController),
                                               name: NSNotification.Name.GCControllerDidConnect,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.didDisconnectController),
                                               name: NSNotification.Name.GCControllerDidDisconnect,
                                               object: nil)
	    
        GCController.startWirelessControllerDiscovery {}
		self.registerControllerHandler()
    }
    
    func registerControllerHandler()
	{
	    for controller in GCController.controllers() {
            controllers.insert(controller)
            if controllers.count > 1 { break }
			    			
            delegate?.inputManager(self, didConnect: controller)
            
            controller.extendedGamepad?.dpad.left.pressedChangedHandler =      { (button, value, pressed) in self.buttonChangedHandler(GAMEPAD_BUTTON_DPAD_LEFT, pressed) }
            controller.extendedGamepad?.dpad.right.pressedChangedHandler =     { (button, value, pressed) in self.buttonChangedHandler(GAMEPAD_BUTTON_DPAD_RIGHT, pressed) }
            controller.extendedGamepad?.dpad.up.pressedChangedHandler =        { (button, value, pressed) in self.buttonChangedHandler(GAMEPAD_BUTTON_DPAD_UP, pressed) }
            controller.extendedGamepad?.dpad.down.pressedChangedHandler =      { (button, value, pressed) in self.buttonChangedHandler(GAMEPAD_BUTTON_DPAD_DOWN, pressed) }
            
            // buttonA is labeled "X" (blue) on PS4 controller
            controller.extendedGamepad?.buttonA.pressedChangedHandler =        { (button, value, pressed) in self.buttonChangedHandler(GAMEPAD_BUTTON_A, pressed) }
            // buttonB is labeled "circle" (red) on PS4 controller
            controller.extendedGamepad?.buttonB.pressedChangedHandler =        { (button, value, pressed) in self.buttonChangedHandler(GAMEPAD_BUTTON_B, pressed) }
            // buttonX is labeled "square" (pink) on PS4 controller
            controller.extendedGamepad?.buttonX.pressedChangedHandler =        { (button, value, pressed) in self.buttonChangedHandler(GAMEPAD_BUTTON_X, pressed) }
            // buttonY is labeled "triangle" (green) on PS4 controller
            controller.extendedGamepad?.buttonY.pressedChangedHandler =        { (button, value, pressed) in self.buttonChangedHandler(GAMEPAD_BUTTON_Y, pressed) }
            
            // buttonOptions is labeled "SHARE" on PS4 controller
            controller.extendedGamepad?.buttonOptions?.pressedChangedHandler = { (button, value, pressed) in self.buttonChangedHandler(GAMEPAD_BUTTON_BACK, pressed) }
            // buttonMenu is labeled "OPTIONS" on PS4 controller
            controller.extendedGamepad?.buttonMenu.pressedChangedHandler =     { (button, value, pressed) in self.buttonChangedHandler(GAMEPAD_BUTTON_START, pressed) }
            
            controller.extendedGamepad?.leftShoulder.pressedChangedHandler =   { (button, value, pressed) in self.buttonChangedHandler(GAMEPAD_BUTTON_LSHOULDER, pressed) }
            controller.extendedGamepad?.rightShoulder.pressedChangedHandler =  { (button, value, pressed) in self.buttonChangedHandler(GAMEPAD_BUTTON_RSHOULDER, pressed) }
            
            //controller.extendedGamepad?.leftTrigger.PressedChangedHandler =    { (button, value, pressed) in self.triggerButtonChangedHandler(GAMEPAD_AXIS_TRIGGERL, pressed) }
            controller.extendedGamepad?.leftTrigger.valueChangedHandler =      { (button, value, pressed) in self.triggerChangedHandler(GAMEPAD_AXIS_TRIGGERL, value, pressed) }
            //controller.extendedGamepad?.rightTrigger.pressedChangedHandler =   { (button, value, pressed) in self.triggerButtonChangedHandler(GAMEPAD_AXIS_TRIGGERR, pressed) }
            controller.extendedGamepad?.rightTrigger.valueChangedHandler =     { (button, value, pressed) in self.triggerChangedHandler(GAMEPAD_AXIS_TRIGGERR, value, pressed) }
            
            controller.extendedGamepad?.leftThumbstick.valueChangedHandler =   { (button, xvalue, yvalue) in self.thumbLstickChangedHandler(xvalue, yvalue) }
            controller.extendedGamepad?.rightThumbstick.valueChangedHandler =  { (button, xvalue, yvalue) in self.thumbRstickChangedHandler(xvalue, yvalue) }
            
            controller.extendedGamepad?.leftThumbstickButton?.pressedChangedHandler =  { (button, value, pressed) in self.buttonChangedHandler(GAMEPAD_BUTTON_LSTICK, pressed) }
            controller.extendedGamepad?.rightThumbstickButton?.pressedChangedHandler = { (button, value, pressed) in self.buttonChangedHandler(GAMEPAD_BUTTON_RSTICK, pressed) }
		}
	}
	
    @objc func didConnectController(_ notification: Notification) {
        
        //guard controllers.count < maximumControllerCount else { return }
        //let controller = notification.object as! GCController
        self.registerControllerHandler()
    }
	
    @objc func didDisconnectController(_ notification: Notification) {
        
        let controller = notification.object as! GCController
        controllers.remove(controller)
        
        delegate?.inputManager(self, didDisconnect: controller)
		CParsec.sendGameControllerUnplugMessage(controllerId:1)
    }
    
	func ButtonFloatToParsecInt(_ value: Float) -> Int16
	{
	    let newval: Float = (65535.0*value-1.0)/2.0
		return Int16(newval) 
	}
    
    func buttonChangedHandler(_ button: ParsecGamepadButton, _ pressed: Bool) {
        CParsec.sendGameControllerButtonMessage(controllerId:1, button, pressed:pressed)
    }
    
	//func triggerButtonChangedHandler(_ button: ParsecGamepadAxis, _ pressed: Bool) {
        //CParsec.sendGameControllerTriggerButtonMessage(controllerId:1, button, pressed)
    //}
	
    func triggerChangedHandler(_ button:ParsecGamepadAxis, _ value: Float, _ pressed: Bool) {
        CParsec.sendGameControllerAxisMessage(controllerId:1, button, ButtonFloatToParsecInt(value))
    }
    
	
    func thumbLstickChangedHandler(_ xvalue: Float, _ yvalue: Float) {
        CParsec.sendGameControllerAxisMessage(controllerId:1, GAMEPAD_AXIS_LX, ButtonFloatToParsecInt(xvalue))
		CParsec.sendGameControllerAxisMessage(controllerId:1, GAMEPAD_AXIS_LY, ButtonFloatToParsecInt(-yvalue))
		
    }
	
	func thumbRstickChangedHandler(_ xvalue: Float, _ yvalue: Float) {
        CParsec.sendGameControllerAxisMessage(controllerId:1, GAMEPAD_AXIS_RX, ButtonFloatToParsecInt(xvalue))
		CParsec.sendGameControllerAxisMessage(controllerId:1, GAMEPAD_AXIS_RY, ButtonFloatToParsecInt(-yvalue))
    }
    
}

protocol InputManagerDelegate: AnyObject {
    func inputManager(_ manager: GamepadViewController, didConnect controller: GCController)
    func inputManager(_ manager: GamepadViewController, didDisconnect controller: GCController)
}
