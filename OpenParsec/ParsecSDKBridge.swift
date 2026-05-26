import ParsecSDK
import MetalKit
import UIKit
import os

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

// Which hotkey to fire at the host when the iPad's hardware-keyboard input
// language changes. Default: Ctrl+Space, the macOS built-in "select previous
// input source" shortcut — works if the user has the same two layouts on the
// host as on the iPad, in the same order. For other layout sets / OSes the
// user can pick a different combination in Settings.
enum LayoutSyncHotkey: Int, CaseIterable
{
    case none = 0
    case ctrlSpace = 1
    case cmdSpace = 2
    case altSpace = 3
    case altShift = 4
    case ctrlShift = 5  // ⌃⇧ — another common macOS layout-toggle binding
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
	// Doubles as a gate for outgoing input messages: while false (between an
	// explicit disconnect and the next connect, including the brief gap in
	// changeResolution), every send* method below early-returns so we don't
	// fire ParsecClientSendMessage into a disconnected client.
	var backgroundTaskRunning = true
	// C3 fix: monotonic token bumped on every startBackgroundTask(). Each poll
	// loop captures the value at spawn and exits the instant the token moves,
	// so a fast disconnect→reconnect (which the 0.02 s drain in disconnect()
	// can't guarantee has fully drained) cannot leave two generations of
	// audio/event loops running against one client and double-polling
	// ParsecGetBuffer / ParsecFree.
	private var pollGeneration: Int = 0
	var didSetResolution = false
	// Restored once per session in handleUserDataEvent case 12 so display
	// hot-plug / sleep-wake echoes don't keep re-firing updateHostVideoConfig
	// and causing momentary re-encode flicker.
	var didRestoreSavedDisplay = false
	
	// C1 fix: `mouseInfo` is written on the poll thread (handleCursorEvent),
	// on the input paths (sendMousePosition / setFrame), and read on the main
	// thread (updateImage). It holds a `CGImage?` (`cursorImg`) — an ARC
	// reference. A struct copy in the getter retains `cursorImg` while a
	// concurrent write releases it; that non-atomic retain/release races and
	// over-releases the CGImage → use-after-free crash that fires constantly
	// during cursor motion. All access now goes through `os_unfair_lock`:
	// readers take an atomic snapshot via the `mouseInfo` getter, writers
	// mutate under the same lock via `withMouseInfo`.
	private var _mouseInfo = MouseInfo()
	private var mouseInfoLock = os_unfair_lock_s()

	// Atomic snapshot for cross-thread readers. Returns a consistent copy of
	// the whole struct under the lock so `cursorImg`'s retain happens while no
	// writer can release it.
	var mouseInfo: MouseInfo {
		os_unfair_lock_lock(&mouseInfoLock)
		defer { os_unfair_lock_unlock(&mouseInfoLock) }
		return _mouseInfo
	}

	// Serialize every mutation under the same lock the snapshot getter uses.
	// Keep the body short — never do heavy work (e.g. CGImage construction)
	// while holding the lock; build first, then assign inside.
	@discardableResult
	private func withMouseInfo<T>(_ body: (inout MouseInfo) -> T) -> T {
		os_unfair_lock_lock(&mouseInfoLock)
		defer { os_unfair_lock_unlock(&mouseInfoLock) }
		return body(&_mouseInfo)
	}

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
	
