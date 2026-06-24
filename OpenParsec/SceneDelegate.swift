import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
	var window: UIWindow?

	func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
		let contentView = ContentView()

		if let windowScene = scene as? UIWindowScene {
		    let window = UIWindow(windowScene: windowScene)
		    window.rootViewController = UIHostingController(rootView: contentView)
		    self.window = window
		    window.makeKeyAndVisible()
		}
	}

	func sceneDidDisconnect(_ scene: UIScene) {
		if ParsecBackgroundManager.shared.hasActiveConnection {
			CParsec.sendReleaseMessage()
			CParsec.disconnect()
		}
	}

	func sceneDidBecomeActive(_ scene: UIScene) {
		if #available(iOS 15.0, *) {
			PictureInPictureManager.shared.stopPiP()
		}
		if ParsecBackgroundManager.shared.isPaused {
			ParsecBackgroundManager.shared.glkViewController?.isPaused = false
			CParsec.resume()
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				ParsecBackgroundManager.shared.isPaused = false
			}
		}
		// drop any input the host still thinks is held after ANY interruption — Control Center, the
		// notification shade, a bottom-bar tap, or a brief sleep/unlock all resign+reactivate WITHOUT a
		// full background (isPaused stays false), so the paused-only path above misses them and a
		// stranded button (right = context menu) survives the resume. releasing nothing held is a no-op.
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
		var pipAttempted = false
		if #available(iOS 15.0, *) {
			if ParsecBackgroundManager.shared.hasActiveConnection && SettingsHandler.enablePiP {
				PictureInPictureManager.shared.startPiP()
				pipAttempted = PictureInPictureManager.shared.isPiPActive || PictureInPictureManager.shared.isStarting
			}
		}

		if !pipAttempted && ParsecBackgroundManager.shared.hasActiveConnection {
			ParsecBackgroundManager.shared.glkViewController?.isPaused = true
			CParsec.sendReleaseMessage()
			CParsec.pause()
			ParsecBackgroundManager.shared.isPaused = true
		}

		ParsecBackgroundManager.shared.sceneDidEnterBackground()
	}
}
