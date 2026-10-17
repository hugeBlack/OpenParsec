import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
	var window: UIWindow?

	func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
		if connectionOptions.shortcutItem?.type == ParsecBackgroundManager.reconnectShortcut {
			ParsecBackgroundManager.shared.reconnectPending = true
		}
		ParsecBackgroundManager.shared.updateShortcut()
		let contentView = ContentView()

		if let windowScene = scene as? UIWindowScene {
		    let window = UIWindow(windowScene: windowScene)
		    window.rootViewController = UIHostingController(rootView: contentView)
		    self.window = window
		    window.makeKeyAndVisible()
		}
	}

	func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
		guard shortcutItem.type == ParsecBackgroundManager.reconnectShortcut, !ParsecBackgroundManager.shared.hasActiveConnection, !ParsecBackgroundManager.shared.isMarkedForReconnect, let reconnect = ParsecBackgroundManager.shared.onShortcutReconnect else {
			completionHandler(false)
			return
		}
		reconnect()
		completionHandler(true)
	}

	func sceneDidDisconnect(_ scene: UIScene) {
		if ParsecBackgroundManager.shared.hasActiveConnection {
			CParsec.sendReleaseMessage()
			CParsec.disconnect()
		}
	}

	private var pendingUnpause: DispatchWorkItem?

	func sceneDidBecomeActive(_ scene: UIScene) {
		if #available(iOS 15.0, *) {
			PictureInPictureManager.shared.stopPiP()
			if PictureInPictureManager.shared.stopFramePump() {
				ParsecBackgroundManager.shared.glkViewController?.isPaused = false
			}
		}
		if ParsecBackgroundManager.shared.isPaused {
			ParsecBackgroundManager.shared.glkViewController?.isPaused = false
			CParsec.resume()
			ParsecBackgroundManager.shared.resumedAt = Date()
			pendingUnpause?.cancel()
			let unpause = DispatchWorkItem { ParsecBackgroundManager.shared.isPaused = false }
			pendingUnpause = unpause
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: unpause)
		}
		// drop any input the host still thinks is held, a stuck modifier survives the resume
		if ParsecBackgroundManager.shared.hasActiveConnection {
			CParsec.sendReleaseMessage()
		}
		ParsecBackgroundManager.shared.sceneDidBecomeActive()
	}

	func sceneWillResignActive(_ scene: UIScene) {
		if ParsecBackgroundManager.shared.hasActiveConnection {
			CParsec.sendReleaseMessage()
		}
		ParsecBackgroundManager.shared.sceneWillResignActive()
	}

	func sceneWillEnterForeground(_ scene: UIScene) {
	}

	func sceneDidEnterBackground(_ scene: UIScene) {
		pendingUnpause?.cancel()
		pendingUnpause = nil
		var pipAttempted = false
		if #available(iOS 15.0, *) {
			if ParsecBackgroundManager.shared.hasActiveConnection && SettingsHandler.enablePiP {
				PictureInPictureManager.shared.startPiP()
				pipAttempted = PictureInPictureManager.shared.isPiPActive || PictureInPictureManager.shared.isStarting
			}
		}

		if pipAttempted {
			ParsecBackgroundManager.shared.isPaused = false
			if #available(iOS 15.0, *) {
				ParsecBackgroundManager.shared.glkViewController?.isPaused = true
				PictureInPictureManager.shared.startFramePump()
			}
		}

		if !pipAttempted && ParsecBackgroundManager.shared.hasActiveConnection {
			ParsecBackgroundManager.shared.glkViewController?.isPaused = true
			CParsec.sendReleaseMessage()
			CParsec.pause()
			ParsecBackgroundManager.shared.isPaused = true
		}

		if ParsecBackgroundManager.shared.hasActiveConnection {
			appNote("[background] picture in picture \(pipAttempted ? "starting" : "off"), stream \(pipAttempted ? "running" : "paused")")
		}
		ParsecBackgroundManager.shared.sceneDidEnterBackground()
	}
}
