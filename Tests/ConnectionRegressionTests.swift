import Foundation

@main
enum ConnectionRegressionTests {
	static func main() {
		var checks = 0
		func check(_ condition: @autoclosure () -> Bool, _ name: String) {
			precondition(condition(), "FAILED: \(name)")
			checks += 1
		}
		var policy = ConnectionAttemptPolicy()
		var paused = true
		for _ in 0..<100 { paused = !policy.tick(isActive: false) && paused }
		check(paused, "permission prompt pauses polling")
		check(policy.activePolls == 0 && !policy.timedOut, "inactive time never consumes timeout")
		for _ in 0..<29 { _ = policy.tick(isActive: true) }
		check(!policy.timedOut, "attempt remains live before timeout")
		_ = policy.tick(isActive: true)
		check(policy.timedOut, "attempt is bounded")
		check(ConnectionAttemptPolicy.shouldRetry(isPeerFailure: true, alreadyRetried: false), "first peer failure can retry")
		check(!ConnectionAttemptPolicy.shouldRetry(isPeerFailure: true, alreadyRetried: true), "second failure never loops")
		check(!ConnectionAttemptPolicy.shouldRetry(isPeerFailure: false, alreadyRetried: false), "permission/auth errors not peer retries")
		print("Passed \(checks) connection-policy assertions.")
	}
}
