#!/usr/bin/env python3
"""Run production touch-handler logic with deterministic platform/transport doubles.
Requires macOS Swift. Does not replace a real iOS streaming/input smoke test.
"""
from pathlib import Path
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[1] / "OpenParsec/ParsecViewController.swift").read_text()
def method(name):
    import re
    match = re.search(r"(?:@objc )?(?:private )?func " + name + r"\(", source)
    assert match, name
    start = source.index("{", match.start())
    depth = 1
    end = start + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[match.start():end].replace("@objc ", "").replace("private ", "")

swift = r"""
import Foundation
import CoreGraphics
typealias CFTimeInterval = Double
var now = 10.0
func CACurrentMediaTime() -> Double { now }
enum Mode { case touchpad, direct }
enum SettingsHandler {
 static var cursorMode = Mode.touchpad
 static var cursorMomentum = true
 enum RightClick { case firstFinger, secondFinger, middle }
 static var rightClickPosition = RightClick.middle
}
class View { func convert(_ p: CGPoint, from: View?) -> CGPoint { p } }
class UITouch: Hashable {
 var point = CGPoint(x:100,y:100); var previous = CGPoint(x:100,y:100); var timestamp = now
 func location(in: View?) -> CGPoint { point }
 func previousLocation(in: View?) -> CGPoint { previous }
 static func ==(a: UITouch,b: UITouch) -> Bool { a === b }
 func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }
}
class UIGestureRecognizer {
 enum State { case began, changed, ended, cancelled, failed, possible }
 var state = State.possible; var view: View?; var point = CGPoint(x:100,y:100)
 func location(in: View?) -> CGPoint { point }
 func location(ofTouch: Int, in: View?) -> CGPoint { point }
}
typealias UITapGestureRecognizer = UIGestureRecognizer
struct ParsecMouseButton { init(rawValue: UInt32) {} }
class MouseInfo { var mousePositionRelative = false }
enum CParsec {
 static let mouseInfo = MouseInfo()
 static var events: [String] = []
 static func sendMouseClickMessage(_ button: ParsecMouseButton, _ down: Bool) { events.append(down ? "down" : "up") }
 static func sendMousePosition(_ x: Int32,_ y: Int32) { events.append("move") }
 static func sendMouseDelta(_ x: Int32,_ y: Int32) { events.append("delta") }
 static func sendWheelMsg(x: Int32,y: Int32) { events.append("wheel") }
}
class TouchController {
 func onTap(typeOfTap: Int,location: CGPoint) { CParsec.events += typeOfTap == 1 ? ["down","up"] : ["rightDown","rightUp"] }
}
class UIApplication { static let shared = UIApplication(); enum State { case active }; var applicationState = State.active }
class ParsecBackgroundManager { static let shared = ParsecBackgroundManager(); var hasActiveConnection = true }
class ScrollView { var zoomScale = 1.0 }
class CADisplayLink { var timestamp = now; var targetTimestamp = now + 0.016 }
class Controller {
 let view = View(); let contentView = View(); let scrollView = ScrollView(); let touchController = TouchController()
 var clickHoldActive = false; var tapDragCandidate = false; var tapDragActive = false; var suppressSingleFingerTap = false
 var lastTapTime: Double?; var lastTapScreen = CGPoint.zero
 let tapDragInterval = 0.3; let tapDragRadius = 44.0
 var cursorDidMoveThisTouch = false; var singleTouchStartScreen = CGPoint.zero; let tapMoveSlop = 4.0
 var activeTouches: [UITouch] = []; var touchOrigins: [UITouch: CGPoint] = [:]
 let staleMoveSlop = 24.0; let staleTouchThreshold = 1.5
 var isDragging = false; var twoFingerResidual = false; var twoFingerDidMove = false
 enum TwoFingerMode { case undecided, zoom, scroll }
 var twoFingerMode = TwoFingerMode.undecided
 var edgeScrollActive = false; var edgeScrollPoint = CGPoint.zero; var edgeScrollLastTick = 0.0
 var cursorMomentumActive = false; var scrollMomentumActive = false
 var cursorVelocity = CGPoint.zero; var scrollVelocity: Float = 0
 var lastCursorMoveTime = now; var cursorContentPos = CGPoint.zero; var mouseSensitivity: Float = 1
 let flingMinSpeed = 80.0; let cursorStopSpeed = 40.0; let cursorDecayPerSec = 0.08
 let scrollDecayPerSec = 0.004; let scrollStopSpeed: Float = 200
 var accumulatedScrollY: Float = 0
 func beginTwoFinger() { twoFingerMode = .undecided; twoFingerDidMove = false }
 func handleTwoFinger() { twoFingerMode = .scroll; twoFingerDidMove = true; CParsec.events.append("wheel") }
 func startScrollMomentum() { scrollMomentumActive = true }
 func stopMomentum() { cursorMomentumActive = false; scrollMomentumActive = false; cursorVelocity = .zero }
 func ensureMomentumLink() {}
 func clampToContent(_ p: CGPoint) -> CGPoint { p }
 func positionCursorOverlay() {}
 func centerViewportOnCursorPos() {}
 func keepCursorAboveKeyboard() {}
 func edgeScrollVelocity(at: CGPoint) -> CGPoint { .zero }
 func stepEdgeScroll(_ dt: CGFloat) -> Bool { false }
"""
for name in ["parsecTouchesUpdated", "handleTouchCountChange", "beginClickHold", "releaseClickHoldIfNeeded", "flushAllTouches", "parsecTouchesCancelled", "startCursor", "endCursorIfNeeded", "handleActiveTouchesMoved", "moveCursor", "startCursorMomentum", "momentumTick", "handleSingleFingerTap", "handleTwoFingerTap", "handleLongPress"]:
    swift += method(name) + "\n"
