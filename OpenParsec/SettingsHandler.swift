import Foundation
import SwiftUI

struct SettingsHandler {
	//public static var renderer:RendererType = .opengl
	@AppStorage("resolution") public static var resolution: ParsecResolution = .client
	@AppStorage("bitrate") public static var bitrate: Int = 0
	@AppStorage("decoder") public static var decoder: DecoderPref = .h264
	@AppStorage("cursorMode") public static var cursorMode: CursorMode = .touchpad
	@AppStorage("cursorScale") public static var cursorScale: Double = 0.5
	@AppStorage("mouseSensitivity") public static var mouseSensitivity: Double = 1.0
	@AppStorage("noOverlay") public static var noOverlay: Bool = false
	@AppStorage("cursorScale") public static var hideStatusBar: Bool = true
	@AppStorage("rightClickPosition") public static var rightClickPosition: RightClickPosition = .firstFinger
	@AppStorage("preferredFramesPerSecond") public static var preferredFramesPerSecond: Int = 60 // 0 = use device max (ProMotion)
	@AppStorage("decoderCompatibility") public static var decoderCompatibility: Bool = false // Enable for stutter issues on some devices
	@AppStorage("showKeyboardButton") public static var showKeyboardButton: Bool = true
	@AppStorage("alwaysShowStatus") public static var alwaysShowStatus: Bool = false

	@AppStorage("saveSessionSettings") public static var saveSessionSettings: Bool = true
	@AppStorage("savedZoomEnabled") public static var savedZoomEnabled: Bool = false
	@AppStorage("savedConstantFps") public static var savedConstantFps: Bool = false
	@AppStorage("savedMuted") public static var savedMuted: Bool = false

}
