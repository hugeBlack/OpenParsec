import Foundation
import CoreGraphics
import Darwin

// Scope the new layouts to verified Duo hardware. Unknown devices retain the
// existing UI; geometry within the Duo path still follows live bounds/traits.
enum DuoSupport {
	static func supportsAdaptiveLayout(modelIdentifier: String) -> Bool {
		modelIdentifier == "iPhone19,4"
	}

	static let isDuo: Bool = {
		#if targetEnvironment(simulator)
		let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? ""
		#else
		var info = utsname()
		guard uname(&info) == 0 else { return false }
		let model = withUnsafeBytes(of: &info.machine) {
			String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
		}
		#endif
		return supportsAdaptiveLayout(modelIdentifier: model)
	}()
}

enum AdaptiveGeometry {
	static func valid(_ size: CGSize) -> Bool {
		size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
	}

	// Preserve the same host point even when the letterbox changes shape.
	static func carryCursor(_ point: CGPoint, from old: CGSize, to new: CGSize, host: CGSize) -> CGPoint {
		guard valid(new) else { return .zero }
		guard valid(old) else { return CGPoint(x: new.width / 2, y: new.height / 2) }
		let mapped: CGPoint
		if valid(host) {
			let oldScale = min(old.width / host.width, old.height / host.height)
			let newScale = min(new.width / host.width, new.height / host.height)
			let x = (point.x - (old.width - host.width * oldScale) / 2) / oldScale
			let y = (point.y - (old.height - host.height * oldScale) / 2) / oldScale
			mapped = CGPoint(x: x * newScale + (new.width - host.width * newScale) / 2,
							 y: y * newScale + (new.height - host.height * newScale) / 2)
		} else {
			mapped = CGPoint(x: point.x * new.width / old.width, y: point.y * new.height / old.height)
		}
		return CGPoint(x: min(max(mapped.x, 0), new.width), y: min(max(mapped.y, 0), new.height))
	}

	static func clampedOffset(_ point: CGPoint, content: CGSize, viewport: CGSize, bottomInset: CGFloat = 0) -> CGPoint {
		CGPoint(x: min(max(point.x, 0), max(0, content.width - viewport.width)),
				y: min(max(point.y, 0), max(0, content.height - viewport.height + bottomInset)))
	}

	// Keep interactive controls in a usable region, preferring the bottom/trailing
	// half of an active fold. Inputs are in the safe-area container's coordinates.
	static func controlRegion(in bounds: CGRect, avoiding obstacles: [CGRect]) -> CGRect {
		var region = bounds
		for obstacle in obstacles {
			let cut = region.intersection(obstacle)
			guard !cut.isNull, cut.width > 0, cut.height > 0 else { continue }
			let candidates = [
				CGRect(x: cut.maxX, y: region.minY, width: region.maxX - cut.maxX, height: region.height),
				CGRect(x: region.minX, y: cut.maxY, width: region.width, height: region.maxY - cut.maxY),
				CGRect(x: region.minX, y: region.minY, width: cut.minX - region.minX, height: region.height),
				CGRect(x: region.minX, y: region.minY, width: region.width, height: cut.minY - region.minY)
			].filter { $0.width >= 44 && $0.height >= 44 }
			if let best = candidates.max(by: { $0.width * $0.height < $1.width * $1.height }) {
				region = best
			}
		}
		return region
	}

	static func pixelSize(_ size: CGSize, scale: CGFloat) -> CGSize? {
		guard valid(size), scale.isFinite, scale > 0 else { return nil }
		// Video encoders generally require even dimensions.
		return CGSize(width: max(2, floor(size.width * scale / 2) * 2),
					  height: max(2, floor(size.height * scale / 2) * 2))
	}
}
