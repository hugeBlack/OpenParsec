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
	// Draw a local arrow cursor on top of the streamed video and skip
	// rendering the host's own cursor — the local one tracks input
	// immediately while the host's cursor visually lags by the network RTT.
	@AppStorage("localCursorOverlay") public static var localCursorOverlay: Bool = false
	@AppStorage("scrollSensitivity") public static var scrollSensitivity: Double = 1.0
	// When true (default), trackpad scroll direction matches what iPad/macOS
	// call "natural scrolling" — swipe down moves content down. Flip to false
	// if you want classic mouse-wheel direction.
	@AppStorage("naturalScrolling") public static var naturalScrolling: Bool = true
	// Inertia after the finger leaves the trackpad: CADisplayLink keeps
	// firing wheel messages with exponential decay, so scrolls don't stop
	// dead the moment you let go.
	@AppStorage("scrollMomentum") public static var scrollMomentum: Bool = true
	// 0.0 ≈ ~150 ms of glide; 1.0 ≈ ~2 s of long glide. Linear mapping into
	// a per-frame decay multiplier in startScrollMomentum.
	@AppStorage("scrollMomentumStrength") public static var scrollMomentumStrength: Double = 0.5
	// Best-effort iPadOS system-shortcut capture via UIKeyCommand registry
	// with .wantsPriorityOverSystemBehavior (iOS 15+). Catches Cmd+letter
	// combinations the iPad shell would otherwise eat. Cmd+Space, Cmd+H,
	// Globe key, and swipe-up gestures stay system-level — those cannot be
	// intercepted from a sandboxed iPad app.
	@AppStorage("captureSystemKeys") public static var captureSystemKeys: Bool = true
	@AppStorage("noOverlay") public static var noOverlay: Bool = false
	@AppStorage("cursorScale") public static var hideStatusBar: Bool = true
	@AppStorage("rightClickPosition") public static var rightClickPosition: RightClickPosition = .firstFinger
	@AppStorage("preferredFramesPerSecond") public static var preferredFramesPerSecond: Int = 0 // 0 = use device max (ProMotion). Default was 60 — that capped 120 Hz iPads at half their refresh, doubling glass-to-glass present latency.
	@AppStorage("decoderCompatibility") public static var decoderCompatibility: Bool = false // Enable for stutter issues on some devices
	// Umbrella switch — when true, suppresses the artificial 20 ms / 60 ms
	// holds on the captured-key path and the unconditional PiP capture in
	// the render loop. Surfaced as a single Settings toggle that also flips
	// FPS / decoder / overlay / momentum defaults via onChange.
	@AppStorage("lowLatencyMode") public static var lowLatencyMode: Bool = false
	@AppStorage("showKeyboardButton") public static var showKeyboardButton: Bool = true

	// When the iPad's hardware keyboard layout changes (Caps Lock / Ctrl+Space
	// on Magic Keyboard), fire a hotkey at the host so the host's input source
	// switches in lock-step. Eliminates the "wrong characters after switching
	// language" problem people hit on iPad ↔ Mac Parsec sessions.
	@AppStorage("syncKeyboardLayout") public static var syncKeyboardLayout: Bool = true
	@AppStorage("layoutSyncHotkey") public static var layoutSyncHotkey: LayoutSyncHotkey = .ctrlSpace

	@AppStorage("saveSessionSettings") public static var saveSessionSettings: Bool = true
	@AppStorage("savedZoomEnabled") public static var savedZoomEnabled: Bool = false
	@AppStorage("savedConstantFps") public static var savedConstantFps: Bool = false
	@AppStorage("savedMuted") public static var savedMuted: Bool = false
	// Remember which display the user picked last; restored on the next
	// connect once the host enumerates its displays (user-data event 12).
	@AppStorage("savedDisplayOutput") public static var savedDisplayOutput: String = ""

}
