import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate
{
	var window: UIWindow?

	func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions)
	{
		let contentView = ContentView()

		if let windowScene = scene as? UIWindowScene
		{
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

	func sceneDidBecomeActive(_ scene: UIScene)
	{
		if #available(iOS 15.0, *) {
			PictureInPictureManager.shared.stopPiP()
		}
		if ParsecBackgroundManager.shared.isPaused {
			CParsec.resume()
			ParsecBackgroundManager.shared.isPaused = false
		}
		ParsecBackgroundManager.shared.sceneDidBecomeActive()
	}

	func sceneWillResignActive(_ scene: UIScene) {
		if ParsecBackgroundManager.shared.hasActiveConnection {
			CParsec.sendReleaseMessage()
		}
		ParsecBackgroundManager.shared.sceneWillResignActive()
	}

	func sceneWillEnterForeground(_ scene: UIScene)
	{
	}

	func sceneDidEnterBackground(_ scene: UIScene)
	{
		var pipAttempted = false
		if #available(iOS 15.0, *) {
			if ParsecBackgroundManager.shared.hasActiveConnection && SettingsHandler.enablePiP {
				PictureInPictureManager.shared.startPiP()
				pipAttempted = PictureInPictureManager.shared.isPiPActive || PictureInPictureManager.shared.isStarting
			}
		}

		if !pipAttempted && ParsecBackgroundManager.shared.hasActiveConnection {
			CParsec.sendReleaseMessage()
			CParsec.pause()
			ParsecBackgroundManager.shared.isPaused = true
		}

		ParsecBackgroundManager.shared.sceneDidEnterBackground()
	}
}
