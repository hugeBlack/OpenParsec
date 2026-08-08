import Foundation
import SwiftUI
import ParsecSDK
import os

var appScheme: ColorScheme = .dark

struct GLBData {
	let SessionKeyChainKey = "OPStoredAuthData"
}

class GLBDataModel {
	static let shared = GLBData()
}

extension String {
	static func fromBuffer(_ ptr: UnsafeMutablePointer<CChar>, length len: Int) -> String {
		// convert C char bytes using the UTF8 encoding
		let nsstr = NSString(bytes: ptr, length: len, encoding: NSUTF8StringEncoding)
		return nsstr! as String
	}
}

class CursorPositionHelper {
	static func toHost(_ xp: Int, _ yp: Int) -> (Int, Int) {
		let xh = CParsec.hostWidth
		let yh = CParsec.hostHeight
		let xc = CParsec.clientWidth
		let yc = CParsec.clientHeight

		let tc = yc / xc
		let th = yh / xh

		var xa: Float
		var ya: Float
		if th < tc {
			xa = Float(xp) * xh / xc
			ya = (Float(yp) - 0.5 * (yc - xc*th)) * xh / xc
		} else {
			ya = Float(yp) * yh / yc
			xa = (Float(xp) - 0.5 * (xc - yc/th)) * yh / yc
		}

		return (Int(ParsecSDKBridge.clamp(xa, minValue: 0, maxValue: CParsec.hostWidth)), Int(ParsecSDKBridge.clamp(ya, minValue: 0, maxValue: CParsec.hostHeight)))
	}

	static func toClient(_ xa: Int, _ ya: Int) -> (Int, Int) {
		let xh = CParsec.hostWidth
		let yh = CParsec.hostHeight
		let xc = CParsec.clientWidth
		let yc = CParsec.clientHeight

		let tc = yc / xc
		let th = yh / xh

		var xp: Float
		var yp: Float
		if th < tc {
			xp = Float(xa) * xc / xh
			yp = Float(ya) * xc / xh + 0.5 * (yc - xc*th)
		} else {
			yp = Float(ya) * yc / yh
			xp = Float(xa) * yc / yh + 0.5 * (xc - yc/th)
		}

		return (Int(ParsecSDKBridge.clamp(xp, minValue: 0, maxValue: CParsec.clientWidth)), Int(ParsecSDKBridge.clamp(yp, minValue: 0, maxValue: CParsec.clientHeight)))
	}
}

class SharedModel: ObservableObject {
	@Published var resolutionX = 0
	@Published var resolutionY = 0
	@Published var bitrate = 0
	@Published var constantFps = false
	@Published var output = "none"
	@Published var displayConfigs: [ParsecDisplayConfig] = []
	@Published var isBlocked = false

}

class DataManager {
	static let model = SharedModel()
}

extension ParsecStatus {
	func readable(connecting: Bool = false) -> String {
		switch self {
		case WS_ERR_AUTH:               return "Authentication failed"
		case WS_ERR_CONNECT:            return "Can't reach Parsec"
		case WS_ERR_TEAM_DEACTIVATED:   return "Team account deactivated"
		case NAT_ERR_PEER_PHASE:        return "Couldn't reach the host"
		case NETWORK_ERR_BG_TIMEOUT:    return "Timed out in the background"
		case NETWORK_ERR_UNSUPPORTED:   return "Network not supported"
		case CONNECT_WRN_DECLINED:      return "Host declined the connection"
		case CONNECT_WRN_NO_PERMISSION: return "No permission to connect"
		case CONNECT_WRN_NO_ROOM:       return "Host is full"
		case CONNECT_WRN_CANCELED:      return "Connection canceled"
		case CONNECT_WRN_PEER_GONE:     return "Host is offline"
		case HOST_WRN_KICKED:           return "Kicked by the host"
		case HOST_WRN_SHUTDOWN:         return "Host shut down"
		case SERVER_ERR_DISPLAY:        return "Host has no display"
		case SERVER_ERR_RESOLUTION:     return "Host resolution problem"
		case CAPTURE_ERR_INIT:          return "Host capture failed"
		default:
			os_log("%{public}@", "[status] no text for \(rawValue)")
			return "\(connecting ? "Couldn't connect" : "Disconnected") (code \(rawValue))"
		}
	}

	var isPermanentFailure: Bool {
		switch self {
		case WS_ERR_AUTH, WS_ERR_TEAM_DEACTIVATED,
			 CONNECT_WRN_DECLINED, CONNECT_WRN_NO_PERMISSION, CONNECT_WRN_NO_ROOM,
			 CONNECT_WRN_CANCELED,
			 HOST_WRN_KICKED, HOST_WRN_SHUTDOWN,
			 NETWORK_ERR_UNSUPPORTED, SERVER_ERR_DISPLAY, SERVER_ERR_RESOLUTION:
			return true
		default:
			return false
		}
	}
}
