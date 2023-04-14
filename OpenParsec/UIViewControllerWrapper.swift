import SwiftUI
import UIKit

struct UIViewControllerWrapper<Wrapped:UIViewController>:UIViewControllerRepresentable
{
	typealias UIViewControllerType = Wrapped

	let wrappedController:Wrapped

	init(_ wrappedController:Wrapped)
	{
		self.wrappedController = wrappedController
	}

	func makeUIViewController(context:Context) -> Wrapped
	{
		return wrappedController
	}

	func updateUIViewController(_ uiViewController:Wrapped, context:Context)
	{
		// No-op
	}
}
