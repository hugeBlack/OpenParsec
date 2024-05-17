//
//  ParsecWeb.swift
//  OpenParsec
//
//  Created by s s on 2024/5/17.
//

import Foundation
import ParsecSDK
import WebRTC


class ParsecWeb : ParsecService, WebSocketDelegate{
	public var hostWidth:Float = 0
	public var hostHeight:Float = 0
	
	public var netProtocol:Int32 = 1
	public var mediaContainer:Int32 = 0
	public var pngCursor:Bool = false
	private var remoteUfrag: String = ""
	
	private var parsecStatus: ParsecStatus = ParsecStatus(20)
	
	public var mouseInfo = MouseInfo()
	
	private let client: WebRTCClient
	private let ws = WebSocket()
	
	init() {
		client = WebRTCClient(iceServers: ["stun:stun.parsec.gg:3478"])
		ws.delegate = self
	}
	
	static func parseSDP (_ s: String) -> [String:Any]{
		let f = s.components(separatedBy: "\r\n")
		var g = [String: Any]()
		for line in f {
			let c = line.split(separator: "=", maxSplits: 1).map(String.init)
			if c.count < 2 {
				continue
			}
			let e = c[0]
			let value = c[1]
			if !e.isEmpty {
				if e == "a" {
					if g["a"] == nil {
						g["a"] = [String: String]()
					}
					if var aDict = g["a"] as? [String: String] {
						let parts = value.split(maxSplits: 1, whereSeparator: { $0 == ":" }).map(String.init)
						if parts.count > 1 {
							aDict[parts[0]] = parts[1]
							g["a"] = aDict
						}

					}
				} else {
					g[e] = value
				}
			}
		}
		return g
	}
	
	func webSocketDidConnect(_ webSocket: WebSocket) {
		print("Connected!")
	}
	
	func webSocket(_ webSocket: WebSocket, didFailWith error: any Error) {
		print("Failed!")
	}
	
	func webSocket(_ webSocket: WebSocket, didReceiveAction type: String, params: [String : Any]) {
		print("receive action! \(type)")
		if type == "closed" {
			parsecStatus = ParsecStatus(4)
			self.ws.close()
		} else if type == "candex_relay" {
			let data = params["data"] as! [String : Any]
			let ip = data["ip"] as! String
			let port = data["port"] as! Int
			let from_stun = data["from_stun"] as! Bool
			let sdp = "candidate:2395300328 1 udp 2113937151 \(ip) \(port) typ \(from_stun ? "srflx" : "host") generation 0 ufrag \(self.remoteUfrag) network-cost 50";
			print(sdp)
			let c = RTCIceCandidate(sdp: sdp, sdpMLineIndex: 0, sdpMid: "0")
			self.client.set(remoteCandidate: c, completion: { (err) in
				if let err = err {
					print(err)
				}
			})
		} else if type == "answer_relay" {
			if (!(params["approved"] as! Bool)) {
				self.parsecStatus = ParsecStatus(4)
				return
			}
			let data = params["data"] as! [String : Any]
			let creds = data["creds"] as! [String : Any]
			let fingerprint = creds["fingerprint"] as! String
			let ice_pwd = creds["ice_pwd"] as! String
			let ice_ufrag = creds["ice_ufrag"] as! String
			let g = "v=0\r\no=- 6033582178177519 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\na=group:BUNDLE 0\r\na=msid-semantic: WMS *\r\nm=application 9 DTLS/SCTP 5000\r\nc=IN IP4 0.0.0.0\r\nb=AS:30\r\na=ice-ufrag:\(ice_ufrag)\r\na=ice-pwd:\(ice_pwd)\r\na=ice-options:trickle\r\na=fingerprint:\(fingerprint)\r\na=setup:active\r\na=mid:0\r\na=sendrecv\r\na=sctpmap:5000 webrtc-datachannel 256\r\na=max-message-size:1073741823\r\n"
			client.set(remoteSdp: RTCSessionDescription(type: .answer, sdp: g), completion: {(err) in
				if let err = err {
					print(err)
				}
			})
			print(g)
			self.remoteUfrag = ice_ufrag
		}
	}
	
	func webSocket(_ webSocket: WebSocket, didCloseWith reason: String?) {
		print("close!")
	}


	func connect(_ peerID: String) -> ParsecStatus {
		var urlStr :String = ""
		if let session_id = NetworkHandler.clinfo?.session_id{
			urlStr = "wss://kessel-ws.parsec.app:443/?session_id=\(session_id)&role=client&version=1&build=150-91&sdk_version=393216"
		} else {
			return ParsecStatus(4)
		}
		
		ws.connect(toServer: URL(string: urlStr)!)
		
		print(urlStr)
		
		let attemptId = UUID.init().uuidString

		client.offer(completion: { (sdp) in
			print(sdp)
			let parsed = ParsecWeb.parseSDP(sdp.sdp)["a"] as! [String:String]
			let creds = ParsecWsCred(fingerprint: parsed["fingerprint"]!, ice_pwd: parsed["ice-pwd"]!, ice_ufrag: parsed["ice-ufrag"]!)
			let payloadData = ParsecWsOfferPayloadData(creds: creds)
			let payload = ParsecWsOfferPayload(attempt_id: attemptId, data: payloadData, to: peerID)

			self.ws.sendAction("offer", payload: payload)
	
		})
		
	
		return ParsecStatus(4)
	}

	func disconnect() {
		// Implementation here
	}

	func getStatus() -> ParsecStatus {
		return parsecStatus
	}

	func getStatusEx(_ pcs: inout ParsecClientStatus) -> ParsecStatus {
		return parsecStatus
	}

	func setFrame(_ width: CGFloat, _ height: CGFloat, _ scale: CGFloat) {
		// Implementation here
	}

	func renderGLFrame(timeout: UInt32) {
		// Implementation here
	}

	func pollAudio(timeout: UInt32) {
		// Implementation here
	}

	func pollEvent(timeout: UInt32) {
		// Implementation here
	}

	func setMuted(_ muted: Bool) {
		// Implementation here
	}

	func applyConfig() {
		// Implementation here
	}

	func sendMouseMessage(_ button: ParsecMouseButton, _ x: Int32, _ y: Int32, _ pressed: Bool) {
		// Implementation here
	}

	func sendMouseClickMessage(_ button: ParsecMouseButton, _ pressed: Bool) {
		// Implementation here
	}

	func sendMouseDelta(_ dx: Int32, _ dy: Int32) {
		// Implementation here
	}

	func sendMousePosition(_ x: Int32, _ y: Int32) {
		// Implementation here
	}

	func sendMouseRelativeMove(_ dx: Int32, _ dy: Int32) {
		// Implementation here
	}

	func sendKeyboardMessage(event: KeyBoardKeyEvent) {
		// Implementation here
	}

	func sendGameControllerButtonMessage(controllerId: UInt32, _ button: ParsecGamepadButton, pressed: Bool) {
		// Implementation here
	}

	func sendGameControllerAxisMessage(controllerId: UInt32, _ button: ParsecGamepadAxis, _ value: Int16) {
		// Implementation here
	}

	func sendGameControllerUnplugMessage(controllerId: UInt32) {
		// Implementation here
	}

	func sendWheelMsg(x: Int32, y: Int32) {
		// Implementation here
	}
}
