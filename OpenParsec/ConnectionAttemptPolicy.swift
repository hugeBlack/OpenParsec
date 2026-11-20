struct ConnectionAttemptPolicy {
	private(set) var activePolls = 0
	static let timeoutPolls = 30

	mutating func tick(isActive: Bool) -> Bool {
		guard isActive else { return false }
		activePolls += 1
		return true
	}

	var timedOut: Bool { activePolls >= Self.timeoutPolls }

	static func shouldRetry(isPeerFailure: Bool, alreadyRetried: Bool) -> Bool {
		isPeerFailure && !alreadyRetried
	}
}
