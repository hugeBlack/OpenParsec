import UIKit
import Darwin

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

	// ---- Async-signal-safe state, all pre-allocated in install() ----
	// The signal handler must never call malloc, Foundation, or Swift String:
	// if the crashing thread already holds the malloc lock (the common case for
	// SIGSEGV/SIGABRT), any allocation inside the handler deadlocks and the log
	// never gets written — exactly the failure that made crashes undiagnosable.
	// So everything the handler touches is allocated up front here.
	private static var logPathC: UnsafeMutablePointer<CChar>? = nil          // strdup'd log path
	private static var headerPrefixC: UnsafeMutablePointer<CChar>? = nil     // "=== OpenParsec fatal signal "
	private static var headerSuffixC: UnsafeMutablePointer<CChar>? = nil     // " ===\nBacktrace:\n"
	private static let backtraceCapacity: Int32 = 128
	private static var backtraceBuffer: UnsafeMutablePointer<UnsafeMutableRawPointer?>? = nil
	// Set to 1 by the NSException handler so a following SIGABRT (from the
	// uncaught-exception abort) appends instead of clobbering the richer log.
	private static var exceptionRecorded: sig_atomic_t = 0

	// Rich recorder for the NSException path ONLY. Runs in normal context
	// (not a signal trampoline), so Foundation/allocation is safe here.
	static func record(_ header: String) {
		let stamp = ISO8601DateFormatter().string(from: Date())
		var text = "=== OpenParsec crash @ \(stamp) ===\n"
		text += header + "\n\nBacktrace:\n"
		text += Thread.callStackSymbols.joined(separator: "\n")
		text += "\n"
		try? text.write(to: logURL, atomically: true, encoding: .utf8)
		exceptionRecorded = 1
	}

	// Async-signal-safe write of a decimal Int32 using a stack buffer only —
	// no heap, so it is safe to call from the signal handler.
	private static func writeInt(_ fd: Int32, _ value: Int32) {
		withUnsafeTemporaryAllocation(of: CChar.self, capacity: 12) { p in
			var i = 12
			var n = value
			let negative = n < 0
			if negative { n = -n }
			if n == 0 { i -= 1; p[i] = CChar(48) } // '0'
			while n > 0 { i -= 1; p[i] = CChar(48 + Int(n % 10)); n /= 10 }
			if negative { i -= 1; p[i] = CChar(45) } // '-'
			_ = write(fd, p.baseAddress! + i, 12 - i)
		}
	}

	// THE SIGNAL HANDLER. Async-signal-safe primitives only: open, write,
	// backtrace, backtrace_symbols_fd (writes straight to the fd, no malloc),
	// close, signal, raise.
	private static func handleSignal(_ s: Int32) {
		if let path = logPathC {
			// Append (don't truncate) if the exception handler already wrote a
			// richer log before abort()ing into this signal.
			let flags = exceptionRecorded != 0
				? (O_WRONLY | O_CREAT | O_APPEND)
				: (O_WRONLY | O_CREAT | O_TRUNC)
			let fd = open(path, flags, 0o644)
			if fd >= 0 {
				if let h = headerPrefixC { _ = write(fd, h, strlen(h)) }
				writeInt(fd, s)
				if let h = headerSuffixC { _ = write(fd, h, strlen(h)) }
				if let buf = backtraceBuffer {
					let frames = backtrace(buf, backtraceCapacity)
					backtrace_symbols_fd(buf, frames, fd)
				}
				_ = fsync(fd)
				close(fd)
			}
		}
		signal(s, SIG_DFL)
		raise(s)
	}

	static func install() {
		// Pre-allocate everything the signal handler will touch.
		logPathC = strdup(logURL.path)
		headerPrefixC = strdup("=== OpenParsec fatal signal ")
		headerSuffixC = strdup(" ===\nBacktrace:\n")
		backtraceBuffer = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: Int(backtraceCapacity))

		NSSetUncaughtExceptionHandler { exception in
			CrashReporter.record(
				"Uncaught NSException: \(exception.name.rawValue)\n" +
				"Reason: \(exception.reason ?? "(nil)")\n" +
				"User stack:\n" + exception.callStackSymbols.joined(separator: "\n")
			)
		}
		for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP] {
			signal(sig) { s in
				CrashReporter.handleSignal(s)
			}
		}
	}

	// Non-destructive read so a Settings "Copy Last Crash Log" action can
	// retrieve it at any time. The file is overwritten on the next crash and
	// can be cleared explicitly via clear().
	static func peek() -> String? {
		guard let text = try? String(contentsOf: logURL, encoding: .utf8), !text.isEmpty else { return nil }
		return text
	}

	static func clear() {
		try? FileManager.default.removeItem(at: logURL)
	}
}

// Lightweight append-only diagnostics channel, sibling to CrashReporter.
// Used for empirical discovery that has no local console (e.g. the host-OS
// int encoding in S04, or netProtocol/mediaContainer in S08). Entries persist
// to Documents/diagnostics.log and can be copied out via Settings →
// "Copy Diagnostics" or pulled from the Files app. Called only from normal
// (non-signal) contexts, so Foundation use is fine here.
enum Diagnostics {
	static var logURL: URL {
		let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
		return docs.appendingPathComponent("diagnostics.log")
	}

	static func note(_ line: String) {
		let stamp = ISO8601DateFormatter().string(from: Date())
		let entry = "[\(stamp)] \(line)\n"
		print("[OpenParsec][diag] \(line)")
		guard let data = entry.data(using: .utf8) else { return }
		if let handle = try? FileHandle(forWritingTo: logURL) {
			defer { try? handle.close() }
			handle.seekToEndOfFile()
			handle.write(data)
		} else {
			// File doesn't exist yet — create it with this first entry.
			try? data.write(to: logURL, options: .atomic)
		}
	}

	static func peek() -> String? {
		guard let text = try? String(contentsOf: logURL, encoding: .utf8), !text.isEmpty else { return nil }
		return text
	}

	static func clear() {
		try? FileManager.default.removeItem(at: logURL)
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
		if let crash = CrashReporter.peek() {
			// Make the previous crash trivially retrievable: copy to the
			// pasteboard (syncs to a Mac on the same Apple ID via Universal
			// Clipboard) and print it for any attached console. The file is
			// kept (not consumed) so the Settings "Copy Last Crash Log" row
			// can re-surface it later.
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
