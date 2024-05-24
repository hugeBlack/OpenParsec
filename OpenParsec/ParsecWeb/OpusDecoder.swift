// https://github.com/nuclearace/SwiftDiscord/blob/master/Sources/SwiftDiscord/Voice/DiscordOpusCoding.swift

import Opus
import AVFAudio
import Foundation


open class OpusDecoder {
	// MARK: Properties

	/// The number of channels.
	public let channels: Int

	/// The sampling rate.
	public let sampleRate: Int

	private let decoderState: OpaquePointer
	
	private let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 2, interleaved: true)
	// MARK: Initializers

	///
	/// Creates a Decoder that takes Opus encoded data and outputs raw PCM 16-bit-lesample data.
	///
	/// - parameter sampleRate: The sample rate for the decoder. Discord expects this to be 48k.
	/// - parameter channels: The number of channels in the stream to decode, should always be 2.
	/// - parameter gain: The gain for this decoder.
	///
	public init(sampleRate: Int, channels: Int, gain: Int = 0) {
		self.sampleRate = sampleRate
		self.channels = channels

		var err = 0 as Int32

		decoderState = opus_decoder_create(Int32(sampleRate), Int32(channels), &err)

		guard err == 0 else {
			destroyState()
			print("Error!")
			return
		}
	}

	deinit {
		destroyState()
	}

	// MARK: Methods

	private func destroyState() {
		opus_decoder_destroy(decoderState)
	}
	
	public func maxFrameSize(assumingSize size: Int) -> Int {
		return size * channels * MemoryLayout<opus_int16>.size
	}

	///
	/// Decodes Opus data into raw PCM 16-bit-lesample data.
	///
	/// - parameter audio: A pointer to the audio data.
	/// - parameter packetSize: The number of bytes in this packet.
	/// - parameter frameSize: The size of the frame in samples per channel.
	/// - returns: An opus encoded packet.
	///
	open func decode(_ audio: UnsafePointer<UInt8>?, packetSize: Int, frameSize: Int) throws -> AVAudioPCMBuffer {
		let totalSize = frameSize * channels
		let audioBuffer = AVAudioPCMBuffer(pcmFormat: format!, frameCapacity: AVAudioFrameCount(totalSize))!
		
		let decodedSize = Int(opus_decode(decoderState, audio, Int32(packetSize), audioBuffer.int16ChannelData![0], Int32(frameSize), 0))
		
		audioBuffer.frameLength = AVAudioFrameCount(decodedSize)

		return audioBuffer
	}
}
