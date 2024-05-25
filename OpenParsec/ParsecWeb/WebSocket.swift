//
//  WebSocket.swift
//  OpenParsec
//
//  Created by s s on 2024/5/17.
//
// https://github.com/wix/Detox/blob/ea9f655a1f9202d5b715ae78bcc86c2ad2e72d31/detox/ios/Detox/Utilities/WebSocket.swift#L34
import Foundation

struct ParsecWsMsg<T: Codable> : Codable {
	var action: String
	var payload: T
	var version = 1
}

struct ParsecWsVersions : Codable {
	var audio = 1
	var bud = 1
	var control = 1
	var `init` = 1
	var p2p = 1
	var video = 1
}

struct ParsecWsCred : Codable {
	var fingerprint: String
	var ice_pwd: String
	var ice_ufrag: String
}

struct ParsecWsOfferPayloadData : Codable {
	var mode: Int = 2
	var ver_data: Int = 1
	var versions: ParsecWsVersions = ParsecWsVersions()
	var creds: ParsecWsCred
}

struct ParsecWsOfferPayload : Codable {
	var access_link_id: String = ""
	var attempt_id: String
	var data: ParsecWsOfferPayloadData
	var secret: String = ""
	var to: String
}

struct ParsecWsCandexPayloadData : Codable {
	var from_stun :Bool
	var ip : String
	var lan : Bool
	var port : Int
	var sync : Bool
	var ver_data = 1
	var versions: ParsecWsVersions = ParsecWsVersions()
}

struct ParsecWsCandexPayload : Codable {
	var attempt_id: String
	var data: ParsecWsCandexPayloadData
	var to: String
}


protocol WebSocketDelegate: AnyObject {
	func webSocketDidConnect(_ webSocket: WebSocket)
	func webSocket(_ webSocket: WebSocket, didFailWith error: Error)
	func webSocket(_ webSocket: WebSocket, didReceiveAction type : String, params: [String: Any])
	func webSocket(_ webSocket: WebSocket, didCloseWith reason: String?)
}


class WebSocket : NSObject, URLSessionWebSocketDelegate {
	var sessionId: String?
	private var urlSession: URLSession!
	private var webSocketSessionTask: URLSessionWebSocketTask?
	var delegate: WebSocketDelegate?
	
	override init() {
		super.init()
		urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue.main)
	}
	
	func connect(toServer server: URL) {
		
		webSocketSessionTask = urlSession.webSocketTask(with: server)
		webSocketSessionTask?.resume()
	}
	
	func close() {
		webSocketSessionTask?.cancel(with: .normalClosure, reason: nil)
		webSocketSessionTask = nil
	}
	
	func sendAction<T:Codable>(_ action: String, payload: T) {
		let data = ParsecWsMsg(action: action, payload: payload)
		let encoder = JSONEncoder()
		do {
			let dataStr = String(data: try encoder.encode(data), encoding: .utf8)!
			let message = URLSessionWebSocketTask.Message.string(dataStr)
			webSocketSessionTask?.send(message) { error in
				if let error = error {
					print("Error sending message: \(error.localizedDescription)")
				}
			}
		} catch {
			print("Error encoding message: \(error.localizedDescription)")
		}
	}
	
	func sendMsg(_ msg: String) {
		let message = URLSessionWebSocketTask.Message.string(msg)
		webSocketSessionTask?.send(message) { error in
			if let error = error {
				print("Error sending message: \(error.localizedDescription)")
			}
		}
	}
	
	private func receive() {
		webSocketSessionTask?.receive { [weak self] result in
			switch result {
			case .failure(let error as NSError):
				print("Error receiving message: \(error.localizedDescription)")
			case .success(let message):
				switch message {
				case .string(let string):
					self?.receiveAction(json: string)
				case .data(let data):
					self?.receiveAction(json: String(data: data, encoding: .utf8)!)
				@unknown default:
					fatalError("Unknown websocket message type")
				}
				
				self?.receive()
			}
		}
	}
	
	func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol pr: String?) {
		receive()
		
		delegate?.webSocketDidConnect(self)
	}
	
	
	func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
		let string: String?
		if let reason = reason, let str = String(data: reason, encoding: .utf8) {
			string = str
		} else {
			string = nil
		}
		
		delegate?.webSocket(self, didCloseWith: string)
	}
	
	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		if let error = error {
			delegate?.webSocket(self, didFailWith: error)
		} else {
			delegate?.webSocket(self, didCloseWith: nil)
		}
	}
	
	func receiveAction(json: String) {
		do {
			let jsonData = json.data(using: .utf8)!
			let obj = try JSONSerialization.jsonObject(with: jsonData, options: []) as! [String: Any]
			
			let action = obj["action"] as! String
			let payload = obj["payload"] as? [String: Any]
			
			delegate?.webSocket(self, didReceiveAction: action, params: payload ?? [:])
		} catch {
			print("Error decoding receiveAction decode: \(error.localizedDescription)")
		}
	}
	
}
