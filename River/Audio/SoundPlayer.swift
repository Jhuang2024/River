import Foundation
import AVFoundation

/// Small synthesized sound set (no bundled assets): short, quiet, physical
/// clicks and thuds. All generation happens once at startup.
final class SoundPlayer {
    enum Effect {
        case cardDeal
        case chipBet
        case check
        case fold
        case allIn
        case win
        case lose
    }

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private let format: AVAudioFormat
    private var started = false

    var enabled: Bool = true

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
            ?? AVAudioFormat()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.5
        buildBuffers()
    }

    private func startIfNeeded() {
        guard !started else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            playerNode.play()
            started = true
        } catch {
            // Sound is non-essential; fail silently and keep the game running.
            started = false
        }
    }

    func play(_ effect: Effect) {
        guard enabled else { return }
        startIfNeeded()
        guard started else { return }
        let key: String
        switch effect {
        case .cardDeal: key = "deal"
        case .chipBet: key = "chip"
        case .check: key = "check"
        case .fold: key = "fold"
        case .allIn: key = "allin"
        case .win: key = "win"
        case .lose: key = "lose"
        }
        if let buffer = buffers[key] {
            playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        }
    }

    // MARK: - Synthesis

    private func buildBuffers() {
        buffers["deal"] = makeNoiseTap(duration: 0.05, brightness: 0.7, volume: 0.35)
        buffers["chip"] = makeTone(frequencies: [1900, 2400], duration: 0.06, volume: 0.28)
        buffers["check"] = makeTone(frequencies: [700], duration: 0.05, volume: 0.22)
        buffers["fold"] = makeNoiseTap(duration: 0.09, brightness: 0.3, volume: 0.2)
        buffers["allin"] = makeTone(frequencies: [520, 780], duration: 0.35, volume: 0.3)
        buffers["win"] = makeTone(frequencies: [660, 880, 990], duration: 0.5, volume: 0.3)
        buffers["lose"] = makeTone(frequencies: [330, 262], duration: 0.4, volume: 0.22)
    }

    /// Short sine chord with a fast exponential decay envelope.
    private func makeTone(frequencies: [Double], duration: Double, volume: Float) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frames = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        guard let data = buffer.floatChannelData?[0] else { return nil }
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let envelope = exp(-t * 9.0)
            var sample = 0.0
            for (index, frequency) in frequencies.enumerated() {
                let stagger = Double(index) * 0.05
                if t >= stagger {
                    sample += sin(2 * .pi * frequency * (t - stagger)) * exp(-(t - stagger) * 8.0)
                }
            }
            data[i] = Float(sample / Double(max(1, frequencies.count)) * envelope) * volume
        }
        return buffer
    }

    /// Filtered noise burst: the sound of a card sliding or hitting felt.
    private func makeNoiseTap(duration: Double, brightness: Double, volume: Float) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frames = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        guard let data = buffer.floatChannelData?[0] else { return nil }
        var previous: Double = 0
        var seed: UInt64 = 0x1234_5678
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let envelope = exp(-t * 40.0)
            // Cheap deterministic white noise.
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let white = Double(Int64(bitPattern: seed >> 11)) / Double(Int64.max)
            // One-pole low-pass; brightness controls the cutoff blend.
            previous = previous + (white - previous) * (0.15 + brightness * 0.7)
            data[i] = Float(previous * envelope) * volume
        }
        return buffer
    }
}
