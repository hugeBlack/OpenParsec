import ParsecSDK
import MetalKit
import UIKit

enum RendererType:Int
{
	case opengl
    case metal
}

enum DecoderPref:Int
{
    case h264
    case h265
}

enum CursorMode:Int
{
    case touchpad
    case direct
}

class CParsec
{
	private static var _initted:Bool = false

	private static var _parsec:OpaquePointer!
	private static var _audio:OpaquePointer!
	private static let _audioPtr:UnsafeRawPointer = UnsafeRawPointer(_audio)

	public static var hostWidth:Float = 0
	public static var hostHeight:Float = 0
	
	public static var netProtocol:Int32 = 1
	public static var mediaContainer:Int32 = 0
	public static var pngCursor:Bool = false

	static let PARSEC_VER:UInt32 = UInt32((PARSEC_VER_MAJOR << 16) | PARSEC_VER_MINOR)

	static func initialize()
	{
		if _initted { return }

		print("Parsec SDK Version: " + String(CParsec.PARSEC_VER))

		ParsecSetLogCallback(
		{ (level, msg, opaque) in
			print("[\(level == LOG_DEBUG ? "D" : "I")] \(String(cString:msg!))")
		}, nil)

		audio_init(&_audio)

		ParsecInit(PARSEC_VER, nil, nil, &_parsec)

		_initted = true
	}

	static func destroy()
	{
		if !_initted { return }

		ParsecDestroy(_parsec)
		audio_destroy(&_audio)
	}

	static func connect(_ peerID:String) -> ParsecStatus
	{
		var parsecClientCfg = ParsecClientConfig()
		parsecClientCfg.video.0.decoderIndex = 1
		parsecClientCfg.video.0.resolutionX = 0
		parsecClientCfg.video.0.resolutionY = 0
		parsecClientCfg.video.0.decoderCompatibility = false
		parsecClientCfg.video.0.decoderH265 = true
		
		parsecClientCfg.video.1.decoderIndex = 1
		parsecClientCfg.video.1.resolutionX = 0
		parsecClientCfg.video.1.resolutionY = 0
		parsecClientCfg.video.1.decoderCompatibility = false
		parsecClientCfg.video.1.decoderH265 = true
		
	    parsecClientCfg.mediaContainer = 0
		parsecClientCfg.protocol = 1
		//parsecClientCfg.secret = ""
		parsecClientCfg.pngCursor = false
		return ParsecClientConnect(_parsec, &parsecClientCfg, NetworkHandler.clinfo?.session_id, peerID)
	}

	static func disconnect()
	{
        audio_clear(&_audio)
		ParsecClientDisconnect(_parsec)
	}

	static func getStatus() -> ParsecStatus
	{
		return ParsecClientGetStatus(_parsec, nil)
	}

    static func getStatusEx(_ pcs:inout ParsecClientStatus) -> ParsecStatus
	{
		return ParsecClientGetStatus(_parsec, &pcs)
	}
	
	static func setFrame(_ width:CGFloat, _ height:CGFloat, _ scale:CGFloat)
	{
		ParsecClientSetDimensions(_parsec, UInt8(DEFAULT_STREAM), UInt32(width), UInt32(height), Float(scale))

		hostWidth = Float(width)
		hostHeight = Float(height)
	}

	static func renderGLFrame(timeout:UInt32 = 16) // timeout in ms, 16 == 60 FPS, 8 == 120 FPS, etc.
	{
		ParsecClientGLRenderFrame(_parsec, UInt8(DEFAULT_STREAM), nil, nil, timeout)
	}
	
	/*static func renderMetalFrame(_ queue:inout MTLCommandQueue, _ texturePtr:UnsafeMutablePointer<UnsafeMutableRawPointer?>, timeout:UInt32 = 16) // timeout in ms, 16 == 60 FPS, 8 == 120 FPS, etc.
	{
		ParsecClientMetalRenderFrame(_parsec, UInt8(DEFAULT_STREAM), &queue, texturePtr, nil, nil, timeout)
	}*/

