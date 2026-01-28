import ParsecSDK
import MetalKit
import UIKit
import OSLog


import Metal


enum RendererType: Int
{
	case opengl
    case metal
}

enum DecoderPref: Int
{
    case h264
    case h265
}

enum CursorMode: Int
{
    case touchpad
    case direct
}

enum RightClickPosition: Int
{
	case firstFinger
	case middle
	case secondFinger
}

struct KeyBoardKeyEvent {
	var input: UIKey?
	var isPressBegin: Bool
}

class ParsecSDKBridge: ParsecService
{
	var hostWidth: Float = 1920
	
	var hostHeight: Float = 1080


	static let PARSEC_VER: UInt32 = UInt32((PARSEC_VER_MAJOR << 16) | PARSEC_VER_MINOR)
	
	private var _parsec: OpaquePointer!
	private var _audio: OpaquePointer!
	private let _audioPtr: UnsafeRawPointer
	
	private var isVirtualShiftOn = false
	
	public var clientWidth: Float = 1920
	public var clientHeight: Float = 1080
	
	public var netProtocol: Int32 = 1
	public var mediaContainer: Int32 = 0
	public var pngCursor: Bool = false



	private var audioWorkItem: DispatchWorkItem?
	private var eventWorkItem: DispatchWorkItem?


	var didSetResolution = false
	
	public var mouseInfo = MouseInfo()
	
	init() {
		print("Parsec SDK Version: " + String(ParsecSDKBridge.PARSEC_VER))
		
		ParsecSetLogCallback(
			{ (level, msg, opaque) in
				print("[\(level == LOG_DEBUG ? "D" : "I")] \(String(cString:msg!))")
			}, nil)
		
		audio_init(&_audio)
		
		self._audioPtr = UnsafeRawPointer(_audio)
		
		do {
			let reservedCfg = ["ssHost": "kessel-ws.parsec.app"]
			let json = JSONEncoder()
			try json.encode(reservedCfg).withUnsafeBytes { (jsonStrBPtr: UnsafeRawBufferPointer) in
				guard let jsonStrPtr = jsonStrBPtr.baseAddress else {
					return
				}
				ParsecInit(ParsecSDKBridge.PARSEC_VER, nil, jsonStrPtr, &_parsec)
			}

		} catch {
			print("error: \(error)")
		}

	}
	
	deinit {
		ParsecDestroy(_parsec)
		audio_destroy(&_audio)
	}

	func destroy() {
		ParsecDestroy(_parsec)
		print("清理Parsec")

	}


	func connect(_ peerID: String) -> ParsecStatus {

		var parsecClientCfg = ParsecClientConfig()
		parsecClientCfg.video.0.decoderIndex = 1
		parsecClientCfg.video.0.resolutionX = 0
		parsecClientCfg.video.0.resolutionY = 0
		parsecClientCfg.video.0.decoderCompatibility = SettingsHandler.decoderCompatibility


		parsecClientCfg.video.0.decoder444 = false
		
		parsecClientCfg.video.0.decoderH265 = SettingsHandler.decoder == .h265

		print(
			"Debug Compatibility? -> \(parsecClientCfg.video.0.decoderCompatibility)"
		)

		print("Debug H265? -> \(parsecClientCfg.video.0.decoderH265)")

//		parsecClientCfg.video.1.decoderIndex = 1
//		parsecClientCfg.video.1.resolutionX = 0
//		parsecClientCfg.video.1.resolutionY = 0
//		parsecClientCfg.video.1.decoderCompatibility = false
//		parsecClientCfg.video.1.decoderH265 = true
//
		
		parsecClientCfg.mediaContainer = 0
		parsecClientCfg.protocol = 1
		//parsecClientCfg.secret = ""
		parsecClientCfg.pngCursor = false


		let status = ParsecClientConnect(_parsec, &parsecClientCfg, NetworkHandler.clinfo?.session_id, peerID)



		self.startBackgroundTask()

		return status
	}



	func disconnect() {

		mouseInfo.cursorImg = nil
		getFirstCursor = false

		stopBackgroundTask()

		audio_clear(&_audio)

		ParsecClientDisconnect(_parsec)


	}



	func getStatus() -> ParsecStatus {
		
		return ParsecClientGetStatus(_parsec, nil)
	}

