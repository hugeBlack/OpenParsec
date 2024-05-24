import ParsecSDK
import UIKit

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

class TouchController
{
	let viewController: UIViewController
	init(viewController: UIViewController) {
		self.viewController = viewController
	}
	
	func onTouch(typeOfTap:Int, location:CGPoint, state:UIGestureRecognizer.State)
	{
		let x = Int32(location.x)
		let y = Int32(location.y)


		// Send the mouse input to the host
		let parsecTap = ParsecMouseButton(rawValue:UInt32(typeOfTap))
		switch state
		{
			case .began:
				CParsec.sendMouseMessage(parsecTap, x, y, true)
			case .changed:
				CParsec.sendMousePosition(x, y)
			case .ended, .cancelled:
				CParsec.sendMouseMessage(parsecTap, x, y, false)
			default:
				break
		}
	}

	func onTap(typeOfTap:Int, location:CGPoint)
	{
		// Log the touch location
		print("Touch location: \(location)")
		print("Touch type: \(typeOfTap)")

		let x = Int32(location.x)
		let y = Int32(location.y)

		// Send the mouse input to the host
		let parsecTap = ParsecMouseButton(rawValue:UInt32(typeOfTap))
		CParsec.sendMouseMessage(parsecTap, x, y, true)
		CParsec.sendMouseMessage(parsecTap, x, y, false)
	}

	public func viewDidLoad()
	{


		
	}



	
}