	static func pollAudio(timeout:UInt32 = 16) // timeout in ms, 16 == 60 FPS, 8 == 120 FPS, etc.
	{
		ParsecClientPollAudio(_parsec, audio_cb, timeout, _audioPtr)
	}

	static func setMuted(_ muted:Bool)
	{
		audio_mute(muted, _audioPtr)
	}
	
	static func applyConfig()
	{
		var parsecClientCfg = ParsecClientConfig()
		
		parsecClientCfg.video.0.decoderIndex = 1
		parsecClientCfg.video.0.resolutionX = 0
		parsecClientCfg.video.0.resolutionY = 0
		parsecClientCfg.video.0.decoderCompatibility = false
		parsecClientCfg.video.0.decoderH265 = SettingsHandler.decoder == .h265
		
		parsecClientCfg.video.1.decoderIndex = 1
		parsecClientCfg.video.1.resolutionX = 0
		parsecClientCfg.video.1.resolutionY = 0
		parsecClientCfg.video.1.decoderCompatibility = false
		parsecClientCfg.video.1.decoderH265 = SettingsHandler.decoder == .h265
		
	    parsecClientCfg.mediaContainer = mediaContainer
		parsecClientCfg.protocol = netProtocol
		//parsecClientCfg.secret = ""
		parsecClientCfg.pngCursor = pngCursor
		
		ParsecClientSetConfig(_parsec, &parsecClientCfg);
	}

	static func sendMouseMessage(_ button:ParsecMouseButton, _ x:Int32, _ y:Int32, _ pressed:Bool)
	{
		// Send the mouse position
		sendMousePosition(x, y)

		// Send the mouse button state
		var buttonMessage = ParsecMessage()
		buttonMessage.type = MESSAGE_MOUSE_BUTTON
		buttonMessage.mouseButton.button = button
		buttonMessage.mouseButton.pressed = pressed
		ParsecClientSendMessage(_parsec, &buttonMessage)
	}

	static func sendMousePosition(_ x:Int32, _ y:Int32)
	{
		var motionMessage = ParsecMessage()
		motionMessage.type = MESSAGE_MOUSE_MOTION
		motionMessage.mouseMotion.x = x
		motionMessage.mouseMotion.y = y
		ParsecClientSendMessage(_parsec, &motionMessage)
	}

	static func sendKeyboardMessage(sender:UIKeyCommand)
	{
		var key = sender.input ?? ""

		switch sender.modifierFlags.rawValue
		{
			case 131072:
				key = "SHIFT"
				break
			case 262144:
				key = "CONTROL"
				break

			default:
				break
		}

		print("Keyboard Message: \(key)")
		print("KeyboardViewController keyboard modifier info \(sender.modifierFlags.rawValue)")

		var keyboardMessagePress = ParsecMessage()
		keyboardMessagePress.type = MESSAGE_KEYBOARD
		keyboardMessagePress.keyboard.code = parsecKeyCodeTranslator(key)
		keyboardMessagePress.keyboard.pressed = true
		ParsecClientSendMessage(_parsec, &keyboardMessagePress)

		var keyboardMessageRelease = ParsecMessage()
		keyboardMessageRelease.type = MESSAGE_KEYBOARD
		keyboardMessageRelease.keyboard.code = parsecKeyCodeTranslator(key)
		keyboardMessageRelease.keyboard.pressed = false
		ParsecClientSendMessage(_parsec, &keyboardMessageRelease)
	}

