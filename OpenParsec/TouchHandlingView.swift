import SwiftUI
import ParsecSDK

extension Unicode.Scalar:Strideable
{
	public func distance(to other:Unicode.Scalar) -> Int
	{
		return Int(other.value - self.value)
	}

	public func advanced(by n:Int) -> Unicode.Scalar
	{
		return Unicode.Scalar(self.value + UInt32(n))!
	}
}

struct TouchHandlingView:UIViewRepresentable
{
	let handleTouch:(ParsecMouseButton, CGPoint, UIGestureRecognizer.State) -> Void
	let handleTap:(ParsecMouseButton, CGPoint) -> Void

	func makeCoordinator() -> Coordinator
	{
		Coordinator(self)
	}

	func makeUIView(context:Context) -> UIView
	{
		let view = UIView()
		view.isMultipleTouchEnabled = true
		view.isUserInteractionEnabled = true
		view.becomeFirstResponder()

		let panGestureRecognizer = UIPanGestureRecognizer(target:context.coordinator, action:#selector(Coordinator.handlePanGesture(_:)))
		panGestureRecognizer.delegate = context.coordinator
		view.addGestureRecognizer(panGestureRecognizer)

		// Add tap gesture recognizer for single-finger touch
		let singleFingerTapGestureRecognizer = UITapGestureRecognizer(target:context.coordinator, action:#selector(Coordinator.handleSingleFingerTap(_:)))
		singleFingerTapGestureRecognizer.numberOfTouchesRequired = 1
		view.addGestureRecognizer(singleFingerTapGestureRecognizer)

		// Add tap gesture recognizer for two-finger touch
		let twoFingerTapGestureRecognizer = UITapGestureRecognizer(target:context.coordinator, action:#selector(Coordinator.handleTwoFingerTap(_:)))
		twoFingerTapGestureRecognizer.numberOfTouchesRequired = 2
		view.addGestureRecognizer(twoFingerTapGestureRecognizer)

		return view
	}

	func updateUIView(_ uiView:UIView, context:Context)
	{
		uiView.becomeFirstResponder()
	}

	class Coordinator:NSObject, UIGestureRecognizerDelegate
	{
		var parent:TouchHandlingView

		init(_ parent:TouchHandlingView)
		{
			self.parent = parent
			super.init()
		}

		@objc func handlePanGesture(_ gestureRecognizer:UIPanGestureRecognizer)
		{
			let location = gestureRecognizer.location(in:gestureRecognizer.view)
			parent.handleTouch(ParsecMouseButton(rawValue:1), location, gestureRecognizer.state)
		}

		@objc func handleSingleFingerTap(_ gestureRecognizer:UITapGestureRecognizer)
		{
			let location = gestureRecognizer.location(in:gestureRecognizer.view)
			parent.handleTap(ParsecMouseButton(rawValue:1), location)
		}

		@objc func handleTwoFingerTap(_ gestureRecognizer:UITapGestureRecognizer)
		{
			let location = gestureRecognizer.location(in: gestureRecognizer.view)
			parent.handleTap(ParsecMouseButton(rawValue:3), location)
		}
	}
}

struct TouchHandlingView_Previews:PreviewProvider
{
	static var previews:some View
	{
		TouchHandlingView(handleTouch:
		{ _, _, _ in
			print("Touch event received in preview")
		}, handleTap:
		{ _, _ in
			print("Tap event received in preview")
		})
	}
}
