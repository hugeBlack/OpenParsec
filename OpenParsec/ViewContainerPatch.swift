//
//  ViewContainerPatch.swift
//  OpenParsec
//
//  Created by s s on 2024/5/12.
//

import Foundation
import UIKit


// from UTM's https://github.com/utmapp/UTM/blob/b03486b8825d5a0e8b9f93162a49a4c98ebab6a1/Platform/iOS/UTMPatches.swift#L33
final class UTMViewControllerPatches {
	static private var isPatched: Bool = false
	
	/// Installs the patches
	/// TODO: Some thread safety/race issues etc
	static func patchAll() {
		UIViewController.patchViewController()
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
	private static var _childForHomeIndicatorAutoHiddenStorage: [UIViewController: UIViewController] = [:]
	
	@objc private dynamic var _childForHomeIndicatorAutoHidden: UIViewController? {
		Self._childForHomeIndicatorAutoHiddenStorage[self]
	}
	
	@objc dynamic func setChildForHomeIndicatorAutoHidden(_ value: UIViewController?) {
		if let value = value {
			Self._childForHomeIndicatorAutoHiddenStorage[self] = value
		} else {
			Self._childForHomeIndicatorAutoHiddenStorage.removeValue(forKey: self)
		}
		setNeedsUpdateOfHomeIndicatorAutoHidden()
	}
	
	private static var _childViewControllerForPointerLockStorage: [UIViewController: UIViewController] = [:]
	
	@objc private dynamic var _childViewControllerForPointerLock: UIViewController? {
		Self._childViewControllerForPointerLockStorage[self]
	}
	
	@objc dynamic func setChildViewControllerForPointerLock(_ value: UIViewController?) {
		if let value = value {
			Self._childViewControllerForPointerLockStorage[self] = value
		} else {
			Self._childViewControllerForPointerLockStorage.removeValue(forKey: self)
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