	static func parsecKeyCodeTranslator(_ str:String) -> ParsecKeycode
	{
		switch str
		{
			case "A": return ParsecKeycode(4)
			case "B": return ParsecKeycode(5)
			case "C": return ParsecKeycode(6)
			case "D": return ParsecKeycode(7)
			case "E": return ParsecKeycode(8)
			case "F": return ParsecKeycode(9)
			case "G": return ParsecKeycode(10)
			case "H": return ParsecKeycode(11)
			case "I": return ParsecKeycode(12)
			case "J": return ParsecKeycode(13)
			case "K": return ParsecKeycode(14)
			case "L": return ParsecKeycode(15)
			case "M": return ParsecKeycode(16)
			case "N": return ParsecKeycode(17)
			case "O": return ParsecKeycode(18)
			case "P": return ParsecKeycode(19)
			case "Q": return ParsecKeycode(20)
			case "R": return ParsecKeycode(21)
			case "S": return ParsecKeycode(22)
			case "T": return ParsecKeycode(23)
			case "U": return ParsecKeycode(24)
			case "V": return ParsecKeycode(25)
			case "W": return ParsecKeycode(26)
			case "X": return ParsecKeycode(27)
			case "Y": return ParsecKeycode(28)
			case "Z": return ParsecKeycode(29)
			case "1": return ParsecKeycode(30)
			case "2": return ParsecKeycode(31)
			case "3": return ParsecKeycode(32)
			case "4": return ParsecKeycode(33)
			case "5": return ParsecKeycode(34)
			case "6": return ParsecKeycode(35)
			case "7": return ParsecKeycode(36)
			case "8": return ParsecKeycode(37)
			case "9": return ParsecKeycode(38)
			case "0": return ParsecKeycode(39)
			case "ENTER": return ParsecKeycode(40)
			case "UIKeyInputEscape": return ParsecKeycode(41) // ESCAPE with re-factored
			case "BACKSPACE": return ParsecKeycode(42)
			case "TAB": return ParsecKeycode(43)
			case "SPACE": return ParsecKeycode(44)
			case "MINUS": return ParsecKeycode(45)
			case "EQUALS": return ParsecKeycode(46)
			case "LBRACKET": return ParsecKeycode(47)
			case "RBRACKET": return ParsecKeycode(48)
			case "BACKSLASH": return ParsecKeycode(49)
			case "SEMICOLON": return ParsecKeycode(51)
			case "APOSTROPHE": return ParsecKeycode(52)
			case "BACKTICK": return ParsecKeycode(53)
			case "COMMA": return ParsecKeycode(54)
			case "PERIOD": return ParsecKeycode(55)
			case "SLASH": return ParsecKeycode(56)
			case "CAPSLOCK": return ParsecKeycode(57)
			case "F1": return ParsecKeycode(58)
			case "F2": return ParsecKeycode(59)
			case "F3": return ParsecKeycode(60)
			case "F4": return ParsecKeycode(61)
			case "F5": return ParsecKeycode(62)
			case "F6": return ParsecKeycode(63)
			case "F7": return ParsecKeycode(64)
			case "F8": return ParsecKeycode(65)
			case "F9": return ParsecKeycode(66)
			case "F10": return ParsecKeycode(67)
			case "F11": return ParsecKeycode(68)
			case "F12": return ParsecKeycode(69)
			case "PRINTSCREEN": return ParsecKeycode(70)
			case "SCROLLLOCK": return ParsecKeycode(71)
			case "PAUSE": return ParsecKeycode(72)
			case "INSERT": return ParsecKeycode(73)
			case "HOME": return ParsecKeycode(74)
			case "PAGEUP": return ParsecKeycode(75)
			case "DELETE": return ParsecKeycode(76)
			case "END": return ParsecKeycode(77)
			case "PAGEDOWN": return ParsecKeycode(78)
			case "RIGHT": return ParsecKeycode(79)
			case "LEFT": return ParsecKeycode(80)
			case "DOWN": return ParsecKeycode(81)
			case "UP": return ParsecKeycode(82)
			case "NUMLOCK": return ParsecKeycode(83)
			case "KP_DIVIDE": return ParsecKeycode(84)
			case "KP_MULTIPLY": return ParsecKeycode(85)
			case "KP_MINUS": return ParsecKeycode(86)
			case "KP_PLUS": return ParsecKeycode(87)
			case "KP_ENTER": return ParsecKeycode(88)
			case "KP_1": return ParsecKeycode(89)
			case "KP_2": return ParsecKeycode(90)
			case "KP_3": return ParsecKeycode(91)
			case "KP_4": return ParsecKeycode(92)
			case "KP_5": return ParsecKeycode(93)
			case "KP_6": return ParsecKeycode(94)
			case "KP_7": return ParsecKeycode(95)
			case "KP_8": return ParsecKeycode(96)
			case "KP_9": return ParsecKeycode(97)
			case "KP_0": return ParsecKeycode(98)
			case "KP_PERIOD": return ParsecKeycode(99)
			case "APPLICATION": return ParsecKeycode(101)
			case "F13": return ParsecKeycode(104)
			case "F14": return ParsecKeycode(105)
			case "F15": return ParsecKeycode(106)
			case "F16": return ParsecKeycode(107)
			case "F17": return ParsecKeycode(108)
			case "F18": return ParsecKeycode(109)
			case "F19": return ParsecKeycode(110)
			case "MENU": return ParsecKeycode(118)
			case "MUTE": return ParsecKeycode(127)
			case "VOLUMEUP": return ParsecKeycode(128)
			case "VOLUMEDOWN": return ParsecKeycode(129)
			case "CONTROL": return ParsecKeycode(224)
			case "SHIFT": return ParsecKeycode(225)
			case "LALT": return ParsecKeycode(226)
			case "LGUI": return ParsecKeycode(227)
			case "RCTRL": return ParsecKeycode(228)
			case "RSHIFT": return ParsecKeycode(229)
			case "RALT": return ParsecKeycode(230)
			case "RGUI": return ParsecKeycode(231)
			case "AUDIONEXT": return ParsecKeycode(258)
			case "AUDIOPREV": return ParsecKeycode(259)
			case "AUDIOSTOP": return ParsecKeycode(260)
			case "AUDIOPLAY": return ParsecKeycode(261)
			case "AUDIOMUTE": return ParsecKeycode(262)
			case "MEDIASELECT": return ParsecKeycode(263)

			default: return ParsecKeycode(UInt32(0))
		}
	}
	
