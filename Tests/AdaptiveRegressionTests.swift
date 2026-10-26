import Foundation
import CoreGraphics

@main
enum AdaptiveRegressionTests {
	static func main() {
		var checks = 0
		func check(_ condition: @autoclosure () -> Bool, _ name: String) {
			precondition(condition(), "FAILED: \(name)")
			checks += 1
		}
		func near(_ a: CGPoint, _ b: CGPoint) -> Bool {
			abs(a.x - b.x) < 0.001 && abs(a.y - b.y) < 0.001
		}

		check(DuoSupport.supportsAdaptiveLayout(modelIdentifier: "iPhone19,4"), "verified Duo enables adaptive layout")
		for model in ["iPhone17,1", "iPhone18,1", "iPhone19,1", "iPad16,3", "iPad17,1", "", "unknown", "arm64", "x86_64"] {
			check(!DuoSupport.supportsAdaptiveLayout(modelIdentifier: model), "non-Duo and unknown hardware retains legacy layout")
		}

		let host = CGSize(width: 1920, height: 1080)
		let closed = CGSize(width: 400, height: 700)
		let open = CGSize(width: 800, height: 700)
		check(near(AdaptiveGeometry.carryCursor(CGPoint(x: 200, y: 350), from: closed, to: open, host: host),
				   CGPoint(x: 400, y: 350)), "cursor center survives unfolding")
		let point = CGPoint(x: 140, y: 320)
		let unfolded = AdaptiveGeometry.carryCursor(point, from: closed, to: open, host: host)
		check(near(AdaptiveGeometry.carryCursor(unfolded, from: open, to: closed, host: host), point),
			  "host cursor round trip across aspect ratios")
		let tall = CGSize(width: 800, height: 1000)
		check(near(AdaptiveGeometry.carryCursor(CGPoint(x: 400, y: 350), from: open, to: tall, host: host),
				   CGPoint(x: 400, y: 500)), "height-only resize")
		check(AdaptiveGeometry.carryCursor(point, from: closed, to: .zero, host: host) == .zero,
			  "zero viewport is safe")
		check(AdaptiveGeometry.carryCursor(point, from: .zero, to: open, host: host) == CGPoint(x: 400, y: 350),
			  "initial viewport centers cursor")
		check(near(AdaptiveGeometry.carryCursor(CGPoint(x: 200, y: 350), from: closed, to: open, host: .zero),
				   CGPoint(x: 400, y: 350)), "unknown host size uses proportional mapping")
		check(AdaptiveGeometry.carryCursor(CGPoint(x: -1000, y: 10000), from: closed, to: open, host: host) == CGPoint(x: 0, y: 700),
			  "cursor clamped to resized view")
		check(!AdaptiveGeometry.valid(CGSize(width: CGFloat.nan, height: 100)), "invalid view rejected")

		let zoomedContent = CGSize(width: 1600, height: 1400)
		check(AdaptiveGeometry.clampedOffset(CGPoint(x: 2000, y: -100), content: zoomedContent, viewport: open) == CGPoint(x: 800, y: 0),
			  "zoomed offset clamped after resize")
		check(AdaptiveGeometry.clampedOffset(CGPoint(x: 0, y: 2000), content: zoomedContent, viewport: open, bottomInset: 300).y == 1000,
			  "keyboard inset remains reachable")
		check(AdaptiveGeometry.clampedOffset(CGPoint(x: 50, y: 50), content: closed, viewport: open) == .zero,
			  "small content cannot pan beyond bounds")

		let bounds = CGRect(origin: .zero, size: open)
		check(AdaptiveGeometry.controlRegion(in: bounds, avoiding: []) == bounds, "flat screen uses full safe area")
		let verticalFold = CGRect(x: 390, y: 0, width: 20, height: 700)
		let verticalRegion = AdaptiveGeometry.controlRegion(in: bounds, avoiding: [verticalFold])
		check(verticalRegion.minX == 410 && verticalRegion.width == 390, "book pose prefers trailing controls")
		check(!verticalRegion.intersects(verticalFold.insetBy(dx: 1, dy: 1)), "controls avoid vertical hinge")
		let horizontalFold = CGRect(x: 0, y: 340, width: 800, height: 20)
		let horizontalRegion = AdaptiveGeometry.controlRegion(in: bounds, avoiding: [horizontalFold])
		check(horizontalRegion.minY == 360 && horizontalRegion.height == 340, "tabletop pose prefers bottom controls")
		let camera = CGRect(x: 750, y: 0, width: 50, height: 50)
		let cameraRegion = AdaptiveGeometry.controlRegion(in: bounds, avoiding: [camera])
		check(!cameraRegion.intersects(camera.insetBy(dx: 1, dy: 1)), "controls avoid active camera")
		check(AdaptiveGeometry.controlRegion(in: bounds, avoiding: [CGRect(x: 400, y: 0, width: 0, height: 700)]) == bounds,
			  "inactive zero-width hinge does not displace controls")
		check(AdaptiveGeometry.pixelSize(CGSize(width: 401, height: 703), scale: 3) == CGSize(width: 1202, height: 2108),
			  "native resolution is encoder-aligned")
		check(AdaptiveGeometry.pixelSize(.zero, scale: 3) == nil, "zero resolution ignored")
		check(AdaptiveGeometry.pixelSize(open, scale: .infinity) == nil, "invalid scale ignored")

		print("Passed \(checks) adaptive layout assertions.")
	}
}
