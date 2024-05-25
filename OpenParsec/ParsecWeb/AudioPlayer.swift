//
//  AudioPlayer.swift
//  OpenParsec
//
//  Created by s s on 2024/5/20.
//

import Foundation
import AVFoundation

class AudioPlayer {
	
	public var ctx : OpaquePointer!
	private let _audioPtr:UnsafeMutableRawPointer

	init() {
		audio_init(&ctx)
		self._audioPtr = unsafeBitCast(ctx, to: UnsafeMutableRawPointer.self)
	}
	
	deinit {
		audio_destroy(&ctx)
	}
	

	func play(buffer: AVAudioPCMBuffer) {
		audio_cb(buffer.int16ChannelData![0], buffer.frameLength, _audioPtr)
	}
	

	func stop() {
		audio_clear(&ctx)
	}
	
	func setMuted(_ muted:Bool)
	{
		audio_mute(muted, _audioPtr)
	}
}
