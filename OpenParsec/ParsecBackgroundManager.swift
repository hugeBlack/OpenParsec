import UIKit
import AVFoundation

class ParsecBackgroundManager {
	static let shared = ParsecBackgroundManager()

	private(set) var hasActiveConnection = false
	private var lastPeerId: String?
	private var didDisconnectDueToBackground = false
	private(set) var isReconnecting = false

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
		if hasActiveConnection {
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
	}
}
