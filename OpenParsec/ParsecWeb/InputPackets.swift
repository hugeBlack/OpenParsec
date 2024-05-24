//
//  InputPackets.swift
//  OpenParsec
//
//  Created by s s on 2024/5/24.
//

import Foundation

protocol ParsecWebControlPacket {
	func getPacket() -> Data
}

struct MouseMovePacket : ParsecWebControlPacket {
	let x: Int
	let y: Int
	let relative: Bool
	
	func getPacket() -> Data{
		let ptr = ParsecWebDataParser.get13ByteBuffer()
		if relative {
			ParsecWebDataParser.setCommandBytes(ptr: ptr, command: 3, p1: 1, p2: Int32(x), p3: Int32(y))
		} else {
			let coord = CursorPositionHelper.toHost(x, y)
			ParsecWebDataParser.setCommandBytes(ptr: ptr, command: 3, p1: 0, p2: Int32(coord.0), p3: Int32(coord.1))
		}

		let ans = Data(bytes: ptr, count: 13)
		ptr.deallocate()
		return ans

	}
}

struct MouseButtonPacket : ParsecWebControlPacket {
	let button: UInt32
	let pressed: Bool
	
	func getPacket() -> Data{
		let ptr = ParsecWebDataParser.get13ByteBuffer()
		ParsecWebDataParser.setCommandBytes(ptr: ptr, command: 1, p1: Int32(button), p2: self.pressed ? 1 : 0, p3: 0)
		let ans = Data(bytes: ptr, count: 13)
		ptr.deallocate()
		return ans

	}
}

struct MouseWheelPacket : ParsecWebControlPacket {
	let x: Int32
	let y: Int32
	
	func getPacket() -> Data{
		let ptr = ParsecWebDataParser.get13ByteBuffer()
		ParsecWebDataParser.setCommandBytes(ptr: ptr, command: 2, p1: x, p2: y, p3: 0)
		let ans = Data(bytes: ptr, count: 13)
		ptr.deallocate()
		return ans

	}
}

struct KeyboardPacket : ParsecWebControlPacket {
	// {code: 26, mod: 0, type: 1, pressed: true}
	let code: Int32
	let mod: Int32
	let pressed: Bool
	
	func getPacket() -> Data{
		let ptr = ParsecWebDataParser.get13ByteBuffer()
		ParsecWebDataParser.setCommandBytes(ptr: ptr, command: 0, p1: code, p2: mod, p3: self.pressed ? 1 : 0)
		let ans = Data(bytes: ptr, count: 13)
		ptr.deallocate()
		return ans

	}
}
