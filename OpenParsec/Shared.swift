import Foundation
import SwiftUI

var appScheme:ColorScheme = .dark

struct GLBData
{
	let SessionKeyChainKey = "OPStoredAuthData"
}

class GLBDataModel
{
	static let shared = GLBData()
}

extension String
{
	static func fromBuffer(_ ptr:UnsafeMutablePointer<CChar>, length len:Int) -> String
	{
		// convert C char bytes using the UTF8 encoding
		let nsstr = NSString(bytes:ptr, length:len, encoding:NSUTF8StringEncoding)
		return nsstr! as String
	}
}
