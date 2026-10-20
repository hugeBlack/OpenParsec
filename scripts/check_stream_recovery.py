#!/usr/bin/env python3
"""Run production recovery methods with a fake SDK, display layer and clock.

Usage: python3 scripts/check_stream_recovery.py
Requires macOS swiftc; does not exercise an iOS renderer or a real stream.
"""

from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def method(path, signature):
    source = (ROOT / path).read_text()
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end].replace("private func", "func")


poll = method("OpenParsec/ParsecView.swift", "func poll()")
# Metrics formatting is unrelated to recovery and requires SDK decoder structs.
poll = poll.split("\n\t\tif showMenu || SettingsHandler.alwaysShowStatus {", 1)[0] + "\n}"
pip = method("OpenParsec/PictureInPictureManager.swift", "private func displayLayerTakesFrames")

fixtures = r'''
import Foundation

var clock: TimeInterval = 0
var testDate: Date { Date(timeIntervalSince1970: clock) }
var failures = 0
var checks = 0
func check(_ value: Bool, _ message: String) {
    checks += 1
    if !value { print("FAIL: \(message)"); failures += 1 }
}
func appNote(_ message: String) {}

enum Status: Int {
    case ok, interrupted, connecting, approval, permanent
    var isPermanentFailure: Bool { self == .permanent }
    func readable() -> String { "test failure" }
}
let PARSEC_OK = Status.ok
let NETWORK_ERR_INTERRUPTED = Status.interrupted
let PARSEC_CONNECTING = Status.connecting
let CONNECT_WRN_APPROVAL = Status.approval
struct ParsecClientStatus { var networkFailure = false }
enum SettingsHandler {
    static var autoReconnect = true
    static var errorPrompts = true
}
class RenderLoop { var isPaused = false }
class ParsecBackgroundManager {
    static var shared = ParsecBackgroundManager()
    var isPaused = false
    var isMarkedForReconnect = false
    var lastPeerId: String? = "host"
    var reconnectAttempts = 0 // Lets this harness also reproduce the old main behavior.
    var recoveryBudget = StreamRecoveryBudget()
    var reconnectStartTime = Date(timeIntervalSince1970: 0)
    var resumedAt: Date?
    var glkViewController: RenderLoop? = RenderLoop()
    func connectionDidEnd() {}
    func markForReconnect() { isMarkedForReconnect = true }
}
struct Bounds { var width: CGFloat = 1024; var height: CGFloat = 768 }
class MockView { var bounds = Bounds() }
class ParsecViewController {
    var view = MockView()
    func resetKeyState() {}
}
class UIScreen {
    static let main = UIScreen()
    var scale: CGFloat = 2
}
enum ParsecView { static func getHostUserData() {} }
enum CParsec {
    static var status = Status.ok
    static var networkFailure = false
    static var reconnects = 0
    static func getStatusEx(_ pcs: inout ParsecClientStatus) -> Status {
        pcs.networkFailure = networkFailure
        return status
    }
    static func disconnect() {}
    static func reconnect(_ peer: String) { reconnects += 1 }
    static func setFrame(_ width: CGFloat, _ height: CGFloat, _ scale: CGFloat) {}
}
class AVAudioSession {
    enum Option { case notifyOthersOnDeactivation }
    static func sharedInstance() -> AVAudioSession { AVAudioSession() }
    func setActive(_ active: Bool, options: Option) throws {}
}
class AVSampleBufferDisplayLayer {
    enum State { case failed, rendering, unknown }
    var status = State.unknown
    var isReadyForMoreMediaData = true
    var requiresFlushToResumeDecoding = true
    var flushes = 0
    func flush() { flushes += 1; status = .unknown }
}
class PictureInPictureManager {
    static var shared = PictureInPictureManager()
    var isPiPActive = false
    var isPumping = false
    var displayLayerFlushes = 0
    var displayLayerRecovery = StreamRecoveryBudget()
    var displayLayerGaveUp = false
    var cachedFormatDescription: Int?
    var terminalFailures = 0
    func handleTerminalDisplayLayerFailure(_ layer: AVSampleBufferDisplayLayer) {
        terminalFailures += 1
    }
    // PIP_METHOD
}
class PollHarness {
    var showDCAlert = false
    var DCAlertText = ""
    var isReconnecting = false
    var connectionLost = false
    var networkFailureSince: Date?
    var parsecViewController: ParsecViewController? = ParsecViewController()
    var wasDisconnected = true
    var silentDisconnects = 0
    func onSilentDisconnect() { silentDisconnects += 1 }
    // POLL_METHOD
}

@main struct CheckRecovery {
    static func fresh() -> PollHarness {
        clock = 0
        CParsec.reconnects = 0
        CParsec.networkFailure = false
        CParsec.status = .ok
        SettingsHandler.autoReconnect = true
        SettingsHandler.errorPrompts = true
        ParsecBackgroundManager.shared = ParsecBackgroundManager()
        PictureInPictureManager.shared = PictureInPictureManager()
        return PollHarness()
    }
    static func poll(_ harness: PollHarness, _ time: TimeInterval, _ status: Status) {
        clock = time
        CParsec.status = status
        harness.poll()
    }
    static func main() {
        let flapping = fresh()
        for time in [0.0, 2, 7, 12, 17] {
            poll(flapping, time, .interrupted)
            poll(flapping, time + 0.5, .ok)
        }
        check(CParsec.reconnects == 3, "reconnects stop after three attempts across brief OK samples")
        check(flapping.showDCAlert, "exhausted reconnects reach the existing error prompt")

        let stable = fresh()
        poll(stable, 0, .interrupted)
        check(ParsecBackgroundManager.shared.glkViewController?.isPaused == true, "recovery pauses the shared render loop")
        poll(stable, 0.5, .ok)
        check(stable.isReconnecting, "one OK poll keeps the recovery overlay visible")
        poll(stable, 5, .ok)
        check(stable.isReconnecting, "recovery waits for five full healthy seconds")
        poll(stable, 5.5, .ok)
        check(!stable.isReconnecting, "sustained health completes recovery")
        check(ParsecBackgroundManager.shared.glkViewController?.isPaused == false, "stable recovery resumes rendering")
        check(ParsecBackgroundManager.shared.recoveryBudget.attempts == 0, "sustained health renews retries")

        let pumping = fresh()
        PictureInPictureManager.shared.isPumping = true
        poll(pumping, 0, .interrupted)
        poll(pumping, 0.5, .ok)
        poll(pumping, 5.5, .ok)
        check(ParsecBackgroundManager.shared.glkViewController?.isPaused == true, "PiP pumping retains ownership of rendering")

        let network = fresh()
        poll(network, 0, .interrupted)
        CParsec.networkFailure = true
        for time in stride(from: 0.5, through: 4.0, by: 0.5) { poll(network, time, .ok) }
        check(CParsec.reconnects == 2, "SDK OK with network failure cannot complete a reconnect")
        check(network.isReconnecting, "network failure keeps recovery active")

        let connecting = fresh()
        poll(connecting, 0, .interrupted)
        poll(connecting, 14, .connecting)
        check(CParsec.reconnects == 1, "connecting retains the existing 15-second timeout")
        poll(connecting, 15, .connecting)
        check(CParsec.reconnects == 2, "connecting retries after its timeout")

        let approval = fresh()
        poll(approval, 0, .interrupted)
        poll(approval, 59, .approval)
        check(CParsec.reconnects == 1, "approval retains its 60-second timeout")
        poll(approval, 60, .approval)
        check(CParsec.reconnects == 2, "approval retries after its timeout")

        let permanent = fresh()
        poll(permanent, 0, .permanent)
        check(CParsec.reconnects == 0 && permanent.showDCAlert, "permanent failures are not retried")
        let silent = fresh()
        SettingsHandler.errorPrompts = false
        for time in [0.0, 2, 7, 12] { poll(silent, time, .interrupted) }
        check(silent.silentDisconnects == 1 && !silent.showDCAlert, "silent exhaustion stays silent")

        let pip = PictureInPictureManager()
        let layer = AVSampleBufferDisplayLayer()
        for time in [0.0, 2, 7, 12] {
            clock = time
            layer.status = .failed
            _ = pip.displayLayerTakesFrames(layer)
            clock = time + 0.5
            layer.status = .rendering
            _ = pip.displayLayerTakesFrames(layer)
        }
        check(layer.flushes == 3 && pip.terminalFailures == 1, "PiP stops alternating failure/rendering after three flushes")
        check(!pip.displayLayerTakesFrames(layer), "terminal PiP recovery stays stopped")

        let delayed = PictureInPictureManager()
        let delayedLayer = AVSampleBufferDisplayLayer()
        clock = 0
        delayedLayer.status = .failed
        _ = delayed.displayLayerTakesFrames(delayedLayer)
        clock = 1
        delayedLayer.status = .failed
        check(!delayed.displayLayerTakesFrames(delayedLayer), "PiP backoff does not enqueue failed layers")
        check(delayedLayer.flushes == 1, "PiP respects retry spacing")

        clock = 2
        delayedLayer.status = .failed
        _ = delayed.displayLayerTakesFrames(delayedLayer)
        clock = 2.5
        delayedLayer.status = .rendering
        _ = delayed.displayLayerTakesFrames(delayedLayer)
        clock = 6
        delayedLayer.status = .unknown
        _ = delayed.displayLayerTakesFrames(delayedLayer)
        clock = 7.5
        delayedLayer.status = .rendering
        _ = delayed.displayLayerTakesFrames(delayedLayer)
        check(delayed.displayLayerRecovery.attempts == 2, "unknown layer status interrupts the healthy interval")
        clock = 12.5
        _ = delayed.displayLayerTakesFrames(delayedLayer)
        check(delayed.displayLayerRecovery.attempts == 0, "five healthy PiP seconds renew flush retries")

        var budget = StreamRecoveryBudget()
        check(budget.beginAttempt(at: 0), "first recovery attempt starts immediately")
        check(!budget.beginAttempt(at: 1), "second attempt waits two seconds")
        check(budget.beginAttempt(at: 2), "second attempt starts at its deadline")
        check(!budget.beginAttempt(at: 6.9), "third attempt waits five seconds")
        check(budget.beginAttempt(at: 7), "third attempt starts at its deadline")
        check(!budget.recordHealthy(at: 8), "brief health retains exhausted retries")
        budget.recordFailure()
        check(!budget.recordHealthy(at: 100), "resume/failure restarts the health interval")
        check(budget.recordHealthy(at: 105), "continuous health renews exhausted retries")
        budget.reset()
        check(budget.attempts == 0 && budget.lastAttemptAt == nil, "a new session gets a fresh budget")

        if failures > 0 { exit(1) }
        print("\(checks) stream recovery policy and production-method checks passed")
    }
}
'''

fixtures = fixtures.replace("// PIP_METHOD", pip).replace("// POLL_METHOD", poll)
fixtures = fixtures.replace("ProcessInfo.processInfo.systemUptime", "clock")
fixtures = fixtures.replace("Date()", "testDate")
with tempfile.TemporaryDirectory(prefix="openparsec-recovery-") as directory:
    source = Path(directory) / "RecoveryChecks.swift"
    binary = Path(directory) / "check-recovery"
    source.write_text(fixtures)
    subprocess.run(["swiftc", str(ROOT / "OpenParsec/StreamRecovery.swift"), str(source), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