	func connect(_ peerID: String) -> ParsecStatus {
		// CRITICAL: disconnect() set this to false to drain the poll loops.
		// If we don't flip it back to true here, the new poll loops spawned
		// by startBackgroundTask() below will read false on their first
		// iteration and exit immediately — leaving the session with no audio
		// callbacks, no cursor updates, and no user-data events for the rest
		// of its lifetime. Also acts as the "sending allowed" gate for input
		// messages, so flip it before any input could possibly fire.
		backgroundTaskRunning = true
		// Every fresh connect() should attempt to restore the saved display
		// when case-12 arrives. Resetting here (not only in disconnect()) is
		// load-bearing — common reconnect paths (alert dismiss → reconnect,
		// background → resume) skip disconnect() entirely, so without this
		// the flag stayed `true` from a prior session and the restore was
		// silently never re-run.
		didRestoreSavedDisplay = false
		didSetResolution = false

		var parsecClientCfg = ParsecClientConfig()
		parsecClientCfg.video.0.decoderIndex = 1
        // Use saved resolution from SettingsHandler
		parsecClientCfg.video.0.resolutionX = Int32(SettingsHandler.resolution.width)
		parsecClientCfg.video.0.resolutionY = Int32(SettingsHandler.resolution.height)
		parsecClientCfg.video.0.decoderCompatibility = SettingsHandler.decoderCompatibility
		parsecClientCfg.video.0.decoderH265 = SettingsHandler.decoder == .h265

		parsecClientCfg.video.1.decoderIndex = 1
		parsecClientCfg.video.1.resolutionX = Int32(SettingsHandler.resolution.width)
		parsecClientCfg.video.1.resolutionY = Int32(SettingsHandler.resolution.height)
		parsecClientCfg.video.1.decoderCompatibility = SettingsHandler.decoderCompatibility
		parsecClientCfg.video.1.decoderH265 = SettingsHandler.decoder == .h265

		parsecClientCfg.mediaContainer = 0
		parsecClientCfg.protocol = 1
		//parsecClientCfg.secret = ""
		parsecClientCfg.pngCursor = false

		self.startBackgroundTask()
		
		let status = ParsecClientConnect(_parsec, &parsecClientCfg, NetworkHandler.clinfo?.session_id, peerID)
		
		if status == PARSEC_OK || status == PARSEC_CONNECTING {
			ParsecBackgroundManager.shared.connectionDidStart(peerId: peerID)
		}

		return status
	}
	
	func disconnect() {

		audio_clear(&_audio)
		ParsecClientDisconnect(_parsec)
		backgroundTaskRunning = false
		// Reset so the next case-11 echo after a reconnect re-pushes our
		// desired resolution instead of clobbering it with whatever the host
		// happens to advertise.
		didSetResolution = false
		didRestoreSavedDisplay = false

		// Give the two `while backgroundTaskRunning` loops in
		// startBackgroundTask() one full poll-timeout to notice the flag
		// flip and exit. Without this drain, a fast reconnect() can spawn
		// fresh loops while the old ones are still inside ParsecClientPollAudio
		// / ParsecClientPollEvents, briefly doubling the poll rate and
		// causing audio glitches.
		Thread.sleep(forTimeInterval: 0.02)

		ParsecBackgroundManager.shared.connectionDidEnd()
	}
	
	func getStatus() -> ParsecStatus {
		
		return ParsecClientGetStatus(_parsec, nil)
	}
	
	func getStatusEx(_ pcs:inout ParsecClientStatus) -> ParsecStatus {
		let ans = ParsecClientGetStatus(_parsec, &pcs)
		self.hostHeight = Float(pcs.decoder.0.height)
		self.hostWidth = Float(pcs.decoder.0.width)

		return ans;
	}
	
	func setFrame(_ width:CGFloat, _ height:CGFloat, _ scale: CGFloat) {
		
		ParsecClientSetDimensions(_parsec, UInt8(DEFAULT_STREAM), UInt32(width), UInt32(height), Float(scale))
		
		clientWidth = Float(width)
		clientHeight = Float(height)
		withMouseInfo {
			$0.mouseX = Int32(width / 2)
			$0.mouseY = Int32(height / 2)
		}
	}
	
	// timeout in ms, 16 == 60 FPS, 8 == 120 FPS, etc.
	func renderGLFrame(timeout: UInt32 = 16) {
		
		ParsecClientGLRenderFrame(_parsec, UInt8(DEFAULT_STREAM), nil, nil, timeout)
	}
	
