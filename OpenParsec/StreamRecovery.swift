import Foundation

struct StreamRecoveryBudget {
	private(set) var attempts = 0
	private(set) var lastAttemptAt: TimeInterval?
	private var healthySince: TimeInterval?

	var isExhausted: Bool { attempts >= 3 }

	mutating func beginAttempt(at time: TimeInterval) -> Bool {
		healthySince = nil
		guard !isExhausted else { return false }
		if let lastAttemptAt {
			let delay: TimeInterval = attempts == 1 ? 2 : 5
			guard time - lastAttemptAt >= delay else { return false }
		}
		attempts += 1
		lastAttemptAt = time
		return true
	}

	mutating func recordFailure() {
		healthySince = nil
	}

	@discardableResult
	mutating func recordHealthy(at time: TimeInterval) -> Bool {
		if healthySince == nil { healthySince = time }
		guard time - healthySince! >= 5 else { return false }
		attempts = 0
		lastAttemptAt = nil
		return true
	}

	mutating func reset() {
		self = StreamRecoveryBudget()
	}
}