	func getOutputs(maxCount: Int = 10) -> [ParsecDecoder] {
		// 1️⃣ 创建一个 C 数组
		var outputs = [ParsecDecoder](
			repeating: ParsecDecoder(),
			count: maxCount
		)

		// 2️⃣ 调用 SDK
		let count = outputs.withUnsafeMutableBufferPointer { buffer -> UInt32 in
			return ParsecGetDecoders(buffer.baseAddress, UInt32(buffer.count))
		}
		// 3️⃣ 返回 Swift 数组
		return Array(outputs.prefix(Int(count)))
		
	}


	func getStatusEx(_ pcs: inout ParsecClientStatus) -> ParsecStatus {

		let status = ParsecClientGetStatus(_parsec, &pcs)
		if status == PARSEC_OK {
			hostWidth  = Float(pcs.decoder.0.width)
			hostHeight = Float(pcs.decoder.0.height)
		}
		return status
	}

	func setFrame(_ width:CGFloat, _ height:CGFloat, _ scale:CGFloat)
	{
		ParsecClientSetDimensions(_parsec, UInt8(DEFAULT_STREAM), UInt32(width), UInt32(height), Float(scale))
		
		clientWidth = Float(width)
		clientHeight = Float(height)
		mouseInfo.mouseX = Int32(width / 2)
		mouseInfo.mouseY = Int32(height / 2)
	}




	// timeout in ms, 16 == 60 FPS, 8 == 120 FPS, etc.
	func renderGLFrame(timeout: UInt32 = 16) {
		
		ParsecClientGLRenderFrame(_parsec, UInt8(DEFAULT_STREAM), nil, nil, timeout)
	}

	func clearGL(){
		os_log("ClearGL")
		ParsecClientGLDestroy(_parsec,UInt8(DEFAULT_STREAM))

	}

	/*static func renderMetalFrame(_ queue:inout MTLCommandQueue, _ texturePtr: UnsafeMutablePointer<UnsafeMutableRawPointer?>, timeout: UInt32 = 16) // timeout in ms, 16 == 60 FPS, 8 == 120 FPS, etc.
	 {
	 ParsecClientMetalRenderFrame(_parsec, UInt8(DEFAULT_STREAM), &queue, texturePtr, nil, nil, timeout)
	 }*/


	

	// 在 CParsec 封裝層
	func renderMetalFrame(
		queue: MTLCommandQueue,
		texture: MTLTexture,
		timeout: UInt32 = 16
	) -> ParsecStatus {

		//let cq = Unmanaged.passUnretained(queue).toOpaque()

		var texPtr: UnsafeMutableRawPointer? = Unmanaged.passUnretained(texture).toOpaque()

		let texPtrPtr = withUnsafeMutablePointer(to: &texPtr) { $0 }


		let status = ParsecClientMetalRenderFrame(
			_parsec,
			UInt8(DEFAULT_STREAM),
			nil,
			texPtrPtr,
			nil,
			UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque()),
			timeout
		)

		// SDK 可能在內部替換 texture（例如 resize）
		if let newTexPtr = texPtrPtr.pointee {
			let newTex =
				Unmanaged<MTLTexture>
				.fromOpaque(newTexPtr)
				.takeUnretainedValue()

			if #available(iOS 16.0, *) {
				print("Device",newTex.device,newTex.gpuResourceID,
					  String(describing: newTex.parent))
			} else {
				print("Device15",newTex.device,String(describing: newTex.parent))


				// Fallback on earlier versions
			}
			print("Texture size: \(newTex.width)x\(newTex.height)")
			print("Pixel format: \(newTex.pixelFormat)")

