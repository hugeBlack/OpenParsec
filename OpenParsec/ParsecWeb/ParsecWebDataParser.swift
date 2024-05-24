//
//  ParsecWebDataParser.swift
//  OpenParsec
//
//  Created by s s on 2024/5/18.
//

import Foundation

struct ParsecConfig : Codable {
	var _version = 1
	var _max_w = 6E4
	var _max_h = 6E4
	var _flags = 0
	var resolutionX: Int
	var resolutionY: Int
	var refreshRate = 60
	var mediaContainer = 0
}

class ParsecWebDataParser {
	static func getResolutionByte(_ resolutionX: Int,_ resolutionY: Int) -> Data {
		let config = ParsecConfig(resolutionX: resolutionX, resolutionY: resolutionY)
		let encoder = JSONEncoder()
		let s = try! encoder.encode(config)
		let ptr = UnsafeMutableRawPointer.allocate(byteCount: 14 + s.count, alignment: 1)
		setCommandBytes(ptr: ptr, command: 11, p1: Int32(s.count + 1), p2: 0, p3: 0)
		let ptrStr = ptr.advanced(by: 13)
		s.copyBytes(to: ptrStr.assumingMemoryBound(to: UInt8.self), count: s.count)
		let ans = Data(bytes: ptr, count: 14 + s.count)
		ptr.deallocate()
		return ans
	}
	
	// Remember to dealloc
	static func get13ByteBuffer() -> UnsafeMutableRawPointer {
		return UnsafeMutableRawPointer.allocate(byteCount: 13, alignment: 1)
	}
	
	static func setCommandBytes(ptr: UnsafeMutableRawPointer, command: UInt8, p1: Int32, p2: Int32, p3: Int32) {
		ptr.storeBytes(of: p1.bigEndian, toByteOffset: 0, as: Int32.self)
		ptr.storeBytes(of: p2.bigEndian, toByteOffset: 4, as: Int32.self)
		ptr.storeBytes(of: p3.bigEndian, toByteOffset: 8, as: Int32.self)
		ptr.storeBytes(of: command, toByteOffset: 12, as: UInt8.self)
		
	}
}

