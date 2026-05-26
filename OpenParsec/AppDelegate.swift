import UIKit

// Lightweight crash reporter. Writes the last uncaught exception / fatal
// signal (with a backtrace) to Documents/last_crash.log. On the next launch
// the log is copied to the system pasteboard (so it can be pasted straight
// into a chat, or synced to a Mac via Universal Clipboard) and left in the
// app's Documents folder, which is exposed in the Files app via
// UIFileSharingEnabled. Zero infrastructure required.
enum CrashReporter {
	static var logURL: URL {
		let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
		return docs.appendingPathComponent("last_crash.log")
	}

	// MUST stay free of captured context — signal trampolines are C function
	// pointers. Only touches statics / the file system / Thread API.
	static func record(_ header: String) {
		let stamp = ISO8601DateFormatter().string(from: Date())
		var text = "=== OpenParsec crash @ \(stamp) ===\n"
		text += header + "\n\nBacktrace:\n"
		text += Thread.callStackSymbols.joined(separator: "\n")
		text += "\n"
		try? text.write(to: logURL, atomically: true, encoding: .utf8)
	}

	static func install() {
		NSSetUncaughtExceptionHandler { exception in
			CrashReporter.record(
				"Uncaught NSException: \(exception.name.rawValue)\n" +
				"Reason: \(exception.reason ?? "(nil)")\n" +
				"User stack:\n" + exception.callStackSymbols.joined(separator: "\n")
			)
		}
		for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP] {
			signal(sig) { s in
				CrashReporter.record("Fatal signal: \(s)")
				signal(s, SIG_DFL)
				raise(s)
			}
		}
	}

	// Returns the pending crash log (if any) and removes it.
	static func consumePending() -> String? {
		guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return nil }
		try? FileManager.default.removeItem(at: logURL)
		return text
	}
}

@main
class AppDelegate: UIResponder, UIApplicationDelegate
{
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions:[UIApplication.LaunchOptionsKey: Any]?) -> Bool
	{
		// Install the crash reporter as early as possible so it catches
		// failures during the rest of launch too.
		CrashReporter.install()
		if let crash = CrashReporter.consumePending() {
			// Make the previous crash trivially retrievable: copy to the
			// pasteboard (syncs to a Mac on the same Apple ID via Universal
			// Clipboard) and print it for any attached console.
			UIPasteboard.general.string = crash
			print("[OpenParsec] Recovered crash log from previous run:\n\(crash)")
		}

		// Override point for customization after application launch.
		UTMViewControllerPatches.patchAll()
		return true
	}

	func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration
	{
		// Called when a new scene session is being created.
		// Use this method to select a configuration to create the new scene with.
		return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
	}

	func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>)
	{
		// Called when the user discards a scene session.
		// If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
		// Use this method to release any resources that were specific to the discarded scenes, as they will not return.
	}

	func applicationWillTerminate(_ application: UIApplication)
	{
		CParsec.destroy()
	}
}