	static func sendGameControllerButtonMessage(controllerId:UInt32, _ button:ParsecGamepadButton, pressed:Bool)
	{
		var pmsg = ParsecMessage()
		pmsg.type = MESSAGE_GAMEPAD_BUTTON
		pmsg.gamepadButton.id = controllerId
		pmsg.gamepadButton.button = button
		pmsg.gamepadButton.pressed = pressed
		ParsecClientSendMessage(_parsec, &pmsg)
	}
	
	/*static func sendGameControllerTriggerButtonMessage(controllerId:UInt32, _ button:ParsecGamepadAxis, pressed:Bool)
	{
	    var pmsg = ParsecMessage()
		pmsg.type = MESSAGE_GAMEPAD_AXIS
		pmsg.gamepadAxis.id = controllerId
		pmsg.gamepadAxis.button = button
		pmsg.gamepadAxis.pressed = pressed
		ParsecClientSendMessage(_parsec, &pmsg)
	}*/
	
	static func sendGameControllerAxisMessage(controllerId:UInt32, _ button:ParsecGamepadAxis, _ value: Int16)
	{
	    var pmsg = ParsecMessage()
		pmsg.type = MESSAGE_GAMEPAD_AXIS
		pmsg.gamepadAxis.id = controllerId
		pmsg.gamepadAxis.axis = button
		pmsg.gamepadAxis.value = value
		ParsecClientSendMessage(_parsec, &pmsg)
	}
	
	static func sendGameControllerUnplugMessage(controllerId:UInt32)
	{
	    var pmsg = ParsecMessage()
		pmsg.type = MESSAGE_GAMEPAD_UNPLUG;
		pmsg.gamepadUnplug.id = controllerId;
		ParsecClientSendMessage(_parsec, &pmsg)
	}
}
