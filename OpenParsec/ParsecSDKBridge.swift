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

enum ProtocolPref:Int
{
	case stcp
	case bud
}

enum CursorMode:Int
{
    case touchpad
    case direct
}

struct KeyBoardKeyEvent {
	var input: UIKey?
	var isPressBegin: Bool
}

struct RGBA {
	let R:UInt8
	let G:UInt8
	let B:UInt8
	let A:UInt8
}

class ParsecSDKBridge: ParsecService
{
	var hostWidth: Float = 1920
	
	var hostHeight: Float = 1080
	
	
	static let PARSEC_VER:UInt32 = UInt32((PARSEC_VER_MAJOR << 16) | PARSEC_VER_MINOR)
	
	private var _parsec:OpaquePointer!
	private var _audio:OpaquePointer!
	private let _audioPtr:UnsafeRawPointer

	
	public var clientWidth:Float = 1920
	public var clientHeight:Float = 1080
	
	public var netProtocol:Int32 = 1
	public var mediaContainer:Int32 = 0
	public var pngCursor:Bool = false
	var backgroundTaskRunning = true
	
	public var mouseInfo = MouseInfo()
	
	init() {
		print("Parsec SDK Version: " + String(ParsecSDKBridge.PARSEC_VER))

		ParsecSetLogCallback(
		{ (level, msg, opaque) in
			print("[\(level == LOG_DEBUG ? "D" : "I")] \(String(cString:msg!))")
		}, nil)

		audio_init(&_audio)

		ParsecInit(ParsecSDKBridge.PARSEC_VER, nil, nil, &_parsec)
		

		self._audioPtr = UnsafeRawPointer(_audio)
		
	}
	
	deinit
	{

		ParsecDestroy(_parsec)
		audio_destroy(&_audio)
	}

	func connect(_ peerID:String) -> ParsecStatus
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
		
		self.startBackgroundTask()
		
