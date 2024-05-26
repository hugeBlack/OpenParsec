import ParsecSDK
import SwiftUI
import CoreGraphics
import GLKit

struct MouseInfo {
	var pngCursor:Bool = false
	var mouseX:Int32 = 1
	var mouseY:Int32 = 1
	var cursorWidth = 0
	var cursorHeight = 0
	var cursorHotX = 0
	var cursorHotY = 0
	var cursorImg: CGImage?
	var cursorHidden = false
	var mousePositionRelative = false
}

protocol ParsecService {
	var clientWidth: Float { get }
	var clientHeight: Float { get }
	var hostWidth: Float { get }
	var hostHeight: Float { get }
	var mouseInfo: MouseInfo { get }
	
	func connect(_ peerID: String) -> ParsecStatus
	func disconnect()
	func getStatus() -> ParsecStatus
	func getStatusEx(_ pcs: inout ParsecClientStatus) -> ParsecStatus
	func setFrame(_ width: CGFloat, _ height: CGFloat, _ scale: CGFloat)
	func renderGLFrame(timeout: UInt32)
	func setMuted(_ muted: Bool)
	func applyConfig()
	func sendMouseMessage(_ button: ParsecMouseButton, _ x: Int32, _ y: Int32, _ pressed: Bool)
	func sendMouseClickMessage(_ button: ParsecMouseButton, _ pressed: Bool)
	func sendMouseDelta(_ dx: Int32, _ dy: Int32)
	func sendMousePosition(_ x: Int32, _ y: Int32)
	func sendKeyboardMessage(event: KeyBoardKeyEvent)
	func sendGameControllerButtonMessage(controllerId: UInt32, _ button: ParsecGamepadButton, pressed: Bool)
	func sendGameControllerAxisMessage(controllerId: UInt32, _ button: ParsecGamepadAxis, _ value: Int16)
	func sendGameControllerUnplugMessage(controllerId: UInt32)
	func sendWheelMsg(x: Int32, y: Int32)
}

class CParsec
{
	public static var hostWidth:Float {
		return parsecImpl.hostWidth
	}
	public static var hostHeight:Float {
		return parsecImpl.hostHeight
	}
	
	public static var clientWidth:Float {
		return parsecImpl.clientWidth
	}
	public static var clientHeight:Float {
		return parsecImpl.clientHeight
	}

	public static var mouseInfo: MouseInfo {
		return parsecImpl.mouseInfo
	}
	
	

	static var parsecImpl: ParsecService!

	static func initialize()
	{
		switch SettingsHandler.streamProtocol {
		case .stcp:
			parsecImpl = ParsecWeb()
			break
		case .bud:
			parsecImpl = ParsecSDKBridge()
			break
		}
		
	}

	static func destroy()
	{
		
	}

	static func connect(_ peerID:String) -> ParsecStatus
	{
		parsecImpl.connect(peerID)
	}

	static func disconnect()
	{
		parsecImpl.disconnect()
	}

	static func getStatus() -> ParsecStatus
	{
		return parsecImpl.getStatus()
	}

    static func getStatusEx(_ pcs:inout ParsecClientStatus) -> ParsecStatus
	{
		return parsecImpl.getStatusEx(&pcs)
	}
	
	static func setFrame(_ width:CGFloat, _ height:CGFloat, _ scale:CGFloat )
	{
		parsecImpl.setFrame(width, height, scale)
	}

	static func renderGLFrame(timeout:UInt32 = 16) // timeout in ms, 16 == 60 FPS, 8 == 120 FPS, etc.
	{
		parsecImpl.renderGLFrame(timeout: timeout)
	}
	
	static func setMuted(_ muted:Bool)
	{
		parsecImpl.setMuted(muted)
	}
	
	static func applyConfig()
	{
		parsecImpl.applyConfig()
	}

	static func sendMouseMessage(_ button:ParsecMouseButton, _ x:Int32, _ y:Int32, _ pressed:Bool)
	{
		parsecImpl.sendMouseMessage(button, x, y, pressed)
	}
	
	static func sendMouseClickMessage(_ button:ParsecMouseButton, _ pressed:Bool) {
		parsecImpl.sendMouseClickMessage(button, pressed)
	}
	
	static func sendMouseDelta(_ dx: Int32, _ dy: Int32) {
		parsecImpl.sendMouseDelta(dx, dy)
	}

	static func sendMousePosition(_ x:Int32, _ y:Int32)
	{
		parsecImpl.sendMousePosition(x, y)
	}

	static func sendKeyboardMessage(event:KeyBoardKeyEvent)
	{
		parsecImpl.sendKeyboardMessage(event: event)
	}
	
	static func sendGameControllerButtonMessage(controllerId:UInt32, _ button:ParsecGamepadButton, pressed:Bool)
	{
		parsecImpl.sendGameControllerButtonMessage(controllerId: controllerId, button, pressed: pressed)
	}
	
	
	static func sendGameControllerAxisMessage(controllerId:UInt32, _ button:ParsecGamepadAxis, _ value: Int16)
	{
		parsecImpl.sendGameControllerAxisMessage(controllerId: controllerId, button, value)
	}
	
	static func sendGameControllerUnplugMessage(controllerId:UInt32)
	{
		parsecImpl.sendGameControllerUnplugMessage(controllerId: controllerId)
	}
	
	static func sendWheelMsg(x: Int32, y: Int32) {
		parsecImpl.sendWheelMsg(x: x, y: y)
	}
	
	static func getImpl() -> ParsecService {
		return parsecImpl
	}
}