	/*static func renderMetalFrame(_ queue:inout MTLCommandQueue, _ texturePtr: UnsafeMutablePointer<UnsafeMutableRawPointer?>, timeout: UInt32 = 16) // timeout in ms, 16 == 60 FPS, 8 == 120 FPS, etc.
	 {
	 ParsecClientMetalRenderFrame(_parsec, UInt8(DEFAULT_STREAM), &queue, texturePtr, nil, nil, timeout)
	 }*/
	
	func pollAudio(timeout: UInt32 = 16) // timeout in ms, 16 == 60 FPS, 8 == 120 FPS, etc.
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
					// Restore the saved display ONCE per session. The host
					// can re-advertise its display list multiple times mid-
					// stream (sleep/wake, display hot-plug); without this
					// gate, every echo would re-fire updateHostVideoConfig
					// and cause a brief re-encode flicker.
					if !self.didRestoreSavedDisplay {
						self.didRestoreSavedDisplay = true
						let savedId = SettingsHandler.savedDisplayOutput
						let savedName = SettingsHandler.savedDisplayName
						guard !savedId.isEmpty || !savedName.isEmpty else { return }
						// Match by id first (stable when the host reports
						// consistent display ids across sessions). Fall
						// back to name+adapter match so a display that
						// changed id between connects (Parsec sometimes
						// regenerates them) is still found.
						let match = config.first(where: { $0.id == savedId })
							?? config.first(where: { !savedName.isEmpty && "\($0.name) \($0.adapterName)" == savedName })
						if let match = match {
							DataManager.model.output = match.id
							SettingsHandler.savedDisplayOutput = match.id // re-sync if id rolled
							self.updateHostVideoConfig()
						}
					}
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
		// hidden / relative always track the latest event; capture the prior
		// hidden state in the same locked section to decide the reposition.
		let prevHidden = withMouseInfo { info -> Bool in
			let prev = info.cursorHidden
			info.cursorHidden = event.cursor.hidden
			info.mousePositionRelative = event.cursor.relative
			return prev
		}

		guard event.cursor.imageUpdate || !getFirstCursor else { return }
		getFirstCursor = true

		let pointer = ParsecGetBuffer(_parsec, event.key)
		if pointer == nil {
			return
		}

		let size = event.cursor.size
		let width = event.cursor.width
		let height = event.cursor.height

		// Build the CGImage BEFORE taking the lock — image construction is the
		// expensive part and must not run while the snapshot getter is blocked.
		let elmentLength: Int = 4
		let render: CGColorRenderingIntent = CGColorRenderingIntent.defaultIntent
		let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
		let bitmapInfo: CGBitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
		let providerRef: CGDataProvider? = CGDataProvider(data: NSData(bytes: pointer, length: Int(size)))
		let cgimage: CGImage? = CGImage(width: Int(width), height: Int(height), bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: Int(width) * elmentLength, space: rgbColorSpace, bitmapInfo: bitmapInfo, provider: providerRef!, decode: nil, shouldInterpolate: true, intent: render)
		ParsecFree(pointer)

