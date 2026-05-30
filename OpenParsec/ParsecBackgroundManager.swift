import UIKit
import AVFoundation

class ParsecBackgroundManager {
	static let shared = ParsecBackgroundManager()

	private(set) var hasActiveConnection = false
	private var lastPeerId: String?
	private var didDisconnectDueToBackground = false
	private(set) var isReconnecting = false

	// Keep-alive grace window: when the app is backgrounded without PiP we
	// hold a finite UIBackgroundTask instead of dropping the stream at once.
	// A quick app-switch that returns inside the window resumes the live
	// connection instantly; staying away past it (or the OS reclaiming the
	// time via the expiration handler) falls back to the disconnect+reconnect
	// path. beginBackgroundTask needs no background-mode entitlement.
	private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
	private var graceTimer: Timer?
	// Held under iOS's typical ~30 s background allowance so our timer — not a
	// hard OS suspension — usually drives the disconnect; the expiration
	// handler is the backstop when the OS grants less time.
	private let backgroundGracePeriod: TimeInterval = 20

	var onShouldReconnect: ((String) -> Void)?
	var onShouldDisconnect: (() -> Void)?

	var isMarkedForReconnect: Bool {
		return didDisconnectDueToBackground || isReconnecting
	}

	var isPiPActive: Bool {
		if #available(iOS 15.0, *) {
			return PictureInPictureManager.shared.isPiPActive
		}
		return false
	}

	private init() {
	}

	func connectionDidStart(peerId: String) {
		hasActiveConnection = true
		lastPeerId = peerId
		didDisconnectDueToBackground = false
		isReconnecting = false
	}

	func connectionDidEnd() {
		hasActiveConnection = false
	}

	func sceneWillResignActive() {
	}

	func sceneDidBecomeActive() {
		// Returned inside the keep-alive window: the connection was never torn
		// down, so cancel the pending disconnect and resume instantly. No
		// reconnect — didDisconnectDueToBackground was never set.
		if graceTimer != nil {
			endBackgroundGrace()
			return
		}

		// Takes priority over isPiPActive check because stopPiP() is async
		if didDisconnectDueToBackground, let peerId = lastPeerId {
			didDisconnectDueToBackground = false
			isReconnecting = true

			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
				self?.onShouldReconnect?(peerId)
			}
		}
	}

	// Backgrounded without PiP: open a finite keep-alive window rather than
	// dropping the stream immediately. Called from SceneDelegate only when a
	// connection is active and PiP was not attempted.
	func beginBackgroundGrace() {
		guard hasActiveConnection else { return }
		// Re-entrancy: a window is already open, leave it running.
		guard backgroundTaskId == .invalid else { return }

		backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "ParsecKeepAlive") { [weak self] in
			// OS is about to suspend us — disconnect now while we still can.
			self?.expireBackgroundGrace()
		}

		// No background time granted: fall back to the old immediate drop.
		if backgroundTaskId == .invalid {
			triggerBackgroundDisconnect()
			return
		}

		graceTimer?.invalidate()
		graceTimer = Timer.scheduledTimer(withTimeInterval: backgroundGracePeriod, repeats: false) { [weak self] _ in
			self?.expireBackgroundGrace()
		}
	}

	// Window survived to its end (timer fired or OS reclaimed the time):
	// disconnect and let the normal return-to-foreground reconnect take over.
	private func expireBackgroundGrace() {
		guard backgroundTaskId != .invalid else { return }
		graceTimer?.invalidate()
		graceTimer = nil
		triggerBackgroundDisconnect()
		endBackgroundTaskAssertion()
	}

	// Window cancelled because the app came back: keep the live connection.
	private func endBackgroundGrace() {
		graceTimer?.invalidate()
		graceTimer = nil
		endBackgroundTaskAssertion()
	}

	private func triggerBackgroundDisconnect() {
		didDisconnectDueToBackground = true
		// Tear the SDK session down synchronously *here*. When this runs from
		// the UIBackgroundTask expiration handler, iOS may suspend us the
		// instant endBackgroundTaskAssertion() releases the assertion, so we
		// cannot rely on the async UI-notification path to reach
		// CParsec.disconnect() in time — the same suspend hazard the PiP-stop
		// path guards against (ParsecView.post). disconnect() also flips
		// hasActiveConnection to false via connectionDidEnd(), so a second
		// background event can't reopen a window over an already-dropped
		// session. The notification below then does the UI teardown (return to
		// main view, GL cleanup), which is safe to finish on the next runloop.
		CParsec.disconnect()
		onShouldDisconnect?()
	}

	private func endBackgroundTaskAssertion() {
		if backgroundTaskId != .invalid {
			UIApplication.shared.endBackgroundTask(backgroundTaskId)
			backgroundTaskId = .invalid
		}
	}

	func markForReconnect() {
		guard lastPeerId != nil else { return }
		didDisconnectDueToBackground = true
	}

	func disableAutoReconnect() {
		didDisconnectDueToBackground = false
		isReconnecting = false
		lastPeerId = nil
		// An explicit disconnect cancels any open keep-alive window.
		endBackgroundGrace()
	}
}
