# OpenParsec — Trackpad / Keyboard / Input Overhaul — Engineering Handoff

> Hand-off document for a reviewing AI agent. Self-contained. Covers every change on
> branch `fix/trackpad-input`, the rationale, the current state, user-reported issues,
> outstanding bugs, and host-side limitations that cannot be fixed client-side.
> Last updated at commit `fc6776c`.

---

## 0. TL;DR for the reviewing agent

- **Repo:** `2extndd/OpenParsec` (fork of `hugeBlack/OpenParsec`). iPad app, Swift/SwiftUI + UIKit, Parsec SDK (binary `ParsecSDK.framework`, vendored, no headers in tree). Deployment target **iOS 14.0**.
- **Branch:** `fix/trackpad-input`, 17 commits ahead of `cd155f8` (fork's `main`). HEAD = `fc6776c`.
- **What it does:** fixes Magic Keyboard trackpad input (cursor lag + choppy scroll), adds Mac↔iPad keyboard-layout sync, local cursor overlay, mouse acceleration, Windows-host key remap, in-session resolution change, display persistence, a Low-Latency mode, and a crash reporter.
- **Build/CI:** GitHub Actions (`.github/workflows/build.yml`) on `macos-latest`, Xcode 26.2, produces `OpenParsec.ipa`. CI is currently green at HEAD.
- **The user tests on a real iPad M4 + Magic Keyboard, streaming to an M3 MacBook Pro (and sometimes a Windows host).** No Mac/Xcode locally → all builds go through CI; .ipa is sideloaded via Scarlet/eSign (unsigned variant) or AltStore (ad-hoc).
- **Your job (suggested):** verify correctness of the input pipeline, concurrency safety, and the host-protocol assumptions. Highest-risk areas are flagged in §6.

---

## 1. Project & repo context

OpenParsec is an open-source Parsec client for iPad. Parsec streams a host desktop (Mac/Windows/Linux) to the client over a low-latency UDP protocol (BUD). The client sends input (mouse/keyboard/gamepad) via `ParsecClientSendMessage` and receives video frames + a separately-streamed cursor image + user-data events.

Key architectural facts the reviewer must hold:

- **`CParsec`** (`CParsec.swift`) is a static facade over **`ParsecSDKBridge`** (`ParsecSDKBridge.swift`), a singleton (`CParsec.parsecImpl`) that lives for the whole process. State on the bridge (`backgroundTaskRunning`, `didSetResolution`, `didRestoreSavedDisplay`, `mouseInfo`) persists across connect/disconnect cycles.
- **`ParsecViewController`** (`ParsecViewController.swift`, ~1500 lines now) owns the GLKView render surface, all gesture recognizers, the keyboard pipeline, the local cursor overlay, and language sync. It is **persisted across SwiftUI updates** by `ParsecSession` (an `ObservableObject` holding the VC) — see the comment in `ParsecView.swift`. Do not assume it is recreated per-connection.
- **`ParsecView`** (`ParsecView.swift`) is the SwiftUI layer: the in-stream overlay menu (Resolution / Bitrate / Display / Mute / Keyboard / Zoom), the status bar poller (`ParsecStatusBar`), and the connection lifecycle.
- **Input only flows on the main thread** for touch/gesture paths. The **GCMouse / GCController** path (`GameController.swift`) fires on GameController's *private background queue* — this is the source of a class of threading bugs (see §3.8, §6).
- Parsec's iOS SDK keyboard input is **scancode-only** (`MESSAGE_KEYBOARD` + `ParsecKeycode`). There is **no Unicode/text message**. This drove the design of language sync (§3.3) and Windows remap (§3.5).

---

## 2. Branch state & commit timeline

`git log --oneline cd155f8..HEAD` (oldest → newest):

| SHA | Title | Theme |
|-----|-------|-------|
| `8277e0d` | Fix trackpad input lag and choppy 2-finger scroll | Bug 1 + Bug 2 baseline |
| `c6f9eb2` | Add Mac↔iPad keyboard layout sync via host hotkey | Language sync |
| `96ae81e` | Trackpad polish: natural scroll, inertia, sensitivity + key capture | Scroll polish + UIKeyCommand |
| `5d2bf2d` | Fix keyboard toolbar regression + scroll inertia + Mac-first labels | Regression fix |
| `5464629` | Persist last-used display + in-session resolution change | Display + resolution |
| `54a96d0` | ci: retrigger workflow | empty commit |
| `de86645` | Apply audit P0/P1/P2/P3 | Big audit batch |
| `4ad1d42` | Fix build: ParsecStatusBar init + local cursor overlay | Build fix + overlay |
| `0bc675d` | Windows host key remap + 4 audit-found bugfixes | Windows remap |
| `2b57e24` | v4 — real bugfixes from user testing | Scroll dir, cursor, reconnect, display |
| `af5261b` | v4 follow-up: loosen language-sync gates + lower inertia threshold | Tuning |
| `aca422b` | Add Mac Ctrl+Shift hotkey + adjustable mouse acceleration | Features (introduced a build break) |
| `fc8357f` | Fix scroll inertia tail — threshold + decay + touchesBegan gate | Inertia tuning |
| `5d31035` | Fix Resolution-menu crash, display persistence, display-switch debounce | Crash + display |
| `041c789` | Fix build: actually add @AppStorage mouseAcceleration | Build fix |
| `e924473` | GCMouse: move local cursor, fix wheel direction, fix x/y wheel swap | External mouse |
| `fc6776c` | Fix GCMouse off-main crash + crash reporter + CADisplayLink deinit | Crash fixes |

**8 files changed, ~1316 insertions / 72 deletions.** Heaviest: `ParsecViewController.swift` (~827 lines added).

> Note for the reviewer: several commits fixed build breaks introduced by earlier commits in the same series (`aca422b`→`041c789`, `5d2bf2d`'s `inputAccessoryView` read-only override→`4ad1d42`). The series was authored without a local compiler — only CI validated. Treat the *final* state at `fc6776c` as the truth; intermediate commits may contain code that was later corrected.

---

## 3. Every change, by subsystem

### 3.1 Trackpad cursor lag — Bug 1 (issue #47)

**Symptom:** cursor in the stream lagged/juddered while moving a finger on the Magic Keyboard trackpad.

**Root cause:** the main `panGestureRecognizer` had no `allowedTouchTypes` filter, so it ingested `.indirectPointer` UITouches (iPad trackpad/pointer, raw type 3). `UIPanGestureRecognizer` imposes a small movement threshold before `.began` and re-arms its state machine between strokes; at the per-frame trackpad event rate that produces visible stickiness.

**Fix (`ParsecViewController.swift`, `viewDidLoad`):**
- `panGestureRecognizer.allowedTouchTypes = [NSNumber(.direct.rawValue), NSNumber(.pencil.rawValue)]` — excludes `.indirectPointer`.
- Added `override func touchesMoved(...)` handling `.indirectPointer` touches directly via `preciseLocation(in:) - precisePreviousLocation(in:)`, sub-pixel accumulation through `accumulatedDeltaX/Y`. `cursorMode == .direct` → `sendMousePosition`; otherwise `sendMouseDelta`.
- `touchesBegan` resets accumulators on `.indirectPointer`; `touchesEnded`/`touchesCancelled` too.
- `prefersPointerLocked = true` (pre-existing) is what makes iPad deliver trackpad motion as `.indirectPointer` touches.

### 3.2 Trackpad 2-finger scroll + inertia — Bug 2

**Symptom:** choppy, stepped 2-finger scroll; later "no inertia at all".

**Root cause(s):**
- Original 2-finger branch used `velocity(in:)/20` → large irregular wheel deltas.
- Later inertia attempt had a stop threshold (`0.5` pts/frame) that killed the glide in ~270 ms.
- Scroll accumulator used `Int32()` truncation → sub-pixel ticks swallowed.
- `touchesBegan` killed momentum on every touch incl. `.indirectPointer`.

**Fix (`ParsecViewController.swift`):**
- Dedicated `UIPanGestureRecognizer` with `allowedScrollTypesMask = .all`, `maximumNumberOfTouches = 0` → only scroll-wheel/trackpad-scroll events. Handler `handleTrackpadScroll` uses `translation(in:)` deltas.
- Scroll accumulator now `.rounded(.toNearestOrAwayFromZero)`.
- Peak-velocity tracking during `.changed` (the recognizer's `velocity` is decayed to ~0 by iPad's own deceleration before `.ended`); peak reset only after a >1.0 s gap.
- Momentum via `CADisplayLink`: stop threshold `0.05` pts/frame, decay `0.90 + 0.095*strength` (strength 0..1 from `scrollMomentumStrength`).
- `touchesBegan` kills momentum only on `.direct`/`.pencil`.
- `naturalScrolling ? +1 : -1` direction sign (ON = no client-side invert, matching macOS default Natural Scrolling).

> **Reviewer caution (§6):** the "best-practices" research concluded iPadOS auto-synthesizes momentum phases on the pan recognizer, and apps like Moonlight do **not** implement client-side inertia. The current code does client-side `CADisplayLink` inertia. This works but is non-canonical; a future refactor may remove it. Verify the current decay parameters don't double-apply on top of iPad's own deceleration tail.

### 3.3 Mac↔iPad keyboard layout sync

**Goal:** when the user toggles the iPad's hardware-keyboard input language (Caps Lock / Ctrl+Space), the host's input source should follow.

**Constraint:** Parsec iOS SDK is scancode-only — no way to send composed Unicode. So we cannot bypass host layout; instead we fire a configurable hotkey at the host to make *it* switch.

**Mechanics (`ParsecViewController.swift`, `LanguageSyncCoordinator` + `LanguageSyncTextField`):**
- A 1×1, alpha-0 `LanguageSyncTextField` (UITextField subclass) is added to the view and made first responder. Needed because `UITextInputMode.currentInputModeDidChangeNotification` only fires when a text-input first responder exists.
- The field installs an empty `inputView` (suppress soft keyboard) and an empty non-nil `inputAccessoryView` (halt the responder-chain walk so the VC's keyboard toolbar does NOT appear by default — this was a regression fixed in `5d2bf2d`).
- The field forwards `pressesBegan/Ended/Changed/Cancelled` to the VC **without calling `super`** — hardware-keyboard scancodes keep flowing through the existing `pressesBegan` pipeline (same trick Moonlight uses).
- On a real language change, `sendLayoutSyncHotkey()` fires the configured chord via `CParsec.sendVirtualKeyboardInput`. Options: Ctrl+Space (default, macOS), Ctrl+Shift, Cmd+Space, Opt+Space, Alt+Shift (Windows), Off.
- Coordinator yields FR before the VC becomes FR (soft keyboard via 3-finger tap / button) and reclaims after.

> **Reviewer caution (§6):** the host only switches if it has the matching shortcut bound (macOS Sequoia default for "Select previous input source" is NOT Ctrl+Space). This is the dominant reason the user perceives "sync doesn't work" — it is a host-config issue, not necessarily a client bug. Also verify: (a) hidden field reliably reclaims FR after the soft keyboard is dismissed via OS routes that bypass `setKeyboardVisible(false)`; (b) the initial-seed logic doesn't fire a spurious hotkey at session start for users with 3+ layouts.

### 3.4 System-shortcut capture (UIKeyCommand registry)

**Goal:** let Cmd+letter shortcuts (Cmd+A/C/V/Z/S…) reach the host instead of being eaten by the iPad shell.

**Mechanics:** `override var keyCommands` returns a cached (`static var _cachedKeyCommands`) list of ~286 `UIKeyCommand`s — `(a–z, 0–9, punctuation) × (Cmd, Cmd+Shift, Cmd+Opt, Cmd+Ctrl, Opt, Opt+Shift)` + Cmd+(Tab/Space/Enter/`). On iOS 15+, `wantsPriorityOverSystemBehavior = true`. `handleCapturedKey` translates to a modifier-press / key / release scancode sequence (synchronous in Low-Latency mode, async +20/+60 ms otherwise).

**Hard limit:** Cmd+Space (Spotlight), Cmd+H, Cmd+Tab, Globe key, swipe-up — wired below the responder chain in SpringBoard; **no sandboxed app can intercept them**.

### 3.5 Windows host key remap

`SettingsHandler.windowsHostKeyboardRemap` (default off). When on, `ParsecSDKBridge.remapKeyForHostIfNeeded` swaps scancodes at the lowest layer (so every input path inherits it): `227 LGUI ↔ 224 LCTRL`, `231 RGUI ↔ 228 RCTRL`. Opt (226/230) and Shift (225/229) untouched. So Cmd+C on the iPad arrives as Ctrl+C on Windows.

### 3.6 Local cursor overlay

`SettingsHandler.localCursorOverlay` (default off). Draws a 13 pt iPadOS-style gray dot (`UIView` with cornerRadius/border/shadow) on `contentView`, tracked client-side from input deltas (no host RTT). When on, `updateImage` hides the host-streamed cursor (`u`). Seeded at `contentView.center` in `viewDidLayoutSubviews` (one-shot via `hasSeededLocalCursor`, because `viewDidLoad` sees zero bounds). Also useful as a workaround when a Windows host doesn't stream a cursor image at all.

### 3.7 Mouse acceleration

`SettingsHandler.mouseAcceleration` (0…1.5, default 0 = linear). `effectiveDeltaScale(rawDX:rawDY:)` returns `sensitivity + accel × (|delta|/5)` — fast flicks travel further. Applied in both `touchesMoved` (.indirectPointer) and `handlePanGesture` (touchscreen) touchpad branches.

> **Reviewer note:** best-practices research recommends linear + let the host apply its own curve. The acceleration here is a client-side curve stacked on top of the host's. Default 0 keeps it off; only opt-in users get the stacked curve.

### 3.8 External mouse (GCMouse) — `GameController.swift`

- `mouseMovedHandler` sends `sendMouseDelta`; **the local-cursor overlay update is dispatched to `DispatchQueue.main`** because GCMouse handlers run on GC's private background queue (touching `UIView.center` off-main traps — this was the crash fixed in `fc6776c`).
- Scroll: `yAxis`→y, `xAxis`→x (fixed a pre-existing x/y swap), with `naturalScrolling` sign + `scrollSensitivity`.
- Magic Keyboard trackpad does **not** enumerate as GCMouse — this path is only for external USB/BT mice.

### 3.9 In-session resolution change — `ParsecView.changeResolution`

**Constraint discovered:** Parsec host honours bitrate / FPS / output via `setVideoConfig` user-data, but **not resolution** — resolution is only read at `ParsecClientConnect`. So `changeResolution` does a clean disconnect + 600 ms gap + reconnect with new `ParsecClientConfig`.
- `isReconfiguring` guard prevents re-entry (spam-tap).
- Suppresses the status-bar disconnect alert during the gap; shows a "Switching resolution…" overlay; pauses GLKViewController (`isPaused = true`) so the last frame stays on screen instead of going black.
- Branches on `connect()` status — surfaces a real "Reconnect failed" alert if the host went away.

> **Reviewer caution (§7):** even at connect, a macOS host with a single physical display ignores small resolution requests (no virtual display). The user reported 1920×1080 in Settings is ignored — this is host behavior, not a client bug. Bitrate/H.265 are the working bandwidth levers.

### 3.10 Display selection persistence — `ParsecView.changeDisplay` + `ParsecSDKBridge` case 12

- `SettingsHandler.savedDisplayOutput` (id) + `savedDisplayName` (name+adapter fallback, because Parsec regenerates display ids across sessions).
- `handleUserDataEvent case 12` restores once per session (`didRestoreSavedDisplay`, reset in **both** `connect()` and `disconnect()` — the connect() reset was the key fix because reconnect paths bypass disconnect).
- `updateHostVideoConfig` resends the payload at +250 ms and a `getVideoConfig` at +450 ms — the host can drop a `setVideoConfig` mid-encoder-reset, which is why display switches needed multiple taps.

### 3.11 Low Latency Mode + latency reductions

`SettingsHandler.lowLatencyMode` toggle flips `preferredFramesPerSecond = 0` (device max), `decoder = h265`, `noOverlay = true`, and gates the 20/60 ms captured-key holds. Independently:
- `preferredFramesPerSecond` default changed 60 → **0** (was capping 120 Hz iPads at 60 → doubled present latency).
- `startBackgroundTask` poll timeout scales with FPS; QoS raised to `.userInteractive`.
- `ParsecGLKRenderer` gates PiP `captureFrame` on `isPiPActive || isStarting`.
- Mouse accumulator rounding (no event coalescing on slow drags).

### 3.12 Reconnect UX + send gating

- All `ParsecSDKBridge` send methods early-return on `!backgroundTaskRunning` (the gate is set true in `connect()`, false in `disconnect()`). Prevents `ParsecClientSendMessage` into a torn-down client during the reconnect gap.
- `disconnect()` sleeps 20 ms to drain the two poll loops before a fast reconnect spawns new ones.

### 3.13 Crash reporter — `AppDelegate.swift`

`CrashReporter.install()` sets `NSSetUncaughtExceptionHandler` + signal handlers (SIGABRT/SEGV/BUS/ILL/FPE/TRAP). Writes `Documents/last_crash.log` with a backtrace. On next launch: copies the log to `UIPasteboard` (syncs to a Mac via Universal Clipboard) and leaves the file in Documents (browsable via Files app — `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` added to Info.plist).

### 3.14 Concurrency / lifecycle hardening

- `ParsecViewController.deinit` invalidates `momentumDisplayLink` and stops `languageSync`.
- `CADisplayLink` always invalidated before a new one is created in `startScrollMomentum`.
- `keyCommands` cached (was rebuilding 286 objects per query).

---

## 4. New settings (`SettingsHandler.swift` @AppStorage keys)

| Key | Type | Default | Surfaced in SettingsView |
|-----|------|---------|--------------------------|
| `mouseAcceleration` | Double | 0.0 | Interactivity |
| `localCursorOverlay` | Bool | false | Interactivity |
| `scrollSensitivity` | Double | 1.0 | Interactivity |
| `naturalScrolling` | Bool | true | Interactivity |
| `scrollMomentum` | Bool | true | Interactivity |
| `scrollMomentumStrength` | Double | 0.5 | Interactivity |
| `captureSystemKeys` | Bool | true | Keyboard |
| `windowsHostKeyboardRemap` | Bool | false | Keyboard |
| `syncKeyboardLayout` | Bool | true | Keyboard |
| `layoutSyncHotkey` | LayoutSyncHotkey | .ctrlSpace | Keyboard |
| `lowLatencyMode` | Bool | false | Graphics |
| `preferredFramesPerSecond` | Int | **0** (was 60) | Graphics |
| `savedDisplayOutput` | String | "" | (internal) |
| `savedDisplayName` | String | "" | (internal) |

> **Pre-existing bug, NOT introduced here, but worth flagging:** `SettingsHandler.swift` reuses the key `"cursorScale"` for both `cursorScale: Double` AND `hideStatusBar: Bool`. They collide in UserDefaults. Left untouched to keep the diff scoped, but a reviewer may want to fix it (`hideStatusBar` should have its own key).

---

## 5. User feedback log (chronological, paraphrased)

1. ✅ Trackpad cursor lag fixed (confirmed by user).
2. "Screen moves when scrolling" → was the keyboard accessory toolbar showing by default (language-sync FR regression). Fixed (`5d2bf2d`).
3. Couldn't install .ipa ("integrity") → sideloader cert / bundle-id; solved by unsigned + unique-bundle-id variants.
4. Natural-scroll toggle inverted / didn't work → sign flipped (`2b57e24`); scroll accumulator rounding (`fc8357f`).
5. Local cursor "crooked, doesn't move" → SF-Symbol arrow → UIView dot, seed in `viewDidLayoutSubviews` (`2b57e24`).
6. Display selection not remembered → `didRestoreSavedDisplay` reset in connect (`5d31035`).
7. Resolution change → "Disconnected 20" → 600 ms reconnect gap (`2b57e24`/`5d31035`).
8. Resolution in Settings ignored → **host-side limitation** (§7), not fixed client-side.
9. Language switch doesn't work → loosened gates (`af5261b`); likely also host-shortcut config (§7).
10. Scroll "no inertia at all", "ragged with fingers on trackpad" → threshold/decay/touchesBegan fixes (`fc8357f`).
11. Resolution menu **crashes** → iOS 14.0–14.4 UIMenu `_ConditionalContent<Label,Text>` bug; fixed with HStack (`5d31035`).
12. Add Ctrl+Shift hotkey ✅ (`aca422b`). Add mouse acceleration ✅ (`aca422b`/`041c789`).
13. External mouse → cursor disappears / wrong wheel direction / no cursor on Windows → GCMouse fixes (`e924473`), off-main crash fix (`fc6776c`).
14. "App crashes during scroll / in general" → most likely the GCMouse off-main UIView mutation (`fc6776c`) and/or the iOS-14 Resolution-menu crash (`5d31035`). **Awaiting a crash log** from the new crash reporter to confirm.

---

## 6. Outstanding bugs / open code-review findings

A 5-angle code review was started but the finder sub-agents hit a session limit before completing. The reviewer-author's own confirmed/plausible findings:

1. **(FIXED `fc6776c`) [HIGH]** GCMouse `moveLocalCursor` off-main → UIView mutation crash.
2. **[MED, OPEN]** `updateHostVideoConfig` schedules 2 async resends per call. Rapid bitrate-slider drags stack many resends + `getVideoConfig` echoes; the case-11 echo writes `DataManager.model.bitrate` back to the host's reported value, which could snap the slider mid-drag. *Suggested fix:* debounce `updateHostVideoConfig` with a token/timestamp; skip resend if superseded.
3. **[MED, OPEN]** Language-sync hidden field may not reclaim first responder if the soft keyboard is dismissed via an OS route that doesn't call `setKeyboardVisible(false)`. *Verify:* does `keyboardWillHide` → `onKeyboardVisibilityChanged` → `setKeyboardVisible(false)` cover swipe-to-dismiss and hardware Esc?
4. **[LOW, OPEN]** Two identical external monitors collide on the name fallback (`changeDisplay`/case 12 name match picks first). Id-match runs first, so only matters when ids roll AND monitors are identical.
5. **[LOW, OPEN]** `scrollMomentumTick` and `handleTrackpadScroll` both touch `momentumVelocity*` — both on main, so not a true race, but confirm no path schedules the tick off-main.
6. **[LOW, OPEN]** Spurious Ctrl+Space at session start possible for 3+ layout users (initial-seed nil → first notification fires). Accepted trade-off; revisit if reported.
7. **[INFO]** Client-side scroll inertia is non-canonical (iPadOS provides momentum phases). Consider removing in favor of forwarding native momentum events (Moonlight approach). Would also remove the `scrollMomentumStrength` tuning surface.
8. **[INFO]** Mouse acceleration stacks a client curve on the host's curve. Default off mitigates.

---

## 7. Hard constraints — cannot be fixed client-side

1. **Resolution downscale on macOS hosts.** Parsec captures the physical display at native resolution; `parsecClientCfg.video.0.resolutionX/Y` is advisory and ignored without a virtual-display driver (BetterDummy etc.). Bitrate + H.265 are the real bandwidth levers.
2. **Hiding the cursor on the host's own physical display.** No client→host cursor message exists in the Parsec SDK; macOS draws the cursor before Parsec captures the frame. Requires a host-side helper (e.g. Hammerspoon `CGDisplayHideCursor` bound to a hotkey the iPad sends).
3. **System shortcuts** Cmd+Space / Cmd+H / Cmd+Tab / Globe / swipe-up — SpringBoard-level, not interceptable. Workaround: Windows-host remap, or Opt-based combos.
4. **Layout sync requires host config.** The host must have the chosen hotkey bound to "Select previous input source". macOS Sequoia does not bind Ctrl+Space by default.

---

## 8. Files reference map

| File | What changed |
|------|--------------|
| `OpenParsec/ParsecViewController.swift` | Trackpad cursor (`touchesMoved`), scroll + inertia (`handleTrackpadScroll`, momentum CADisplayLink), language sync (`LanguageSyncCoordinator`, `LanguageSyncTextField`), key capture (`keyCommands`, `handleCapturedKey`), local cursor overlay, mouse acceleration (`effectiveDeltaScale`), layout-sync hotkey sender, deinit. |
| `OpenParsec/ParsecSDKBridge.swift` | Send gates (`backgroundTaskRunning`), `remapKeyForHostIfNeeded`, `didRestoreSavedDisplay`, case-12 restore, `updateHostVideoConfig` resend, `connect`/`disconnect` state resets, poll-thread QoS/timeout, `applyConfig` resolution. |
| `OpenParsec/ParsecView.swift` | Resolution/Bitrate menu HStack fix, `changeResolution` reconnect flow, `changeDisplay` persist, `ParsecStatusBar` `isReconfiguring` gating + overlay. |
| `OpenParsec/SettingsHandler.swift` | All new @AppStorage keys. |
| `OpenParsec/SettingsView.swift` | UI for all new settings. |
| `OpenParsec/CParsec.swift` | `lastConnectedPeerID` lifecycle. |
| `OpenParsec/GameController.swift` | GCMouse: local-cursor (main-dispatched), wheel direction/sensitivity, x/y swap fix. |
| `OpenParsec/ParsecGLKRenderer.swift` | PiP captureFrame gate. |
| `OpenParsec/AppDelegate.swift` | `CrashReporter`. |
| `OpenParsec/Info.plist` | `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`. |

---

## 9. Build, CI, signing, release

- **CI:** `.github/workflows/build.yml`, `macos-latest`, Xcode 26.2 → `xcodebuild archive ... CODE_SIGNING_ALLOWED=NO` → fake-sign with `ldid` on Ubuntu → `OpenParsec.ipa` artifact. (Fork required Actions to be manually enabled once.)
- **Releases** are produced manually by the author: download the CI `.ipa`, then for sideloader compatibility produce four variants per release tag:
  - `OpenParsec-vN.ipa` — CI original (Linux `ldid` fake-sign, bundle `com.aigch.OpenParsec`).
  - `OpenParsec-vN-unsigned.ipa` — signature stripped, original bundle id (Scarlet/eSign re-sign cleanly).
  - `OpenParsec-vN-trackpadfix.ipa` — unique bundle id `com.2extndd.openparsec.trackpadfix`, macOS ad-hoc signed (AltStore/SideStore).
  - `OpenParsec-vN-trackpadfix-unsigned.ipa` — unique bundle id, unsigned (parallel install).
  - `CFBundleVersion` is bumped per release to defeat sideloader caches.
- **Upstream PR:** `hugeBlack/OpenParsec#70` tracks the branch.

---

## 10. Test plan (manual QA, per feature)

**Trackpad:** cursor smooth on slow + fast finger moves; no judder at gesture start. 2-finger scroll smooth; lift → visible inertia glide (~0.5 s default); toggle Inertia off → stops dead. Natural Scrolling on = swipe-down moves content down.

**Local cursor:** enable overlay → gray dot appears centered, follows finger with no RTT; host cursor hidden. Plug external mouse → dot follows mouse (no crash). Zoom in (pinch) → scroll pans locally, dot scales with content.

**Keyboard:** type normally (no double chars, no stuck toolbar). Cmd+A/C/V/Z in a host text app. Caps-Lock layout toggle → host switches (requires host shortcut bound). Windows remap on → Cmd+C = copy on Windows. 3-finger tap → soft keyboard + toolbar; Done → toolbar gone, language sync still live.

**Resolution:** open overlay → Resolution menu (must NOT crash on iOS 14.x). Pick a value → "Switching resolution…" overlay, last frame frozen (no black), reconnect ≤ ~1 s, no false Disconnected alert.

**Display:** multi-display host → pick display (switches on first tap). Disconnect, reconnect → same display restored. Kill app, relaunch, reconnect → still restored.

**Latency:** Low Latency Mode on → metrics overlay shows device-max FPS (120 on ProMotion). Cmd shortcuts feel instant.

**Crash reporter:** force a crash (if repro known) → relaunch → crash log in clipboard + in Files app (On My iPad → OpenParsec → last_crash.log).

---

## 11. Recommended next steps for the reviewing agent

1. **Resolve the finder-agent code review** (§6) — especially #2 (bitrate resend pile-up) and #3 (FR reclaim). These are the most likely remaining real bugs.
2. **Confirm GCMouse fix** (`fc6776c`) actually serializes all `localCursorImageView` access to main (also check the scroll x/y handlers — they only call `CParsec.sendWheelMsg`, which is SDK-thread-safe, so they're fine off-main).
3. **Decide on the inertia architecture** — keep client-side `CADisplayLink` (current) or switch to forwarding iPadOS momentum phases (canonical). The user has repeatedly reported inertia feel issues; the canonical approach may end the back-and-forth.
4. **Verify language-sync reliability** end-to-end with a host that has the shortcut bound — separate "client didn't fire" from "host didn't act".
5. **Consider fixing the `cursorScale`/`hideStatusBar` UserDefaults key collision** (§4) — pre-existing but trivial.
6. **Once a real crash log arrives**, symbolicate and confirm whether the remaining crashes are the GCMouse path (now fixed) or something else.
