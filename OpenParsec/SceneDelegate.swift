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
	}

	func sceneDidBecomeActive(_ scene: UIScene)
	{
		if #available(iOS 15.0, *) {
			PictureInPictureManager.shared.stopPiP()
		}
		ParsecBackgroundManager.shared.sceneDidBecomeActive()
	}

	func sceneWillResignActive(_ scene: UIScene)
	{
		// Do NOT start PiP here — fires for app switcher gesture too. PiP starts in sceneDidEnterBackground.
		ParsecBackgroundManager.shared.sceneWillResignActive()
	}

	func sceneWillEnterForeground(_ scene: UIScene)
	{
	}

	func sceneDidEnterBackground(_ scene: UIScene)
	{
		var pipAttempted = false
		if #available(iOS 15.0, *) {
			if ParsecBackgroundManager.shared.hasActiveConnection {
				PictureInPictureManager.shared.startPiP()
				pipAttempted = PictureInPictureManager.shared.isPiPActive || PictureInPictureManager.shared.isStarting
			}
		}

		if !pipAttempted && ParsecBackgroundManager.shared.hasActiveConnection {
			ParsecBackgroundManager.shared.onShouldDisconnect?()
		}

		ParsecBackgroundManager.shared.sceneDidEnterBackground()
	}
}
