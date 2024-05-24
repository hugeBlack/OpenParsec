//
//  ControlChannelDelegate.swift
//  OpenParsec
//
//  Created by s s on 2024/5/24.
//

import Foundation
import WebRTC
import ParsecSDK

class ControlChannelDelegate: NSObject, RTCDataChannelDelegate {
	let buffer: ParsecWebBuffer
	init(buffer: ParsecWebBuffer) {
		self.buffer = buffer
	}
	
	func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
		// 控制通道切换为open后要发送一个控制消息,这样host才会开始发送数据
		if (dataChannel.readyState != .open) {
			return
		}
		let data = ParsecWebDataParser.getResolutionByte(1920, 1080)
		dataChannel.sendData(RTCDataBuffer.init(data: data, isBinary: true))
		buffer.parsecStatus = ParsecStatus(0)
	}
	
	func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
		let status = buffer.data
		status.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
			let ptr2 = ptr.baseAddress
			let type = ptr2?.load(fromByteOffset: 12, as: UInt8.self)
			
			switch type {
			case 10:
				// host force update client status
				let p1 = ptr2?.load(fromByteOffset: 0, as: UInt32.self).byteSwapped
				self.buffer.parsecStatus = ParsecStatus(Int32(p1!))
				break
			case 21:
				// host report status
				let p2 = ptr2?.load(fromByteOffset: 4, as: UInt32.self).byteSwapped
				self.buffer.exStatus.`self`.metrics.0.encodeLatency = Float(p2!) / 1000
				break
			case 20:
				// gamepad info
				break
			case 16:
				// unknow
				break
			case 28:
				// host mode
				break
			case 17:
				// host info
				break
			case 9:
				// mouse event
				handleMouseUpdateMsg(ptr: ptr2!)
				break
				
			case 25:
				// guests info
				break

			default:
				print("Got control msg type: \(type!)")
			}
			
			
		}

	}
	
	func handleMouseUpdateMsg(ptr: UnsafeRawPointer) {
		let mouseFlags = ptr.load(fromByteOffset: 32, as: Int16.self).byteSwapped
		let cursorImgSize = ptr.load(fromByteOffset: 16, as: Int32.self).byteSwapped
		
		// 鼠标从相对模式改为绝对模式时再更新位置,不然位置会跳
		buffer.mouseInfo.cursorHidden = ((mouseFlags & 512) != 0)
		if ((mouseFlags & 256) == 0) && buffer.mouseInfo.mousePositionRelative {
			let mouseNewX = Int32(ptr.load(fromByteOffset: 24, as: Int16.self).byteSwapped)
			let mouseNewY = Int32(ptr.load(fromByteOffset: 26, as: Int16.self).byteSwapped)
			let newCoord = CursorPositionHelper.toClient(Int(mouseNewX), Int(mouseNewY))
			buffer.mouseInfo.mouseX = Int32(newCoord.0)
			buffer.mouseInfo.mouseY = Int32(newCoord.1)
		}
		
		buffer.mouseInfo.mousePositionRelative = ((mouseFlags & 256) != 0)
		
		buffer.mouseInfo.cursorWidth = Int(ptr.load(fromByteOffset: 20, as: Int16.self).byteSwapped)
		buffer.mouseInfo.cursorHeight = Int(ptr.load(fromByteOffset: 22, as: Int16.self).byteSwapped)
		buffer.mouseInfo.cursorHotX = Int(ptr.load(fromByteOffset: 28, as: Int16.self).byteSwapped)
		buffer.mouseInfo.cursorHotY = Int(ptr.load(fromByteOffset: 30, as: Int16.self).byteSwapped)

		
		let cursorImgPtr = ptr.advanced(by: 34)
		if cursorImgSize > 0 {
			let cgimage = UIImage(data: Data(bytes: cursorImgPtr, count: Int(cursorImgSize)))?.cgImage
			
			buffer.mouseInfo.cursorImg = cgimage
		}
		
	}
	
}
