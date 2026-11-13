import UIKit
import ParsecSDK
import os

// Mirrors text between UIPasteboard and the host over user data ID 7, which the stock host
// handles in both directions when its app_copy_paste setting allows it.
final class ClipboardSync {
	static let shared = ClipboardSync()

	// The SDK warns that its message channel is not meant for bulk data.
	private let maxTextBytes = 1 << 20
	private let pollInterval: TimeInterval = 1
	private var timer: Timer?

	// Persisted so a copy made before launching the app still reaches the host, while an
	// unchanged pasteboard does not overwrite the host clipboard on every connection.
	private var lastChangeCount = UserDefaults.standard.integer(forKey: "lastClipboardChangeCount") {
		didSet { UserDefaults.standard.set(lastChangeCount, forKey: "lastClipboardChangeCount") }
	}

	func start() {
		stop()
		// Polling because UIPasteboard.changedNotification misses copies made in other apps.
		timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
			self?.sendIfChanged()
		}
		sendIfChanged()
	}

	func stop() {
		timer?.invalidate()
		timer = nil
	}

	func receive(_ text: String) {
		DispatchQueue.main.async {
			UIPasteboard.general.string = text
			self.lastChangeCount = UIPasteboard.general.changeCount
		}
	}

	private func sendIfChanged() {
		let pasteboard = UIPasteboard.general
		guard pasteboard.changeCount != lastChangeCount,
			UIApplication.shared.applicationState == .active,
			CParsec.getStatus() == PARSEC_OK else { return }

		// Mark it seen before reading, so a declined paste prompt is not repeated every poll.
		lastChangeCount = pasteboard.changeCount
		guard pasteboard.hasStrings, let text = pasteboard.string else { return }

		let data = Data(text.utf8)
		guard data.count <= maxTextBytes else {
			os_log("%{public}@", log: sdkLog, "[clipboard] skipped \(data.count) bytes")
			return
		}
		CParsec.sendUserData(type: .clipboard, message: data)
	}
}
