import Foundation
import UIKit


// from UTM's https://github.com/utmapp/UTM/blob/b03486b8825d5a0e8b9f93162a49a4c98ebab6a1/Platform/iOS/UTMPatches.swift#L33
final class UTMViewControllerPatches {
	static private var isPatched: Bool = false

	/// Installs the patches
	/// Deferred to next run loop to avoid conflicts with GPU debugger initialization
	static func patchAll() {
		guard !isPatched else { return }
		isPatched = true

		// Defer patching to avoid deadlock with GPU tools initialization during dyld loading
		DispatchQueue.main.async {
			UIViewController.patchViewController()
		}
	}
}

fileprivate extension NSObject {
	static func patch(_ original: Selector, with swizzle: Selector, class cls: AnyClass?) {
		let originalMethod = class_getInstanceMethod(cls, original)!
		let swizzleMethod = class_getInstanceMethod(cls, swizzle)!
		method_exchangeImplementations(originalMethod, swizzleMethod)
	}
}

/// We need to set these when the VM starts running since there is no way to do it from SwiftUI right now
extension UIViewController {
	// Q4: these used `[UIViewController: UIViewController]`, which strongly
	// retains BOTH the parent VC (key) and the ParsecViewController (value).
	// If teardown's nil-clear didn't run (abnormal disconnect), the entry — and
	// with it the GLKView + every gesture recognizer hanging off the Parsec VC —
	// leaked for the lifetime of the process, accumulating one set per reconnect.
	// NSMapTable.weakToWeakObjects() holds neither side, so a dropped VC
	// deallocates and its entry auto-empties even without an explicit clear.
	private static let _childForHomeIndicatorAutoHiddenStorage = NSMapTable<UIViewController, UIViewController>.weakToWeakObjects()

	@objc private dynamic var _childForHomeIndicatorAutoHidden: UIViewController? {
		Self._childForHomeIndicatorAutoHiddenStorage.object(forKey: self)
	}

	@objc dynamic func setChildForHomeIndicatorAutoHidden(_ value: UIViewController?) {
		if let value = value {
			Self._childForHomeIndicatorAutoHiddenStorage.setObject(value, forKey: self)
		} else {
			Self._childForHomeIndicatorAutoHiddenStorage.removeObject(forKey: self)
		}
		setNeedsUpdateOfHomeIndicatorAutoHidden()
	}

	private static let _childViewControllerForPointerLockStorage = NSMapTable<UIViewController, UIViewController>.weakToWeakObjects()

	@objc private dynamic var _childViewControllerForPointerLock: UIViewController? {
		Self._childViewControllerForPointerLockStorage.object(forKey: self)
	}

	@objc dynamic func setChildViewControllerForPointerLock(_ value: UIViewController?) {
		if let value = value {
			Self._childViewControllerForPointerLockStorage.setObject(value, forKey: self)
		} else {
			Self._childViewControllerForPointerLockStorage.removeObject(forKey: self)
		}
		setNeedsUpdateOfPrefersPointerLocked()
	}
	
	/// SwiftUI currently does not provide a way to set the View Conrtoller's home indicator or pointer lock
	fileprivate static func patchViewController() {
		patch(#selector(getter: Self.childForHomeIndicatorAutoHidden),
			  with: #selector(getter: Self._childForHomeIndicatorAutoHidden),
			  class: Self.self)
		patch(#selector(getter: Self.childViewControllerForPointerLock),
			  with: #selector(getter: Self._childViewControllerForPointerLock),
			  class: Self.self)
	}
}