		withMouseInfo { info in
			info.cursorWidth = Int(width)
			info.cursorHeight = Int(height)
			if prevHidden && !event.cursor.hidden {
				info.mouseX = Int32(event.cursor.positionX)
				info.mouseY = Int32(event.cursor.positionY)
			}
			info.cursorHotX = Int(event.cursor.hotX)
			info.cursorHotY = Int(event.cursor.hotY)
			if let cgimage = cgimage {
				info.cursorImg = cgimage
			}
		}
	}
	
	func setMuted(_ muted: Bool) {
		audio_mute(muted, _audioPtr)
	}
	
	func applyConfig() {

		var parsecClientCfg = ParsecClientConfig()

		// Preserve the user's chosen resolution. The previous code hardcoded
		// 0/0 (= "use host default"), which silently overwrote whatever
		// connect() had set, making it look like the in-overlay Resolution
		// picker did nothing.
		parsecClientCfg.video.0.decoderIndex = 1
		parsecClientCfg.video.0.resolutionX = Int32(SettingsHandler.resolution.width)
		parsecClientCfg.video.0.resolutionY = Int32(SettingsHandler.resolution.height)
		parsecClientCfg.video.0.decoderCompatibility = SettingsHandler.decoderCompatibility
		parsecClientCfg.video.0.decoderH265 = SettingsHandler.decoder == .h265

		parsecClientCfg.video.1.decoderIndex = 1
		parsecClientCfg.video.1.resolutionX = Int32(SettingsHandler.resolution.width)
		parsecClientCfg.video.1.resolutionY = Int32(SettingsHandler.resolution.height)
		parsecClientCfg.video.1.decoderCompatibility = SettingsHandler.decoderCompatibility
		parsecClientCfg.video.1.decoderH265 = SettingsHandler.decoder == .h265

		parsecClientCfg.mediaContainer = mediaContainer
		parsecClientCfg.protocol = netProtocol
		//parsecClientCfg.secret = ""
		parsecClientCfg.pngCursor = pngCursor

		ParsecClientSetConfig(_parsec, &parsecClientCfg);
	}
	
	// All outgoing-input methods gate on backgroundTaskRunning. False means
	// we're between an explicit disconnect and the next connect (including
	// the gap inside changeResolution's reconnect dance) — sending into a
	// disconnected SDK is at best a wasted message and at worst a NULL deref
	// inside ParsecClientSendMessage.

	func sendMouseMessage(_ button:ParsecMouseButton, _ x:Int32, _ y:Int32, _ pressed: Bool)
	{
		guard backgroundTaskRunning else { return }
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
		guard backgroundTaskRunning else { return }
		var buttonMessage = ParsecMessage()
		buttonMessage.type = MESSAGE_MOUSE_BUTTON
		buttonMessage.mouseButton.button = button
		buttonMessage.mouseButton.pressed = pressed
		ParsecClientSendMessage(_parsec, &buttonMessage)
	}

	func sendMouseDelta(_ dx: Int32, _ dy: Int32) {
		guard backgroundTaskRunning else { return }
		// One atomic snapshot, then act on it — avoids two separate locked
		// reads racing a concurrent position write.
		let info = mouseInfo
		if info.mousePositionRelative {
			sendMouseRelativeMove(dx, dy)
		} else {
			sendMousePosition(info.mouseX + dx, info.mouseY + dy)
		}

	}
	static func clamp<T>(_ value: T, minValue: T, maxValue: T) -> T where T : Comparable {
		return min(max(value, minValue), maxValue)
	}

	// Swap GUI ↔ Ctrl scan codes when the user has flagged the host as
	// Windows. Mac-keyboard layout calls the modifier-row keys, left-to-right,
	// Control / Option / Cmd. On a Windows host the equivalents are
	// Ctrl / Alt / Win — but Win+C does nothing useful and Ctrl+C is copy.
	// Remapping at the scan-code layer means every consumer (UIKey path,
	// virtual keyboard, UIKeyCommand captured shortcuts) gets the swap with
	// no per-caller awareness.
	static func remapKeyForHostIfNeeded(_ code: ParsecKeycode) -> ParsecKeycode {
		guard SettingsHandler.windowsHostKeyboardRemap else { return code }
		switch code.rawValue {
		case 227: return ParsecKeycode(224)  // LGUI → LCTRL (Cmd → Ctrl)
		case 224: return ParsecKeycode(227)  // LCTRL → LGUI (Ctrl → Win)
		case 231: return ParsecKeycode(228)  // RGUI → RCTRL
		case 228: return ParsecKeycode(231)  // RCTRL → RGUI
		default: return code               // Shift / Alt / printable keys unchanged
		}
	}
	
	func sendMousePosition(_ x:Int32, _ y:Int32)
	{
		guard backgroundTaskRunning else { return }
		let cx = ParsecSDKBridge.clamp(x, minValue: 0, maxValue: Int32(self.clientWidth))
		let cy = ParsecSDKBridge.clamp(y, minValue: 0, maxValue: Int32(self.clientHeight))
		withMouseInfo {
			$0.mouseX = cx
			$0.mouseY = cy
		}
		var motionMessage = ParsecMessage()
		motionMessage.type = MESSAGE_MOUSE_MOTION
		motionMessage.mouseMotion.x = x
		motionMessage.mouseMotion.y = y
		ParsecClientSendMessage(_parsec, &motionMessage)
	}

	func sendMouseRelativeMove(_ dx:Int32, _ dy:Int32)
	{
		guard backgroundTaskRunning else { return }
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
		
		return (keyCode, useShift)
	}
	
	func sendVirtualKeyboardInput(text: String) {
		guard backgroundTaskRunning else { return }
		let (keyCode, useShift) = getKeyCodeByText(text: text)

		guard let keyCode else {
			return
		}
		let remapped = ParsecSDKBridge.remapKeyForHostIfNeeded(keyCode)
		var keyboardMessagePress = ParsecMessage()
		keyboardMessagePress.type = MESSAGE_KEYBOARD
		if !isVirtualShiftOn && useShift {
			keyboardMessagePress.keyboard = ParsecKeyboardMessage(code: KEY_LSHIFT, mod: MOD_NONE, pressed: true, __pad: (0,0,0))
			ParsecClientSendMessage(_parsec, &keyboardMessagePress)
		}
		keyboardMessagePress.keyboard = ParsecKeyboardMessage(code: remapped, mod: MOD_NONE, pressed: true, __pad: (0,0,0))
		ParsecClientSendMessage(_parsec, &keyboardMessagePress)

		// add release delay in case some games ignore instant key release
		DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) {
			// Re-check the gate inside the closure: a disconnect can land in
			// these 20 ms (matches the drain sleep in disconnect() exactly),
			// in which case we would otherwise fire ParsecClientSendMessage
			// against a torn-down client.
			guard self.backgroundTaskRunning else { return }
			keyboardMessagePress.keyboard = ParsecKeyboardMessage(code: remapped, mod: MOD_NONE, pressed: false, __pad: (0,0,0))
			if !self.isVirtualShiftOn && useShift {
				keyboardMessagePress.keyboard = ParsecKeyboardMessage(code: KEY_LSHIFT, mod: MOD_NONE, pressed: false, __pad: (0,0,0))
			}
			ParsecClientSendMessage(self._parsec, &keyboardMessagePress)
		}
	}
	
	func sendVirtualKeyboardInput(text: String, isOn: Bool) {
		guard backgroundTaskRunning else { return }
		let (keyCode, _) = getKeyCodeByText(text: text)

		guard let keyCode else {
			return
		}

		if keyCode.rawValue == 225 {
			isVirtualShiftOn = isOn
		}

		let remapped = ParsecSDKBridge.remapKeyForHostIfNeeded(keyCode)
		var keyboardMessagePress = ParsecMessage()
		keyboardMessagePress.type = MESSAGE_KEYBOARD
		keyboardMessagePress.keyboard.pressed = isOn
		keyboardMessagePress.keyboard.code = remapped
		ParsecClientSendMessage(_parsec, &keyboardMessagePress)

	}

	func sendKeyboardMessage(event:KeyBoardKeyEvent)
	{
		guard backgroundTaskRunning else { return }
		if event.input == nil {
			return
		}

		let rawCode = ParsecKeycode(UInt32(KeyCodeTranslators.uiKeyCodeToInt(key: event.input?.keyCode ?? UIKeyboardHIDUsage.keyboardErrorUndefined)))
		var keyboardMessagePress = ParsecMessage()
		keyboardMessagePress.type = MESSAGE_KEYBOARD
		keyboardMessagePress.keyboard.code = ParsecSDKBridge.remapKeyForHostIfNeeded(rawCode)
		keyboardMessagePress.keyboard.pressed = event.isPressBegin
		ParsecClientSendMessage(_parsec, &keyboardMessagePress)
	}
	
	func sendGameControllerButtonMessage(controllerId: UInt32, _ button:ParsecGamepadButton, pressed: Bool)
	{
		guard backgroundTaskRunning else { return }
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
		guard backgroundTaskRunning else { return }
	    var pmsg = ParsecMessage()
		pmsg.type = MESSAGE_GAMEPAD_AXIS
		pmsg.gamepadAxis.id = controllerId
		pmsg.gamepadAxis.axis = button
		pmsg.gamepadAxis.value = value
		ParsecClientSendMessage(_parsec, &pmsg)
	}
	
	func sendGameControllerUnplugMessage(controllerId: UInt32)
	{
		guard backgroundTaskRunning else { return }
	    var pmsg = ParsecMessage()
		pmsg.type = MESSAGE_GAMEPAD_UNPLUG;
		pmsg.gamepadUnplug.id = controllerId;
		ParsecClientSendMessage(_parsec, &pmsg)
	}
	
	func sendWheelMsg(x: Int32, y: Int32) {
		guard backgroundTaskRunning else { return }
		var pmsg = ParsecMessage()
		pmsg.type = MESSAGE_MOUSE_WHEEL;
		pmsg.mouseWheel.x = x
		pmsg.mouseWheel.y = y
		ParsecClientSendMessage(_parsec, &pmsg)
	}
	
	func startBackgroundTask(){
		// Scale poll timeout to the configured render fps so the audio and
		// event threads don't sit blocked inside the SDK longer than a
		// frame budget. On 120 Hz iPads that's 8 ms; on 60 Hz, 16 ms.
		let fps = SettingsHandler.preferredFramesPerSecond == 0
			? UIScreen.main.maximumFramesPerSecond
			: SettingsHandler.preferredFramesPerSecond
		let pollTimeout = UInt32(max(1000 / fps, 8))

		// Advance the generation and capture it for this pair of loops. Any
		// previously-spawned loop sees the bumped value and exits.
		pollGeneration &+= 1
		let generation = pollGeneration

		let item1 = DispatchWorkItem {
			while self.backgroundTaskRunning && self.pollGeneration == generation {
				self.pollAudio(timeout: pollTimeout)
			}
		}

		let item2 = DispatchWorkItem {
			while self.backgroundTaskRunning && self.pollGeneration == generation {
				self.pollEvent(timeout: pollTimeout)
			}
		}
		// .userInteractive is the right QoS for remote-desktop input/event
		// dispatch — these threads gate audio callbacks and cursor updates.
		// Previously used unspecified (.default) which sometimes coalesces
		// under system load.
		let pollQueue = DispatchQueue.global(qos: .userInteractive)
		pollQueue.async(execute: item1)
		pollQueue.async(execute: item2)
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
		// User reports: display switches needed two or three taps to actually
		// take effect. setVideoConfig is fire-and-forget; the host can drop
		// the message if its encoder is in the middle of a reset triggered
		// by a previous request. Re-send the same payload after 250 ms
		// (idempotent — same output reapplied is a no-op on the host).
		// Then ask the host to echo back its current config so case-11
		// confirms the switch landed.
		DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { [weak self] in
			guard let self = self, self.backgroundTaskRunning else { return }
			CParsec.sendUserData(type: .setVideoConfig, message: data)
		}
		DispatchQueue.global().asyncAfter(deadline: .now() + 0.45) { [weak self] in
			guard let self = self, self.backgroundTaskRunning else { return }
			let empty = "".data(using: .utf8)!
			CParsec.sendUserData(type: .getVideoConfig, message: empty)
		}
	}
}
