import UIKit
import AVFoundation
import GLKit

class ParsecBackgroundManager {
	static let shared = ParsecBackgroundManager()

	private(set) var hasActiveConnection = false
	private(set) var lastPeerId: String? {
		didSet { UserDefaults.standard.set(lastPeerId, forKey: "lastConnectedPeerId") }
	}
	var lastHostname: String? {
		didSet { UserDefaults.standard.set(lastHostname, forKey: "lastConnectedHostname") }
	}
	private var didDisconnectDueToBackground = false
	private(set) var isReconnecting = false
	var reconnectAttempts = 0
	var isPaused = false
	weak var glkViewController: GLKViewController?

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
		lastPeerId = UserDefaults.standard.string(forKey: "lastConnectedPeerId")
		lastHostname = UserDefaults.standard.string(forKey: "lastConnectedHostname")
	}

	func connectionDidStart(peerId: String) {
		hasActiveConnection = true
		lastPeerId = peerId
		didDisconnectDueToBackground = false
		isReconnecting = false
		isPaused = false
	}

	func connectionDidEnd() {
		hasActiveConnection = false
		isPaused = false
	}

	func sceneWillResignActive() {
	}

	func sceneDidBecomeActive() {
		// Takes priority over isPiPActive check because stopPiP() is async
		if didDisconnectDueToBackground, let peerId = lastPeerId {
			didDisconnectDueToBackground = false
			isReconnecting = true

			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
				self?.onShouldReconnect?(peerId)
			}
		}
	}

	func sceneDidEnterBackground() {
		if hasActiveConnection && !isPaused {
			var pipAttempted = false
			if #available(iOS 15.0, *) {
				pipAttempted = isPiPActive || PictureInPictureManager.shared.isStarting
			}
			if !pipAttempted {
				didDisconnectDueToBackground = true
			}
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
		lastHostname = nil
		reconnectAttempts = 0
	}
}