swift += r"""
}
func fresh() -> Controller {
 SettingsHandler.cursorMode = .touchpad; SettingsHandler.cursorMomentum = true; CParsec.mouseInfo.mousePositionRelative = false
 CParsec.events = []; now += 1; return Controller()
}
func tap(_ c: Controller) {
 let t = UITouch(); c.parsecTouchesUpdated([t], moved:false); c.parsecTouchesUpdated([], moved:false)
 c.handleSingleFingerTap(UITapGestureRecognizer())
}
func second(_ c: Controller) -> UITouch {
 now += 0.1; let t = UITouch(); c.parsecTouchesUpdated([t], moved:false); return t
}
func move(_ c: Controller,_ t: UITouch) {
 now += 0.016; t.previous = t.point; t.point.x += 50; t.timestamp = now
 c.parsecTouchesUpdated([t], moved:true)
}
let c = fresh(); tap(c)
assert(CParsec.events == ["down","up"])
let t = second(c); assert(c.tapDragCandidate); move(c,t)
assert(c.clickHoldActive && c.tapDragActive)
assert(Array(CParsec.events.prefix(4)) == ["down","up","down","move"])
let failed = UIGestureRecognizer(); failed.state = .failed; c.handleLongPress(failed)
assert(c.clickHoldActive)
let began = UIGestureRecognizer(); began.state = .began; c.handleLongPress(began)
assert(CParsec.events.filter { $0 == "down" }.count == 2)
c.cursorVelocity = CGPoint(x:1000,y:0); c.lastCursorMoveTime = now
c.startCursorMomentum(); assert(!c.cursorMomentumActive)
c.cursorMomentumActive = true; c.momentumTick(CADisplayLink()); assert(!c.cursorMomentumActive)
c.parsecTouchesUpdated([], moved:false); c.handleSingleFingerTap(UITapGestureRecognizer())
assert(!c.clickHoldActive && !c.cursorMomentumActive && CParsec.events.last == "up")
assert(CParsec.events.filter { $0 == "up" }.count == 2)
let d = fresh(); tap(d); _ = second(d); d.parsecTouchesUpdated([], moved:false)
d.handleSingleFingerTap(UITapGestureRecognizer())
assert(CParsec.events == ["down","up","down","up"])
let ordinary = fresh(); let o = second(ordinary); move(ordinary,o)
assert(!ordinary.clickHoldActive && CParsec.events == ["move"])
ordinary.cursorVelocity = CGPoint(x:1000,y:0); ordinary.lastCursorMoveTime = now
ordinary.parsecTouchesUpdated([], moved:false); assert(ordinary.cursorMomentumActive)
SettingsHandler.cursorMomentum = false; ordinary.momentumTick(CADisplayLink()); assert(!ordinary.cursorMomentumActive)
let expired = fresh(); tap(expired); now += 0.31; let e = second(expired); move(expired,e); assert(!expired.clickHoldActive)
let far = fresh(); tap(far); now += 0.1; let f = UITouch(); f.point.x = 200
far.parsecTouchesUpdated([f],moved:false); move(far,f); assert(!far.clickHoldActive)
let long = fresh(); let l = second(long); long.handleLongPress(began)
assert(long.clickHoldActive); move(long,l); long.parsecTouchesUpdated([],moved:false)
assert(CParsec.events == ["down","move","up"] && !long.cursorMomentumActive)
for cancel in [false,true] {
 let interrupted = fresh(); tap(interrupted); let i = second(interrupted); move(interrupted,i)
 if cancel { interrupted.parsecTouchesCancelled() } else { interrupted.flushAllTouches() }
 assert(!interrupted.clickHoldActive && !interrupted.tapDragActive && interrupted.lastTapTime == nil)
 assert(interrupted.activeTouches.isEmpty && CParsec.events.last == "up")
}
let two = fresh(); tap(two); let a = second(two); move(two,a); let b = UITouch()
two.parsecTouchesUpdated([a,b],moved:false)
assert(!two.clickHoldActive && !two.tapDragCandidate && two.lastTapTime == nil)
two.parsecTouchesUpdated([a,b],moved:true); two.handleTwoFingerTap(UITapGestureRecognizer())
assert(two.twoFingerDidMove && CParsec.events.last == "wheel")
two.parsecTouchesUpdated([a],moved:false); let n = CParsec.events.count
two.parsecTouchesUpdated([a],moved:true); assert(CParsec.events.count == n)
two.parsecTouchesUpdated([],moved:false)
let right = fresh(); let r1 = UITouch(); let r2 = UITouch()
right.parsecTouchesUpdated([r1,r2],moved:false); right.parsecTouchesUpdated([],moved:false)
right.handleTwoFingerTap(UITapGestureRecognizer()); right.handleSingleFingerTap(UITapGestureRecognizer())
assert(CParsec.events == ["rightDown","rightUp"] && right.lastTapTime == nil)
let direct = fresh(); SettingsHandler.cursorMode = .direct; tap(direct)
assert(CParsec.events == ["move","down","up"] && direct.lastTapTime == nil)
let relative = fresh(); tap(relative); CParsec.mouseInfo.mousePositionRelative = true
let rel = second(relative); move(relative,rel)
assert(relative.clickHoldActive && CParsec.events.last == "delta")
relative.parsecTouchesUpdated([],moved:false); assert(CParsec.events.last == "up")
print("PASS single/double tap, tap-drag ordering/release, recognizer failure, long press, cancellation/lifecycle, two-finger transition/right click, momentum toggle/hold cutoff, direct and relative modes")
"""
with tempfile.TemporaryDirectory(prefix="openparsec-tapdrag-") as directory:
    path = Path(directory) / "main.swift"
    path.write_text(swift)
    binary = str(Path(directory) / "regression")
    subprocess.run(["swiftc", str(path), "-o", binary], check=True)
    subprocess.run([binary], check=True)