			ParsecMetalTarget.shared.texture = newTex
		}


		
		return status
	}



	func pollAudio(timeout:UInt32 = 16) // timeout in ms, 16 == 60 FPS, 8 == 120 FPS, etc.
	{
		ParsecClientPollAudio(_parsec, audio_cb, timeout, _audioPtr)
	}
	
	var getFirstCursor = false
	var mousePositionRelative = false
	
	func pollEvent(timeout: UInt32 = 16) // timeout in ms, 16 == 60 FPS, 8 == 120 FPS, etc.
	{
		var e: ParsecClientEvent!
		var _event = ParsecClientEvent()
		var pollSuccess = false;
		withUnsafeMutablePointer(to: &_event, {(_eventPtr) in
			pollSuccess = ParsecClientPollEvents(_parsec, timeout, _eventPtr)
			e = _eventPtr.pointee
		})
		if !pollSuccess {
			return
		}
		if e.type == CLIENT_EVENT_CURSOR {
			handleCursorEvent(event: e.cursor)
		} else if e.type == CLIENT_EVENT_USER_DATA {
			handleUserDataEvent(event: e.userData)
		}
	}


	func handleUserDataEvent(event: ParsecClientUserDataEvent) {
		
		let pointer = ParsecGetBuffer(_parsec, event.key)
		switch event.id {
		case 11:
			do {
				let decoder = JSONDecoder()
				let config = try decoder.decode(ParsecUserDataVideoConfig.self, from: Data(bytesNoCopy: pointer!, count: strlen(pointer!), deallocator: .none))
				let videoConfig = config.video[0]

				DispatchQueue.main.async {
					DataManager.model.resolutionX = videoConfig.resolutionX
					DataManager.model.resolutionY = videoConfig.resolutionY
					DataManager.model.bitrate = videoConfig.encoderMaxBitrate
					DataManager.model.constantFps = videoConfig.fullFPS
					if !self.didSetResolution {
						self.didSetResolution = true
						DataManager.model.resolutionX = SettingsHandler.resolution.width
						DataManager.model.resolutionY = SettingsHandler.resolution.height
						self.updateHostVideoConfig()
					}
				}
				
			} catch {
				print("error while parsing user data: \(error.localizedDescription)")
			}
		case 12:
			do {
				let decoder = JSONDecoder()
				let config = try decoder.decode(Array<ParsecDisplayConfig>.self, from: Data(bytesNoCopy: pointer!, count: strlen(pointer!), deallocator: .none))
				DispatchQueue.main.async {
					DataManager.model.displayConfigs = config
				}
			} catch {
				print("error while parsing user data: \(error.localizedDescription)")
			}
		default:
			break
		}
		
		ParsecFree(pointer)
		
	}

	

	func handleCursorEvent(event: ParsecClientCursorEvent) {

		//let prevHidden = mouseInfo.cursorHidden
		mouseInfo.cursorHidden = event.cursor.hidden
		mouseInfo.mousePositionRelative = event.cursor.relative

		guard event.cursor.imageUpdate || !getFirstCursor else {
			return
		}
		getFirstCursor = true

		guard let pointer = ParsecGetBuffer(_parsec, event.key) else {
			return
		}

		defer {
			ParsecFree(pointer)
		}

		let size = Int(event.cursor.size)
		let width = Int(event.cursor.width)
		let height = Int(event.cursor.height)

		let data = Data(bytes: pointer, count: size)   // ✅ Swift 管理

		let provider = CGDataProvider(data: data as CFData)!

		let cgimage = CGImage(
			width: width,
			height: height,
			bitsPerComponent: 8,
			bitsPerPixel: 32,
			bytesPerRow: width * 4,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
			provider: provider,
			decode: nil,
			shouldInterpolate: true,
			intent: .defaultIntent
		)

		if let cgimage {
			mouseInfo.cursorImg = cgimage   // 舊的會被 ARC 釋放
		}
	}
	func setMuted(_ muted: Bool) {
		audio_mute(muted, _audioPtr)
	}
	
	func applyConfig() {

		var parsecClientCfg = ParsecClientConfig()

		parsecClientCfg.video.0.decoderIndex = 1
		parsecClientCfg.video.0.resolutionX = 0
		parsecClientCfg.video.0.resolutionY = 0
		parsecClientCfg.video.0.decoderCompatibility = SettingsHandler.decoderCompatibility
		parsecClientCfg.video.0.decoderH265 = SettingsHandler.decoder == .h265

		//可能是多餘的流
//		parsecClientCfg.video.1.decoderIndex = 1
//		parsecClientCfg.video.1.resolutionX = 0
//		parsecClientCfg.video.1.resolutionY = 0
//		parsecClientCfg.video.1.decoderCompatibility = false
//		parsecClientCfg.video.1.decoderH265 = SettingsHandler.decoder == .h265
//

		parsecClientCfg.mediaContainer = mediaContainer
		parsecClientCfg.protocol = netProtocol
		//parsecClientCfg.secret = ""
		parsecClientCfg.pngCursor = pngCursor

		ParsecClientSetConfig(_parsec, &parsecClientCfg);
	}
	
	func sendMouseMessage(_ button:ParsecMouseButton, _ x:Int32, _ y:Int32, _ pressed: Bool)
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
	
	func sendMouseClickMessage(_ button:ParsecMouseButton, _ pressed: Bool) {
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
	
	func getKeyCodeByText(text: String) -> (ParsecKeycode?, Bool) {
		var keyCode : ParsecKeycode?
		var useShift = false


		if text.count == 1 {
			let char = Character(text)
			if char.isLetter || char.isNumber {
				keyCode = KeyCodeTranslators.parsecKeyCodeTranslator(text.uppercased())
				if char.isUppercase {
					useShift = true
				}

			} else if char.isNewline {
				keyCode = ParsecKeycode(40)
			} else if char.isWhitespace{
				keyCode = ParsecKeycode(44)
			} else {
				let (keycodeRaw, keyMod) = KeyCodeTranslators.getParsecKeycode(for: text)
				if keycodeRaw != -1 {
					keyCode = ParsecKeycode(UInt32(keycodeRaw))
					if keyMod {
						useShift = true
					}
				}
			}
		} else {
			keyCode = KeyCodeTranslators.parsecKeyCodeTranslator(text)
		}

		if let key = keyCode {
			os_log("KeyCode:\(key.rawValue)-\(text)")
		}

		return (keyCode, useShift)
	}
	
	func sendVirtualKeyboardInput(text: String) {
		let (keyCode, useShift) = getKeyCodeByText(text: text)

		guard let keyCode else {
			return
		}

		os_log("KeyCode:\(keyCode.rawValue)-\(text)")

		if !isVirtualShiftOn && useShift {
			var shiftDown = ParsecMessage()
			shiftDown.type = MESSAGE_KEYBOARD
			shiftDown.keyboard.code = ParsecKeycode(rawValue: 225)
			shiftDown.keyboard.pressed = true
			ParsecClientSendMessage(_parsec, &shiftDown)
		}

		var keyboardMessagePress = ParsecMessage()
		keyboardMessagePress.type = MESSAGE_KEYBOARD
		keyboardMessagePress.keyboard.pressed = true
		keyboardMessagePress.keyboard.code = keyCode

		let res = ParsecClientSendMessage(_parsec, &keyboardMessagePress)

		os_log("Key res->\(res.rawValue)")


		// add release delay in case some games ignore instant key release
		DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {

			// 主鍵 release
			var keyUp = ParsecMessage()
			keyUp.type = MESSAGE_KEYBOARD
			keyUp.keyboard.code = keyCode
			keyUp.keyboard.pressed = false
			ParsecClientSendMessage(self._parsec, &keyUp)

			// Shift release
			if useShift && !self.isVirtualShiftOn {
				var shiftUp = ParsecMessage()
				shiftUp.type = MESSAGE_KEYBOARD
				shiftUp.keyboard.code = ParsecKeycode(rawValue: 225)
				shiftUp.keyboard.pressed = false
				ParsecClientSendMessage(self._parsec, &shiftUp)
			}


			os_log("Key Release")

		}

	}


	func sendVirtualKeyboardInput(text: String, isOn: Bool) {
		let (keyCode, _) = getKeyCodeByText(text: text)
		
		guard let keyCode else {
			return
		}
		
		if keyCode.rawValue == 225 {
			isVirtualShiftOn = isOn
		}



		var keyboardMessagePress = ParsecMessage()
		keyboardMessagePress.type = MESSAGE_KEYBOARD
		keyboardMessagePress.keyboard.pressed = isOn
		keyboardMessagePress.keyboard.code = keyCode
		ParsecClientSendMessage(_parsec, &keyboardMessagePress)
		
	}

	func sendKeyboardMessage(event:KeyBoardKeyEvent)
	{

		if event.input == nil {
			return
		}

		os_log("")

		var keyboardMessagePress = ParsecMessage()
		keyboardMessagePress.type = MESSAGE_KEYBOARD
		keyboardMessagePress.keyboard.code = ParsecKeycode(UInt32(KeyCodeTranslators.uiKeyCodeToInt(key: event.input?.keyCode ?? UIKeyboardHIDUsage.keyboardErrorUndefined)))

		keyboardMessagePress.keyboard.pressed = event.isPressBegin

		ParsecClientSendMessage(_parsec, &keyboardMessagePress)

	}
	
	func sendGameControllerButtonMessage(controllerId: UInt32, _ button:ParsecGamepadButton, pressed: Bool)
	{
		var pmsg = ParsecMessage()
		pmsg.type = MESSAGE_GAMEPAD_BUTTON
		pmsg.gamepadButton.id = controllerId
		pmsg.gamepadButton.button = button
		pmsg.gamepadButton.pressed = pressed
		ParsecClientSendMessage(_parsec, &pmsg)
	}
	
	/*static func sendGameControllerTriggerButtonMessage(controllerId: UInt32, _ button:ParsecGamepadAxis, pressed: Bool)
	{
	    var pmsg = ParsecMessage()
		pmsg.type = MESSAGE_GAMEPAD_AXIS
		pmsg.gamepadAxis.id = controllerId
		pmsg.gamepadAxis.button = button
		pmsg.gamepadAxis.pressed = pressed
		ParsecClientSendMessage(_parsec, &pmsg)
	}*/
	
	func sendGameControllerAxisMessage(controllerId: UInt32, _ button:ParsecGamepadAxis, _ value: Int16)
	{
	    var pmsg = ParsecMessage()
		pmsg.type = MESSAGE_GAMEPAD_AXIS
		pmsg.gamepadAxis.id = controllerId
		pmsg.gamepadAxis.axis = button
		pmsg.gamepadAxis.value = value
		ParsecClientSendMessage(_parsec, &pmsg)
	}
	
	func sendGameControllerUnplugMessage(controllerId: UInt32)
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
	
	func startBackgroundTask() {

		guard audioWorkItem == nil, eventWorkItem == nil else {
			return
		}

		// audio
		audioWorkItem = DispatchWorkItem { [weak self] in
			guard let self else { return }
			while !(self.audioWorkItem?.isCancelled ?? true) {
				//os_log("WorkAudio")
				self.pollAudio()
				Thread.sleep(forTimeInterval: 0.01) // 適度 yield CPU
			}
		}
		// event
		eventWorkItem = DispatchWorkItem { [weak self] in
			guard let self else { return }
			while !(self.eventWorkItem?.isCancelled ?? true) {
				//os_log("WorkEvent")
				self.pollEvent()
				Thread.sleep(forTimeInterval: 0.01)
			}
		}



		DispatchQueue.global().async(execute: audioWorkItem!)
		DispatchQueue.global().async(execute: eventWorkItem!)

	}

	func stopBackgroundTask() {

		guard let audioWorkItem = audioWorkItem, let eventWorkItem = eventWorkItem else {
			return
		}

		// 安全停止
		audioWorkItem.cancel()
		eventWorkItem.cancel()

		// 用 DispatchGroup 等待
		let group = DispatchGroup()

		group.enter()
		DispatchQueue.global().async {
			while !audioWorkItem.isCancelled {
				Thread.sleep(forTimeInterval: 0.01)
			}
			group.leave()
		}

		group.enter()
		DispatchQueue.global().async {
			while !eventWorkItem.isCancelled {
				Thread.sleep(forTimeInterval: 0.01)
			}
			group.leave()
		}

		// 阻塞等待完成
		group.wait()

		// 可選：釋放引用
		self.audioWorkItem = nil
		self.eventWorkItem = nil
	}



	func sendUserData(type: ParsecUserDataType, message: Data) {
        var nullTerminatedMessage = message
        nullTerminatedMessage.append(0)
		nullTerminatedMessage.withUnsafeBytes { ptr in
			let ptr2 = ptr.baseAddress?.assumingMemoryBound(to: CChar.self)
			ParsecClientSendUserData(_parsec, type.rawValue, ptr2)
		}
	}
	
	func updateHostVideoConfig() {
		var videoConfig = ParsecUserDataVideoConfig()
		videoConfig.video[0].resolutionX = DataManager.model.resolutionX
		videoConfig.video[0].resolutionY = DataManager.model.resolutionY
		videoConfig.video[0].encoderMaxBitrate = DataManager.model.bitrate
		videoConfig.video[0].fullFPS = DataManager.model.constantFps
		videoConfig.video[0].output = DataManager.model.output
		let encoder = JSONEncoder()
		let data = try! encoder.encode(videoConfig)
		CParsec.sendUserData(type: .setVideoConfig, message: data)
	}
}
