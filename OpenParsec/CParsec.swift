import ParsecSDK
import SwiftUI
import CoreGraphics
import GLKit

enum ParsecResolution: String, CaseIterable, Hashable {
	case host = "Host Resolution"
	case client = "Client Resolution" // updated dynamically during connection
	case r3840x2160_16_9 = "3840x2160 (16:9)"
	case r3840x1600_21_9 = "3840x1600 (21:9)"
	case r3440x1440_21_9 = "3440x1440 (21:9)"
	case r2560x1600_16_10 = "2560x1600 (16:10)"
	case r2560x1440_16_9 = "2560x1440 (16:9)"
	case r2560x1080_21_9 = "2560x1080 (21:9)"
	case r1920x1200_16_10 = "1920x1200 (16:10)"
	case r1920x1080_16_9 = "1920x1080 (16:9)"
	case r1680x1050_16_10 = "1680x1050 (16:10)"
	case r1600x1200_4_3 = "1600x1200 (4:3)"
	case r1366x768_16_9 = "1366x768 (16:9)"
	case r1280x1024_5_4 = "1280x1024 (5:4)"
	case r1280x800_16_10 = "1280x800 (16:10)"
	case r1280x720_16_9 = "1280x720 (16:9)"
	case r1024x768_4_3 = "1024x768 (4:3)"

	private static var clientSize: (width: Int, height: Int) = (3480, 2160)

	var width: Int {
		switch self {
		case .host:
			return 0
		case .client:
			return ParsecResolution.clientSize.width
		case .r3840x2160_16_9:
			return 3840
		case .r3840x1600_21_9:
			return 3840
		case .r3440x1440_21_9:
			return 3440
		case .r2560x1600_16_10:
			return 2560
		case .r2560x1440_16_9:
			return 2560
		case .r2560x1080_21_9:
			return 2560
		case .r1920x1200_16_10:
			return 1920
		case .r1920x1080_16_9:
			return 1920
		case .r1680x1050_16_10:
			return 1680
		case .r1600x1200_4_3:
			return 1600
		case .r1366x768_16_9:
			return 1366
		case .r1280x1024_5_4:
			return 1280
		case .r1280x800_16_10:
			return 1280
		case .r1280x720_16_9:
			return 1280
		case .r1024x768_4_3:
			return 1024
		}
	}

	var height: Int {
		switch self {
		case .host:
			return 0
		case .client:
			return ParsecResolution.clientSize.height
		case .r3840x2160_16_9:
			return 2160
		case .r3840x1600_21_9:
			return 1600
		case .r3440x1440_21_9:
			return 1440
		case .r2560x1600_16_10:
			return 1600
		case .r2560x1440_16_9:
			return 1440
		case .r2560x1080_21_9:
			return 1080
		case .r1920x1200_16_10:
			return 1200
		case .r1920x1080_16_9:
			return 1080
		case .r1680x1050_16_10:
			return 1050
		case .r1600x1200_4_3:
			return 1200
		case .r1366x768_16_9:
			return 768
		case .r1280x1024_5_4:
			return 1024
		case .r1280x800_16_10:
			return 800
		case .r1280x720_16_9:
			return 720
		case .r1024x768_4_3:
			return 768
		}
	}

	var desc: String {
		return rawValue
	}

	static var resolutions: [ParsecResolution] {
		return Array(Self.allCases)
	}

	static var bitrates = [3, 5, 7, 10, 15, 20, 25, 30, 35, 40, 45, 50]

	static func updateClientResolution(width: Int, height: Int) {
		clientSize = (width, height)
	}
}


struct MouseInfo {
	var pngCursor: Bool = false
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
	func sendVirtualKeyboardInput(text: String)
	func sendVirtualKeyboardInput(text: String, isOn: Bool)
	func sendGameControllerButtonMessage(controllerId: UInt32, _ button: ParsecGamepadButton, pressed: Bool)
	func sendGameControllerAxisMessage(controllerId: UInt32, _ button: ParsecGamepadAxis, _ value: Int16)
	func sendGameControllerUnplugMessage(controllerId: UInt32)
	func sendWheelMsg(x: Int32, y: Int32)
	func sendUserData(type: ParsecUserDataType, message: Data)
	func updateHostVideoConfig()
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

	// Remember the last peer we connected to so callers like changeResolution
	// can disconnect + reconnect with new ParsecClientConfig (resolution can
	// only be changed via a fresh ParsecClientConnect — the in-session
	// setVideoConfig user-data event does not move resolution on the host).
	public static var lastConnectedPeerID: String?

	static func initialize()
	{
		parsecImpl = ParsecSDKBridge()
	}

	static func destroy()
	{

	}

	static func connect(_ peerID: String) -> ParsecStatus
	{
		lastConnectedPeerID = peerID
		return parsecImpl.connect(peerID)
	}

	static func disconnect()
	{
		// Clear the peer-ID memo on any disconnect path; changeResolution sets
		// it again right before calling connect(), so the reconnect dance is
		// unaffected — but a user-initiated disconnect (close stream button,
		// app background, etc.) should leave us with no stale peer.
		lastConnectedPeerID = nil
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
	
	static func setFrame(_ width:CGFloat, _ height:CGFloat, _ scale: CGFloat )
	{
		parsecImpl.setFrame(width, height, scale)
	}

	static func renderGLFrame(timeout: UInt32 = 16) // timeout in ms, 16 == 60 FPS, 8 == 120 FPS, etc.
	{
		parsecImpl.renderGLFrame(timeout: timeout)
	}
	
	static func setMuted(_ muted: Bool)
	{
		parsecImpl.setMuted(muted)
	}
	
	static func applyConfig()
	{
		parsecImpl.applyConfig()
	}
	
	static func updateHostVideoConfig() {
		parsecImpl.updateHostVideoConfig()
	}

	static func sendMouseMessage(_ button:ParsecMouseButton, _ x:Int32, _ y:Int32, _ pressed: Bool)
	{
		parsecImpl.sendMouseMessage(button, x, y, pressed)
	}
	
	static func sendMouseClickMessage(_ button:ParsecMouseButton, _ pressed: Bool) {
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
	
	static func sendVirtualKeyboardInput(text: String) {
		parsecImpl.sendVirtualKeyboardInput(text: text)
	}
	
	static func sendVirtualKeyboardInput(text: String, isOn: Bool) {
		parsecImpl.sendVirtualKeyboardInput(text: text, isOn: isOn)
	}
	
	static func sendGameControllerButtonMessage(controllerId: UInt32, _ button:ParsecGamepadButton, pressed: Bool)
	{
		parsecImpl.sendGameControllerButtonMessage(controllerId: controllerId, button, pressed: pressed)
	}
	
	
	static func sendGameControllerAxisMessage(controllerId: UInt32, _ button:ParsecGamepadAxis, _ value: Int16)
	{
		parsecImpl.sendGameControllerAxisMessage(controllerId: controllerId, button, value)
	}
	
	static func sendGameControllerUnplugMessage(controllerId: UInt32)
	{
		parsecImpl.sendGameControllerUnplugMessage(controllerId: controllerId)
	}
	
	static func sendWheelMsg(x: Int32, y: Int32) {
		parsecImpl.sendWheelMsg(x: x, y: y)
	}
	
	static func sendUserData(type: ParsecUserDataType, message: Data) {
		parsecImpl.sendUserData(type: type, message: message)
	}
	
	static func getImpl() -> ParsecService {
		return parsecImpl
	}
}
