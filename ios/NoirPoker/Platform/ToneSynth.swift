import AVFoundation
import PokerCore

/// Synthesizes the reference's short WebAudio tones natively: notes every
/// 80 ms, gain 0.0001 → 0.025 at 15 ms → 0.0001 at 160 ms, stopped at 200 ms.
/// No audio assets are bundled.
@MainActor
final class ToneSynth {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var buffers: [SoundKind: AVAudioPCMBuffer] = [:]
    private var started = false

    func play(_ kind: SoundKind) {
        guard ensureStarted(), let buffer = buffer(for: kind) else { return }
        player.scheduleBuffer(buffer, at: nil, options: [])
        if !player.isPlaying { player.play() }
    }

    /// Stops output (app background).
    func stop() {
        guard started else { return }
        player.stop()
        engine.pause()
        started = false
    }

    private func ensureStarted() -> Bool {
        if started { return true }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            if engine.attachedNodes.contains(player) == false {
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
            }
            try engine.start()
            started = true
        } catch {
            started = false
        }
        return started
    }

    private func buffer(for kind: SoundKind) -> AVAudioPCMBuffer? {
        if let cached = buffers[kind] { return cached }
        let rate = format.sampleRate
        let notes = kind.notesHz
        let totalSeconds = Double(notes.count - 1) * 0.08 + 0.2
        let frames = AVAudioFrameCount(totalSeconds * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) { data[i] = 0 }
        let triangle = kind.wave == "triangle"
        for (n, hz) in notes.enumerated() {
            let start = Int(Double(n) * 0.08 * rate)
            let length = Int(0.2 * rate)
            for i in 0..<length where start + i < Int(frames) {
                let t = Double(i) / rate
                let phase = (t * Double(hz)).truncatingRemainder(dividingBy: 1)
                let wave = triangle ? (phase < 0.5 ? 4 * phase - 1 : 3 - 4 * phase) : sin(2 * .pi * phase)
                data[start + i] += Float(wave * envelope(t))
            }
        }
        buffers[kind] = buffer
        return buffer
    }

    /// Exponential ramps like `exponentialRampToValueAtTime`.
    private func envelope(_ t: Double) -> Double {
        let low = 0.0001, peak = 0.025
        if t <= 0.015 { return low * pow(peak / low, t / 0.015) }
        if t <= 0.16 { return peak * pow(low / peak, (t - 0.015) / 0.145) }
        return low
    }
}
