import AVFoundation

/// Tiny synth for the per-occurrence stings (GDD §8): each sound is rendered once into a PCM buffer.
final class Synth {
    enum Sound: CaseIterable { case sick, spill, pick, step, ok, fail, nope, ding, chime, rumble, whoa, grumble, grumbleLoud, paChime }
    enum Wave { case sine, square, triangle, saw }
    struct Tone { let f: Double; let d: Double; let wave: Wave; let v: Double; let delay: Double; let f2: Double? }

    var muted = false
    /// Master volume from Options (0…1).
    var volume: Float = 0.8 { didSet { engine.mainMixerNode.outputVolume = volume } }
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var started = false

    // The captain on the cabin PA (GDD §8b): text-to-speech through a band-pass + radio distortion.
    private let speech = AVSpeechSynthesizer()
    private let voicePlayer = AVAudioPlayerNode()
    private let paBand = AVAudioUnitEQ(numberOfBands: 2)
    private let paRadio = AVAudioUnitDistortion()
    private var voiceFormat: AVAudioFormat?
    private lazy var captainVoice: AVSpeechSynthesisVoice? = {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        return english.first { $0.gender == .male && $0.quality != .default }
            ?? english.first { $0.gender == .male }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    init() {
        for s in Sound.allCases { buffers[s] = render(Synth.recipe(s)) }
        for _ in 0..<6 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        // PA chain: voice → band-pass (like a small ceiling speaker) → radio distortion → mixer
        let lowCut = paBand.bands[0], highCut = paBand.bands[1]
        lowCut.filterType = .highPass; lowCut.frequency = 320; lowCut.bypass = false
        highCut.filterType = .lowPass; highCut.frequency = 3400; highCut.bypass = false
        paRadio.loadFactoryPreset(.speechRadioTower)
        paRadio.wetDryMix = 35
        voicePlayer.volume = 0.9
        [voicePlayer, paBand, paRadio].forEach(engine.attach)
        engine.connect(paBand, to: paRadio, format: nil)
        engine.connect(paRadio, to: engine.mainMixerNode, format: nil)
    }

    /// The captain says a line over the cabin PA. `text` is what's spoken (it can differ from the subtitle).
    func captain(say text: String) {
        guard !muted, started else { return }
        let u = AVSpeechUtterance(string: text)
        u.voice = captainVoice
        u.rate = 0.46
        u.pitchMultiplier = 0.88
        speech.write(u) { [weak self] buffer in
            guard let self, let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else { return }
            DispatchQueue.main.async { self.scheduleVoice(pcm) }
        }
    }

    func stopCaptain() {
        speech.stopSpeaking(at: .immediate)
        voicePlayer.stop()
    }

    private func scheduleVoice(_ pcm: AVAudioPCMBuffer) {
        guard let buffer = floatBuffer(pcm) else { return }
        if voiceFormat != buffer.format {
            voiceFormat = buffer.format
            engine.disconnectNodeOutput(voicePlayer)
            engine.connect(voicePlayer, to: paBand, format: buffer.format)
        }
        if !engine.isRunning { try? engine.start() }
        voicePlayer.scheduleBuffer(buffer, completionHandler: nil)
        if !voicePlayer.isPlaying { voicePlayer.play() }
    }

    /// Speech comes out as 16-bit samples; the player wants float.
    private func floatBuffer(_ pcm: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if pcm.format.commonFormat == .pcmFormatFloat32 { return pcm }
        guard let target = AVAudioFormat(standardFormatWithSampleRate: pcm.format.sampleRate, channels: pcm.format.channelCount),
              let converter = AVAudioConverter(from: pcm.format, to: target),
              let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: pcm.frameLength) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return pcm
        }
        return error == nil ? out : nil
    }

    /// Call from a user action; audio starts only after interaction.
    func warmUp() {
        guard !started else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        do { try engine.start(); started = true } catch { started = false }
    }

    func play(_ s: Sound) {
        guard let buffer = buffers[s] else { return }
        play(buffer)
    }

    private func play(_ buffer: AVAudioPCMBuffer) {
        guard !muted, started else { return }
        if !engine.isRunning { try? engine.start() }
        let p = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        p.stop()
        p.scheduleBuffer(buffer, at: nil)
        p.play()
    }

    static func recipe(_ s: Sound) -> [Tone] {
        switch s {
        case .sick: return [Tone(f: 520, d: 0.14, wave: .square, v: 0.045, delay: 0, f2: nil), Tone(f: 390, d: 0.22, wave: .square, v: 0.045, delay: 0.13, f2: nil)]
        case .spill: return [Tone(f: 900, d: 0.28, wave: .triangle, v: 0.08, delay: 0, f2: 160)]
        case .pick: return [Tone(f: 880, d: 0.06, wave: .sine, v: 0.06, delay: 0, f2: nil)]
        case .step: return [Tone(f: 660, d: 0.1, wave: .sine, v: 0.07, delay: 0, f2: nil)]
        case .ok: return [Tone(f: 660, d: 0.1, wave: .sine, v: 0.08, delay: 0, f2: nil), Tone(f: 990, d: 0.18, wave: .sine, v: 0.08, delay: 0.09, f2: nil)]
        case .fail: return [Tone(f: 150, d: 0.4, wave: .saw, v: 0.05, delay: 0, f2: 80)]
        case .nope: return [Tone(f: 210, d: 0.12, wave: .square, v: 0.04, delay: 0, f2: nil)]
        case .ding: return [Tone(f: 740, d: 0.5, wave: .sine, v: 0.07, delay: 0, f2: nil), Tone(f: 587, d: 0.8, wave: .sine, v: 0.07, delay: 0.35, f2: nil)]
        // seatbelt sign: the classic two-note cabin chime
        case .chime: return [Tone(f: 988, d: 0.6, wave: .sine, v: 0.08, delay: 0, f2: nil), Tone(f: 784, d: 0.9, wave: .sine, v: 0.08, delay: 0.45, f2: nil)]
        case .rumble: return [Tone(f: 70, d: 0.9, wave: .saw, v: 0.06, delay: 0, f2: 45), Tone(f: 95, d: 0.6, wave: .saw, v: 0.04, delay: 0.25, f2: 60)]
        case .whoa: return [Tone(f: 300, d: 0.22, wave: .triangle, v: 0.07, delay: 0, f2: 520)]
        // unattended passengers: a grumble, louder and harsher once critical
        case .grumble: return [Tone(f: 190, d: 0.16, wave: .square, v: 0.03, delay: 0, f2: 150), Tone(f: 170, d: 0.18, wave: .square, v: 0.03, delay: 0.17, f2: 130)]
        // the cabin PA "bing-bong" before the captain speaks
        case .paChime: return [Tone(f: 880, d: 0.8, wave: .sine, v: 0.07, delay: 0, f2: nil), Tone(f: 1760, d: 0.4, wave: .sine, v: 0.015, delay: 0, f2: nil),
                               Tone(f: 698, d: 1.0, wave: .sine, v: 0.07, delay: 0.5, f2: nil)]
        case .grumbleLoud: return [Tone(f: 240, d: 0.14, wave: .saw, v: 0.05, delay: 0, f2: 180), Tone(f: 260, d: 0.14, wave: .saw, v: 0.05, delay: 0.15, f2: 170), Tone(f: 220, d: 0.2, wave: .saw, v: 0.05, delay: 0.3, f2: 140)]
        }
    }

    private func render(_ tones: [Tone]) -> AVAudioPCMBuffer? {
        let sr = format.sampleRate
        let length = (tones.map { $0.delay + $0.d }.max() ?? 0) + 0.05
        let frames = AVAudioFrameCount(length * sr)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let out = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = frames
        for i in 0..<Int(frames) { out[i] = 0 }
        for tone in tones {
            var phase = 0.0
            let start = Int(tone.delay * sr), count = Int(tone.d * sr)
            for n in 0..<count where start + n < Int(frames) {
                let t = Double(n) / sr
                let k = t / tone.d
                let f = tone.f2.map { tone.f * pow($0 / tone.f, k) } ?? tone.f      // exponential glide
                phase += 2 * .pi * f / sr
                let s: Double
                switch tone.wave {
                case .sine: s = sin(phase)
                case .square: s = sin(phase) >= 0 ? 1 : -1
                case .triangle: s = 2 / .pi * asin(sin(phase))
                case .saw: let c = phase / (2 * .pi); s = 2 * (c - (c + 0.5).rounded(.down))
                }
                let gain = tone.v * pow(0.0001 / tone.v, k)                        // exponential decay
                out[start + n] += Float(s * gain * 2.2)
            }
        }
        return buf
    }
}
