import Foundation
import SwiftUI

final class SettingsStore: ObservableObject {
	static let shared = SettingsStore()
	private let defaults = UserDefaults.standard

	private init() {
		defaults.register(defaults: [
			"rendererChoice": RendererType.metal.rawValue,
			"resolution": ParsecResolution.client.rawValue,
			"bitrate": 0,
			"decoder": DecoderPref.h264.rawValue,
			"cursorMode": CursorMode.touchpad.rawValue,
			"cursorScale": 0.5,
			"mouseSensitivity": 1.0,
			"optionAsCommand": false,
			"menuSwipeEdge": MenuSwipeEdge.off.rawValue,
			"noOverlay": false,
			"hideStatusBar": true,
			"rightClickPosition": RightClickPosition.firstFinger.rawValue,
			"reverseScrollDirection": false,
			"scrollSensitivity": 1.5,
			"preferredFramesPerSecond": 60,
			"showKeyboardButton": true,
			"alwaysShowStatus": false,
			"enablePiP": false,
			"startMuted": false,
			"autoReconnectEnabled": true,
			"errorPrompts": false,
			"autoConnectOnLaunch": false,
			"savedZoomEnabled": false,
			"savedConstantFps": false
		])
		// values saved back when saving was off would now always apply
		if defaults.object(forKey: "saveSessionSettings") as? Bool == false {
			defaults.set(false, forKey: "savedZoomEnabled")
			defaults.set(false, forKey: "savedConstantFps")
		}
		defaults.removeObject(forKey: "saveSessionSettings")
	}

	private func store(_ value: Any, _ key: String) {
		objectWillChange.send()
		defaults.set(value, forKey: key)
	}

	var renderer: RendererType {
		get { RendererType(rawValue: defaults.integer(forKey: "rendererChoice")) ?? .metal }
		set { store(newValue.rawValue, "rendererChoice") }
	}

	var resolution: ParsecResolution {
		get { ParsecResolution(rawValue: defaults.string(forKey: "resolution") ?? "") ?? .client }
		set { store(newValue.rawValue, "resolution") }
	}

	var bitrate: Int {
		get { defaults.integer(forKey: "bitrate") }
		set { store(newValue, "bitrate") }
	}

	var decoder: DecoderPref {
		get { DecoderPref(rawValue: defaults.integer(forKey: "decoder")) ?? .h264 }
		set { store(newValue.rawValue, "decoder") }
	}

	var cursorMode: CursorMode {
		get { CursorMode(rawValue: defaults.integer(forKey: "cursorMode")) ?? .touchpad }
		set { store(newValue.rawValue, "cursorMode") }
	}

	var cursorScale: Double {
		get { defaults.double(forKey: "cursorScale") }
		set { store(newValue, "cursorScale") }
	}

	var mouseSensitivity: Double {
		get { defaults.double(forKey: "mouseSensitivity") }
		set { store(newValue, "mouseSensitivity") }
	}

	var optionAsCommand: Bool {
		get { defaults.bool(forKey: "optionAsCommand") }
		set { store(newValue, "optionAsCommand") }
	}

	var menuSwipeEdge: MenuSwipeEdge {
		get { MenuSwipeEdge(rawValue: defaults.integer(forKey: "menuSwipeEdge")) ?? .off }
		set { store(newValue.rawValue, "menuSwipeEdge") }
	}

	var noOverlay: Bool {
		get { defaults.bool(forKey: "noOverlay") }
		set { store(newValue, "noOverlay") }
	}

	var hideStatusBar: Bool {
		get { defaults.bool(forKey: "hideStatusBar") }
		set { store(newValue, "hideStatusBar") }
	}

	var rightClickPosition: RightClickPosition {
		get { RightClickPosition(rawValue: defaults.integer(forKey: "rightClickPosition")) ?? .firstFinger }
		set { store(newValue.rawValue, "rightClickPosition") }
	}

	var reverseScrollDirection: Bool {
		get { defaults.bool(forKey: "reverseScrollDirection") }
		set { store(newValue, "reverseScrollDirection") }
	}

	var scrollSensitivity: Double {
		get { defaults.double(forKey: "scrollSensitivity") }
		set { store(newValue, "scrollSensitivity") }
	}

	var preferredFramesPerSecond: Int { // 0 = use device max (ProMotion)
		get { defaults.integer(forKey: "preferredFramesPerSecond") }
		set { store(newValue, "preferredFramesPerSecond") }
	}

	var showKeyboardButton: Bool {
		get { defaults.bool(forKey: "showKeyboardButton") }
		set { store(newValue, "showKeyboardButton") }
	}

	var alwaysShowStatus: Bool {
		get { defaults.bool(forKey: "alwaysShowStatus") }
		set { store(newValue, "alwaysShowStatus") }
	}

