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
		// Log the touch location
		print("Touch location: \(location)")
		print("Touch type: \(typeOfTap)")
		print("Touch state: \(state)")

		// print("Touch finger count:" \(pointerId))
		// Convert the touch location to the host's coordinate system
		let screenWidth = UIScreen.main.bounds.width
		let screenHeight = UIScreen.main.bounds.height
		let x = Int32(location.x * CGFloat(CParsec.hostWidth) / screenWidth)
		let y = Int32(location.y * CGFloat(CParsec.hostHeight) / screenHeight)

		// Log the screen and host dimensions and calculated coordinates
//		print("Screen dimensions: \(screenWidth) x \(screenHeight)")
//		print("Host dimensions: \(CParsec.hostWidth) x \(CParsec.hostHeight)")
//		print("Calculated coordinates: (\(x), \(y))")

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

		// print("Touch finger count:" \(pointerId))
		// Convert the touch location to the host's coordinate system
		let screenWidth = UIScreen.main.bounds.width
		let screenHeight = UIScreen.main.bounds.height
		let x = Int32(location.x * CGFloat(CParsec.hostWidth) / screenWidth)
		let y = Int32(location.y * CGFloat(CParsec.hostHeight) / screenHeight)

//		// Log the screen and host dimensions and calculated coordinates
//		print("Screen dimensions: \(screenWidth) x \(screenHeight)")
//		print("Host dimensions: \(CParsec.hostWidth) x \(CParsec.hostHeight)")
//		print("Calculated coordinates: (\(x), \(y))")

		// Send the mouse input to the host
		let parsecTap = ParsecMouseButton(rawValue:UInt32(typeOfTap))
		CParsec.sendMouseMessage(parsecTap, x, y, true)
		CParsec.sendMouseMessage(parsecTap, x, y, false)
	}

	public func viewDidLoad()
	{


		
	}



	
}
