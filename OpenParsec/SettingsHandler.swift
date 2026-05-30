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
	// Non-linear acceleration applied on top of mouseSensitivity. 0 = pure
	// linear (fastest gestures travel the same per-pixel as slow ones); up
	// to 1.5 = strong macOS-style acceleration where fast flicks travel
	// further. Surfaced as a slider in Settings → Interactivity.
	@AppStorage("mouseAcceleration") public static var mouseAcceleration: Double = 0.0
	// Draw a local arrow cursor on top of the streamed video and skip
	// rendering the host's own cursor — the local one tracks input
	// immediately while the host's cursor visually lags by the network RTT.
	@AppStorage("localCursorOverlay") public static var localCursorOverlay: Bool = false
	@AppStorage("scrollSensitivity") public static var scrollSensitivity: Double = 1.0
	// When true (default), trackpad scroll direction matches what iPad/macOS
	// call "natural scrolling" — swipe down moves content down. Flip to false
	// if you want classic mouse-wheel direction.
	@AppStorage("naturalScrolling") public static var naturalScrolling: Bool = true
	// S03: client-side scroll inertia was removed (iPadOS provides native
	// scroll-deceleration events; the client tail double-applied them). The
	// scrollMomentum / scrollMomentumStrength settings are gone with it.
	// Best-effort iPadOS system-shortcut capture via UIKeyCommand registry
	// with .wantsPriorityOverSystemBehavior (iOS 15+). Catches Cmd+letter
	// combinations the iPad shell would otherwise eat. Cmd+Space, Cmd+H,
	// Globe key, and swipe-up gestures stay system-level — those cannot be
	// intercepted from a sandboxed iPad app.
	@AppStorage("captureSystemKeys") public static var captureSystemKeys: Bool = true
	// When streaming TO a Windows host from a Mac-style iPad keyboard, swap
	// the GUI ↔ Ctrl scan codes so Cmd+C (the iPad user's expectation)
	// arrives as Ctrl+C on the host, Ctrl+anything arrives as Win+anything,
	// and Opt stays Alt (it's the same physical key + same Windows mapping).
	@AppStorage("windowsHostKeyboardRemap") public static var windowsHostKeyboardRemap: Bool = false
	@AppStorage("noOverlay") public static var noOverlay: Bool = false
	// Q1: previously shared the "cursorScale" key with the Double cursorScale
	// above — a Bool write coerced cursorScale (false → 0 = invisible cursor)
	// and vice versa. Own key now; migrateLegacyStatusBarKeyIfNeeded() seeds it
	// and clamps any corrupted cursorScale on first launch after the upgrade.
	@AppStorage("hideStatusBar") public static var hideStatusBar: Bool = true
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

	// When true, pressing Ctrl+Shift *alone* (no other key in between) fires
	// Cmd+Space at the host — the macOS "switch input source" / Spotlight chord
	// the iPad shell otherwise swallows. Holding Ctrl+Shift and then pressing
	// any other key (e.g. Ctrl+Shift+Arrow to extend a selection) is forwarded
	// normally and does NOT fire the emulation. Off by default; intended for Mac
	// hosts. Not auto-gated on host OS yet because host-OS detection (S04) still
	// resolves to .unknown until the Int→OS mapping is discovered empirically —
	// so this stays a deliberate manual opt-in.
	@AppStorage("ctrlShiftEmulatesCmdSpace") public static var ctrlShiftEmulatesCmdSpace: Bool = false

	// When true, pressing a *bare* backtick/grave (`) — no Cmd/Ctrl/Alt/Shift —
	// fires Cmd+Space at the host instead of sending the grave scancode. This is
	// a manual language-switch macro: the physical Cmd+Space is swallowed by
	// iPadOS (Spotlight) and never reaches the host, but a backtick is an
	// ordinary key we can intercept and re-emit as host scancodes. Shift+`
	// (tilde) and Cmd+` are untouched because any modifier disqualifies the
	// remap. Off by default; turning it on means you can no longer type a literal
	// backtick into the host while connected. Intended for Mac hosts whose
	// "Select previous input source" / Spotlight is bound to ⌘Space.
	@AppStorage("backtickEmulatesCmdSpace") public static var backtickEmulatesCmdSpace: Bool = false

	@AppStorage("saveSessionSettings") public static var saveSessionSettings: Bool = true
	@AppStorage("savedZoomEnabled") public static var savedZoomEnabled: Bool = false
	@AppStorage("savedConstantFps") public static var savedConstantFps: Bool = false
	@AppStorage("savedMuted") public static var savedMuted: Bool = false
	// Remember which display the user picked last; restored on the next
	// connect once the host enumerates its displays (user-data event 12).
	// The id is the primary key; the name (e.g. "Built-in Retina Display ...")
	// is a fallback because Parsec sometimes regenerates display ids between
	// connects for the same physical display.
	@AppStorage("savedDisplayOutput") public static var savedDisplayOutput: String = ""
	@AppStorage("savedDisplayName") public static var savedDisplayName: String = ""

	// Q1 one-time migration. hideStatusBar used to (incorrectly) share the
	// "cursorScale" UserDefaults key, so the two settings corrupted each other.
	// On the first launch after the fix, seed the new "hideStatusBar" key with
	// its original default and clamp any cursorScale value that a Bool write
	// may have driven out of range (notably 0 = invisible cursor). Call once at
	// app launch, before any UI reads these values.
	static func migrateLegacyStatusBarKeyIfNeeded() {
		let defaults = UserDefaults.standard
		// Absence of the new key == migration not yet run.
		guard defaults.object(forKey: "hideStatusBar") == nil else { return }
		// The shared value can't be split back into two settings, so restore
		// the original hideStatusBar default (true) and sanitize cursorScale.
		defaults.set(true, forKey: "hideStatusBar")
		if defaults.object(forKey: "cursorScale") != nil {
			let raw = defaults.double(forKey: "cursorScale")
			let clamped = min(max(raw, 0.1), 4.0)
			if clamped != raw {
				defaults.set(clamped, forKey: "cursorScale")
			}
		}
	}

}