	var enablePiP: Bool {
		get { defaults.bool(forKey: "enablePiP") }
		set { store(newValue, "enablePiP") }
	}

	var startMuted: Bool {
		get { defaults.bool(forKey: "startMuted") }
		set { store(newValue, "startMuted") }
	}

	var autoReconnect: Bool {
		get { defaults.bool(forKey: "autoReconnectEnabled") }
		set { store(newValue, "autoReconnectEnabled") }
	}

	var errorPrompts: Bool {
		get { defaults.bool(forKey: "errorPrompts") }
		set { store(newValue, "errorPrompts") }
	}

	var autoConnectOnLaunch: Bool {
		get { defaults.bool(forKey: "autoConnectOnLaunch") }
		set { store(newValue, "autoConnectOnLaunch") }
	}

	var zoomEnabled: Bool {
		get { defaults.bool(forKey: "savedZoomEnabled") }
		set { store(newValue, "savedZoomEnabled") }
	}

	var constantFps: Bool {
		get { defaults.bool(forKey: "savedConstantFps") }
		set { store(newValue, "savedConstantFps") }
	}
}

struct SettingsHandler {
	static var renderer: RendererType { get { SettingsStore.shared.renderer } set { SettingsStore.shared.renderer = newValue } }
	static var resolution: ParsecResolution { get { SettingsStore.shared.resolution } set { SettingsStore.shared.resolution = newValue } }
	static var bitrate: Int { get { SettingsStore.shared.bitrate } set { SettingsStore.shared.bitrate = newValue } }
	static var decoder: DecoderPref { get { SettingsStore.shared.decoder } set { SettingsStore.shared.decoder = newValue } }
	static var cursorMode: CursorMode { get { SettingsStore.shared.cursorMode } set { SettingsStore.shared.cursorMode = newValue } }
	static var cursorScale: Double { get { SettingsStore.shared.cursorScale } set { SettingsStore.shared.cursorScale = newValue } }
	static var mouseSensitivity: Double { get { SettingsStore.shared.mouseSensitivity } set { SettingsStore.shared.mouseSensitivity = newValue } }
	static var optionAsCommand: Bool { get { SettingsStore.shared.optionAsCommand } set { SettingsStore.shared.optionAsCommand = newValue } }
	static var menuSwipeEdge: MenuSwipeEdge { get { SettingsStore.shared.menuSwipeEdge } set { SettingsStore.shared.menuSwipeEdge = newValue } }
	static var noOverlay: Bool { get { SettingsStore.shared.noOverlay } set { SettingsStore.shared.noOverlay = newValue } }
	static var hideStatusBar: Bool { get { SettingsStore.shared.hideStatusBar } set { SettingsStore.shared.hideStatusBar = newValue } }
	static var rightClickPosition: RightClickPosition { get { SettingsStore.shared.rightClickPosition } set { SettingsStore.shared.rightClickPosition = newValue } }
	static var reverseScrollDirection: Bool { get { SettingsStore.shared.reverseScrollDirection } set { SettingsStore.shared.reverseScrollDirection = newValue } }
	static var scrollSensitivity: Double { get { SettingsStore.shared.scrollSensitivity } set { SettingsStore.shared.scrollSensitivity = newValue } }
	static var preferredFramesPerSecond: Int { get { SettingsStore.shared.preferredFramesPerSecond } set { SettingsStore.shared.preferredFramesPerSecond = newValue } }
	static var showKeyboardButton: Bool { get { SettingsStore.shared.showKeyboardButton } set { SettingsStore.shared.showKeyboardButton = newValue } }
	static var alwaysShowStatus: Bool { get { SettingsStore.shared.alwaysShowStatus } set { SettingsStore.shared.alwaysShowStatus = newValue } }
	static var enablePiP: Bool { get { SettingsStore.shared.enablePiP } set { SettingsStore.shared.enablePiP = newValue } }
	static var startMuted: Bool { get { SettingsStore.shared.startMuted } set { SettingsStore.shared.startMuted = newValue } }
	static var autoReconnect: Bool { get { SettingsStore.shared.autoReconnect } set { SettingsStore.shared.autoReconnect = newValue } }
	static var errorPrompts: Bool { get { SettingsStore.shared.errorPrompts } set { SettingsStore.shared.errorPrompts = newValue } }
	static var autoConnectOnLaunch: Bool { get { SettingsStore.shared.autoConnectOnLaunch } set { SettingsStore.shared.autoConnectOnLaunch = newValue } }
	static var zoomEnabled: Bool { get { SettingsStore.shared.zoomEnabled } set { SettingsStore.shared.zoomEnabled = newValue } }
	static var constantFps: Bool { get { SettingsStore.shared.constantFps } set { SettingsStore.shared.constantFps = newValue } }
}