		return ParsecClientConnect(_parsec, &parsecClientCfg, NetworkHandler.clinfo?.session_id, peerID)
	}

	func disconnect()
	{
        audio_clear(&_audio)
		ParsecClientDisconnect(_parsec)
		backgroundTaskRunning = false
	}

	func getStatus() -> ParsecStatus
	{
		return ParsecClientGetStatus(_parsec, nil)
	}

	func getStatusEx(_ pcs:inout ParsecClientStatus) -> ParsecStatus
	{
		self.hostHeight = Float(pcs.decoder.0.height)
		self.hostWidth = Float(pcs.decoder.0.width)
		return ParsecClientGetStatus(_parsec, &pcs)

	}
	
	func setFrame(_ width:CGFloat, _ height:CGFloat, _ scale:CGFloat)
	{
		ParsecClientSetDimensions(_parsec, UInt8(DEFAULT_STREAM), UInt32(width), UInt32(height), Float(scale))

		clientWidth = Float(width)
		clientHeight = Float(height)
	}

	func renderGLFrame(timeout:UInt32 = 16) // timeout in ms, 16 == 60 FPS, 8 == 120 FPS, etc.
	{
		ParsecClientGLRenderFrame(_parsec, UInt8(DEFAULT_STREAM), nil, nil, timeout)
	}
	
	/*static func renderMetalFrame(_ queue:inout MTLCommandQueue, _ texturePtr:UnsafeMutablePointer<UnsafeMutableRawPointer?>, timeout:UInt32 = 16) // timeout in ms, 16 == 60 FPS, 8 == 120 FPS, etc.
	{
		ParsecClientMetalRenderFrame(_parsec, UInt8(DEFAULT_STREAM), &queue, texturePtr, nil, nil, timeout)
	}*/

	func pollAudio(timeout:UInt32 = 16) // timeout in ms, 16 == 60 FPS, 8 == 120 FPS, etc.
	{
		ParsecClientPollAudio(_parsec, audio_cb, timeout, _audioPtr)
	}
	
	var getFirstCursor = false
	var mousePositionRelative = false

	func pollEvent(timeout:UInt32 = 16) // timeout in ms, 16 == 60 FPS, 8 == 120 FPS, etc.
	{
		var e: ParsecClientEvent!
		var _event = ParsecClientEvent()
		withUnsafeMutablePointer(to: &_event, {(_eventPtr) in
			ParsecClientPollEvents(_parsec, timeout, _eventPtr)
			e = _eventPtr.pointee
		})


		let cursor = e.cursor
		let prevHidden = mouseInfo.cursorHidden
		mouseInfo.cursorHidden = cursor.cursor.hidden
		mouseInfo.mousePositionRelative = cursor.cursor.relative
		
		if cursor.cursor.imageUpdate || !getFirstCursor{
			getFirstCursor = true
			let imgKey = cursor.key
			let pointer = ParsecGetBuffer(_parsec, imgKey)
			if pointer == nil{
				return
			}
			let size = cursor.cursor.size
			let width = cursor.cursor.width
			let height = cursor.cursor.height
			mouseInfo.cursorWidth = Int(width)
			mouseInfo.cursorHeight = Int(height)
			// 之前隐藏现在不隐藏了就更新
			if prevHidden && !cursor.cursor.hidden {
				mouseInfo.mouseX = Int32(cursor.cursor.positionX)
				mouseInfo.mouseY = Int32(cursor.cursor.positionY)
			}

			mouseInfo.cursorHotX = Int(cursor.cursor.hotX)
			mouseInfo.cursorHotY = Int(cursor.cursor.hotY)
			
			
			var colors = [RGBA]()
			let count = size << 2
			for i in 0..<count {
					
				// Bind the memory at the calculated offset to the struct type
				let boundPointer = pointer!.bindMemory(to: RGBA.self, capacity: 1)
					
				// Access the struct at the current offset
				let currentStruct = boundPointer.advanced(by: Int(i)).pointee
					
				// Append the struct to the array
				colors.append(currentStruct)
			}
			ParsecFree(pointer)
			
			
			let _: Int = colors.count
			let elmentLength: Int = 4
			let render: CGColorRenderingIntent = CGColorRenderingIntent.defaultIntent
			let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
			let bitmapInfo: CGBitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
			let providerRef: CGDataProvider? = CGDataProvider(data: NSData(bytes: &colors, length: Int(size)))
			let cgimage: CGImage? = CGImage(width: Int(width), height: Int(height), bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: Int(width) * elmentLength, space: rgbColorSpace, bitmapInfo: bitmapInfo, provider: providerRef!, decode: nil, shouldInterpolate: true, intent: render)
			if cgimage != nil {
				mouseInfo.cursorImg = cgimage
			}
		
		}
	}
	
	func setMuted(_ muted:Bool)
	{
		audio_mute(muted, _audioPtr)
	}
	
	func applyConfig()
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

	func sendMouseMessage(_ button:ParsecMouseButton, _ x:Int32, _ y:Int32, _ pressed:Bool)
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
	
	func sendMouseClickMessage(_ button:ParsecMouseButton, _ pressed:Bool) {
		var buttonMessage = ParsecMessage()
		buttonMessage.type = MESSAGE_MOUSE_BUTTON
		buttonMessage.mouseButton.button = button
		buttonMessage.mouseButton.pressed = pressed
		ParsecClientSendMessage(_parsec, &buttonMessage)
	}
	
	func sendMouseDelta(_ dx: Int32, _ dy: Int32) {
		if mouseInfo.mousePositionRelative {
			sendMouseRelativeMove(dx, dy)
		} else {
			sendMousePosition(mouseInfo.mouseX + dx, mouseInfo.mouseY + dy)
		}
		
	}
	static func clamp<T>(_ value: T, minValue: T, maxValue: T) -> T where T : Comparable {
		return min(max(value, minValue), maxValue)
	}

	func sendMousePosition(_ x:Int32, _ y:Int32)
	{
		mouseInfo.mouseX = ParsecSDKBridge.clamp(x, minValue: 0, maxValue: Int32(self.clientWidth))
		mouseInfo.mouseY = ParsecSDKBridge.clamp(y, minValue: 0, maxValue: Int32(self.clientHeight))
		var motionMessage = ParsecMessage()
		motionMessage.type = MESSAGE_MOUSE_MOTION
		motionMessage.mouseMotion.x = x
		motionMessage.mouseMotion.y = y
		ParsecClientSendMessage(_parsec, &motionMessage)
	}
	
	func sendMouseRelativeMove(_ dx:Int32, _ dy:Int32)
	{
		var motionMessage = ParsecMessage()
		motionMessage.type = MESSAGE_MOUSE_MOTION
		motionMessage.mouseMotion.x = dx
		motionMessage.mouseMotion.y = dy
		motionMessage.mouseMotion.relative = true
		ParsecClientSendMessage(_parsec, &motionMessage)
	}

	func sendKeyboardMessage(event:KeyBoardKeyEvent)
	{
		if event.input == nil {
			return
		}
//		var key =
		
//		print("code =  \(event.input?.keyCode)")
//		key = event.input?.characters.uppercased() ?? " "
//		
//		if key == " " {
//			key = "SPACE"
//		}

//		switch sender.modifierFlags.rawValue
//		{
//			case 131072:
//				key = "SHIFT"
//				break
//			case 262144:
//				key = "CONTROL"
//				break
//
//			default:
//				break
//		}
//
//		print("Keyboard Message: \(key)")
//		print("KeyboardViewController keyboard modifier info \(sender.modifierFlags.rawValue)")
		
		var keyboardMessagePress = ParsecMessage()
		keyboardMessagePress.type = MESSAGE_KEYBOARD
		keyboardMessagePress.keyboard.code = ParsecKeycode(UInt32(ParsecSDKBridge.uiKeyCodeToInt(key: event.input?.keyCode ?? UIKeyboardHIDUsage.keyboardErrorUndefined)))
		keyboardMessagePress.keyboard.pressed = event.isPressBegin
		ParsecClientSendMessage(_parsec, &keyboardMessagePress)
	}
	
	static func uiKeyCodeToInt(key: UIKeyboardHIDUsage) -> Int {
		switch key {
		case .keyboardErrorRollOver:
			return 1
		case .keyboardPOSTFail:
			return 2
		case .keyboardErrorUndefined:
			return 3
		case .keyboardA:
			return 4
		case .keyboardB:
			return 5
		case .keyboardC:
			return 6
		case .keyboardD:
			return 7
		case .keyboardE:
			return 8
		case .keyboardF:
			return 9
		case .keyboardG:
			return 10
		case .keyboardH:
			return 11
		case .keyboardI:
			return 12
		case .keyboardJ:
			return 13
		case .keyboardK:
			return 14
		case .keyboardL:
			return 15
		case .keyboardM:
			return 16
		case .keyboardN:
			return 17
		case .keyboardO:
			return 18
		case .keyboardP:
			return 19
		case .keyboardQ:
			return 20
		case .keyboardR:
			return 21
		case .keyboardS:
			return 22
		case .keyboardT:
			return 23
		case .keyboardU:
			return 24
		case .keyboardV:
			return 25
		case .keyboardW:
			return 26
		case .keyboardX:
			return 27
		case .keyboardY:
			return 28
		case .keyboardZ:
			return 29
		case .keyboard1:
			return 30
		case .keyboard2:
			return 31
		case .keyboard3:
			return 32
		case .keyboard4:
			return 33
		case .keyboard5:
			return 34
		case .keyboard6:
			return 35
		case .keyboard7:
			return 36
		case .keyboard8:
			return 37
		case .keyboard9:
			return 38
		case .keyboard0:
			return 39
		case .keyboardReturnOrEnter:
			return 40
		case .keyboardEscape:
			return 41
		case .keyboardDeleteOrBackspace:
			return 42
		case .keyboardTab:
			return 43
		case .keyboardSpacebar:
			return 44
		case .keyboardHyphen:
			return 45
		case .keyboardEqualSign:
			return 46
		case .keyboardOpenBracket:
			return 47
		case .keyboardCloseBracket:
			return 48
		case .keyboardBackslash:
			return 49
		case .keyboardNonUSPound:
			return 50
		case .keyboardSemicolon:
			return 51
		case .keyboardQuote:
			return 52
		case .keyboardGraveAccentAndTilde:
			return 53
		case .keyboardComma:
			return 54
		case .keyboardPeriod:
			return 55
		case .keyboardSlash:
			return 56
		case .keyboardCapsLock:
			return 57
		case .keyboardF1:
			return 58
		case .keyboardF2:
			return 59
		case .keyboardF3:
			return 60
		case .keyboardF4:
			return 61
		case .keyboardF5:
			return 62
		case .keyboardF6:
			return 63
		case .keyboardF7:
			return 64
		case .keyboardF8:
			return 65
		case .keyboardF9:
			return 66
		case .keyboardF10:
			return 67
		case .keyboardF11:
			return 68
		case .keyboardF12:
			return 69
		case .keyboardPrintScreen:
			return 70
		case .keyboardScrollLock:
			return 71
		case .keyboardPause:
			return 72
		case .keyboardInsert:
			return 73
		case .keyboardHome:
			return 74
		case .keyboardPageUp:
			return 75
		case .keyboardDeleteForward:
			return 76
		case .keyboardEnd:
			return 77
		case .keyboardPageDown:
			return 78
		case .keyboardRightArrow:
			return 79
		case .keyboardLeftArrow:
			return 80
		case .keyboardDownArrow:
			return 81
		case .keyboardUpArrow:
			return 82
		case .keypadNumLock:
			return 83
		case .keypadSlash:
			return 84
		case .keypadAsterisk:
			return 85
		case .keypadHyphen:
			return 86
		case .keypadPlus:
			return 87
		case .keypadEnter:
			return 88
		case .keypad1:
			return 89
		case .keypad2:
			return 90
		case .keypad3:
			return 91
		case .keypad4:
			return 92
		case .keypad5:
			return 93
		case .keypad6:
			return 94
		case .keypad7:
			return 95
		case .keypad8:
			return 96
		case .keypad9:
			return 97
		case .keypad0:
			return 98
		case .keypadPeriod:
			return 99
		case .keyboardNonUSBackslash:
			return 100
		case .keyboardApplication:
			return 101
		case .keyboardPower:
			return 102
		case .keypadEqualSign:
			return 103
		case .keyboardF13:
			return 104
		case .keyboardF14:
			return 105
		case .keyboardF15:
			return 106
		case .keyboardF16:
			return 107
		case .keyboardF17:
			return 108
		case .keyboardF18:
			return 109
		case .keyboardF19:
			return 110
		case .keyboardF20:
			return 111
		case .keyboardF21:
			return 112
		case .keyboardF22:
			return 113
		case .keyboardF23:
			return 114
		case .keyboardF24:
			return 115
		case .keyboardExecute:
			return 116
		case .keyboardHelp:
			return 117
		case .keyboardMenu:
			return 118
		case .keyboardSelect:
			return 119
		case .keyboardStop:
			return 120
		case .keyboardAgain:
			return 121
		case .keyboardUndo:
			return 122
		case .keyboardCut:
			return 123
		case .keyboardCopy:
			return 124
		case .keyboardPaste:
			return 125
		case .keyboardFind:
			return 126
		case .keyboardMute:
			return 127
		case .keyboardVolumeUp:
			return 128
		case .keyboardVolumeDown:
			return 129
		case .keyboardLockingCapsLock:
			return 130
		case .keyboardLockingNumLock:
			return 131
		case .keyboardLockingScrollLock:
			return 132
		case .keypadComma:
			return 133
		case .keypadEqualSignAS400:
			return 134
		case .keyboardInternational1:
			return 135
		case .keyboardInternational2:
			return 136
		case .keyboardInternational3:
			return 137
		case .keyboardInternational4:
			return 138
		case .keyboardInternational5:
			return 139
		case .keyboardInternational6:
			return 140
		case .keyboardInternational7:
			return 141
		case .keyboardInternational8:
			return 142
		case .keyboardInternational9:
			return 143
		case .keyboardLANG1:
			return 144
		case .keyboardLANG2:
			return 145
		case .keyboardLANG3:
			return 146
		case .keyboardLANG4:
			return 147
		case .keyboardLANG5:
			return 148
		case .keyboardLANG6:
			return 149
		case .keyboardLANG7:
			return 150
		case .keyboardLANG8:
			return 151
		case .keyboardLANG9:
			return 152
		case .keyboardAlternateErase:
			return 153
		case .keyboardSysReqOrAttention:
			return 154
		case .keyboardCancel:
			return 155
		case .keyboardClear:
			return 156
		case .keyboardPrior:
			return 157
		case .keyboardReturn:
			return 158
		case .keyboardSeparator:
			return 159
		case .keyboardOut:
			return 160
		case .keyboardOper:
			return 161
		case .keyboardClearOrAgain:
			return 162
		case .keyboardCrSelOrProps:
			return 163
		case .keyboardExSel:
			return 164
		case .keyboardLeftControl:
			return 224
		case .keyboardLeftShift:
			return 225
		case .keyboardLeftAlt:
			return 226
		case .keyboardLeftGUI:
			return 227
		case .keyboardRightControl:
			return 228
		case .keyboardRightShift:
			return 229
		case .keyboardRightAlt:
			return 230
		case .keyboardRightGUI:
			return 231
		case .keyboard_Reserved:
			return 65535
		case .keyboardHangul:
			return 144
		case .keyboardHanja:
			return 145
		case .keyboardKanaSwitch:
			return 144
		case .keyboardAlphanumericSwitch:
			return 145
		case .keyboardKatakana:
			return 146
		case .keyboardHiragana:
			return 147
		case .keyboardZenkakuHankakuKanji:
			return 148
		default:
			return 0
		}
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
	
	func sendGameControllerButtonMessage(controllerId:UInt32, _ button:ParsecGamepadButton, pressed:Bool)
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
	
	func sendGameControllerAxisMessage(controllerId:UInt32, _ button:ParsecGamepadAxis, _ value: Int16)
	{
	    var pmsg = ParsecMessage()
		pmsg.type = MESSAGE_GAMEPAD_AXIS
		pmsg.gamepadAxis.id = controllerId
		pmsg.gamepadAxis.axis = button
		pmsg.gamepadAxis.value = value
		ParsecClientSendMessage(_parsec, &pmsg)
	}
	
	func sendGameControllerUnplugMessage(controllerId:UInt32)
	{
	    var pmsg = ParsecMessage()
		pmsg.type = MESSAGE_GAMEPAD_UNPLUG;
		pmsg.gamepadUnplug.id = controllerId;
		ParsecClientSendMessage(_parsec, &pmsg)
	}
	
	func sendWheelMsg(x: Int32, y: Int32) {
		var pmsg = ParsecMessage()
		pmsg.type = MESSAGE_MOUSE_WHEEL;
		pmsg.mouseWheel.x = x
		pmsg.mouseWheel.y = y
		ParsecClientSendMessage(_parsec, &pmsg)
	}
	
	func startBackgroundTask(){
	
		
		let item1 = DispatchWorkItem {
			while self.backgroundTaskRunning {
				self.pollAudio()
			}
			
		}

		let item2 = DispatchWorkItem {
			while self.backgroundTaskRunning {
				self.pollEvent()
	
				
			}
			
		}
		let mainQueue = DispatchQueue.global()
		mainQueue.async(execute: item1)
		mainQueue.async(execute: item2)
	}
}
