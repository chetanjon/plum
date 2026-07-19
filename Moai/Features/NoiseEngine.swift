import AVFoundation

/// Generates ambience in real time with a source node. No audio files,
/// no licensing, works offline, costs nothing. Every level change rides
/// a per-sample gain ramp — nothing clicks, nothing jumps.
final class NoiseEngine {
    enum NoiseColor: String, CaseIterable {
        case brown
        case white
        case pink
        case rain
        case cafe
    }

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var current: NoiseColor = .brown

    // Smoothed master gain, advanced on the render thread.
    private var gain: Float = 0
    private var targetGain: Float = 0

    // Filter state
    private var brownLast: Float = 0
    private var pink0: Float = 0
    private var pink1: Float = 0
    private var pink2: Float = 0
    private var whiteLast: Float = 0

    // Rain: soft wash + stochastic droplet patter + slow swells
    private var rainLow: Float = 0
    private var dropEnv: Float = 0
    private var swellPhase: Double = 0

    // Cafe: low murmur with a wandering babble level + rare clinks
    private var murmurLow: Float = 0
    private var babble: Float = 0.7
    private var babbleTarget: Float = 0.7
    private var babbleCounter = 0
    private var clinkEnv: Float = 0
    private var clinkPhase: Double = 0
    private var clinkFreq: Double = 3000

    private(set) var isRunning = false

    func start(_ color: NoiseColor) {
        current = color
        if source == nil { setup() }
        engine.mainMixerNode.outputVolume = 0.35
        if !engine.isRunning {
            try? engine.start()
        }
        targetGain = 1
        isRunning = true
    }

    func set(_ color: NoiseColor) {
        guard isRunning, color != current else {
            current = color
            return
        }
        // Duck, swap, rise — a hard spectrum change sounds like a glitch.
        targetGain = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, self.isRunning else { return }
            self.current = color
            self.targetGain = 1
        }
    }

    func pause() {
        targetGain = 0
    }

    func resume() {
        targetGain = 1
    }

    func stop() {
        targetGain = 0
        isRunning = false
        // Let the fade finish before the engine goes down.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.isRunning else { return }
            self.engine.stop()
        }
    }

    private func setup() {
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let sample = self.nextSample()
                for buffer in buffers {
                    guard let data = buffer.mData else { continue }
                    let pointer = data.assumingMemoryBound(to: Float.self)
                    pointer[frame] = sample
                }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: nil)
        source = node
    }

    private func nextSample() -> Float {
        // ~50ms exponential ramp at 48k — click-free starts, stops,
        // pauses, and color changes.
        gain += (targetGain - gain) * 0.0004
        if targetGain == 0, gain < 0.0005 { return 0 }

        let white = Float.random(in: -1...1)
        let value: Float
        switch current {
        case .white:
            // Softened: raw full-band white is piercing.
            whiteLast += 0.45 * (white - whiteLast)
            value = whiteLast * 0.8
        case .pink:
            // Kellet economy pink filter
            pink0 = 0.99765 * pink0 + white * 0.0990460
            pink1 = 0.96300 * pink1 + white * 0.2965164
            pink2 = 0.57000 * pink2 + white * 1.0526913
            value = (pink0 + pink1 + pink2 + white * 0.1848) * 0.12
        case .brown:
            brownLast = (brownLast + 0.02 * white) / 1.02
            value = brownLast * 3.2
        case .rain:
            rainLow += 0.22 * (white - rainLow)
            if Float.random(in: 0...1) < 0.0007 {
                dropEnv = min(1, dropEnv + Float.random(in: 0.3...0.8))
            }
            dropEnv *= 0.9992
            swellPhase += 0.05 / 48_000
            let swell = 0.8 + 0.2 * Float(sin(swellPhase * 2 * .pi))
            value = (rainLow * 0.5 + white * dropEnv * 0.35) * swell
        case .cafe:
            murmurLow += 0.06 * (white - murmurLow)
            babbleCounter += 1
            if babbleCounter >= 2400 {
                babbleCounter = 0
                babbleTarget = Float.random(in: 0.35...1.0)
            }
            babble += (babbleTarget - babble) * 0.00025
            if Float.random(in: 0...1) < 0.000008 {
                clinkEnv = Float.random(in: 0.15...0.4)
                clinkFreq = Double.random(in: 1800...4200)
                clinkPhase = 0
            }
            clinkPhase += clinkFreq / 48_000
            clinkEnv *= 0.9993
            let clink = Float(sin(clinkPhase * 2 * .pi)) * clinkEnv
            value = murmurLow * 2.6 * babble + clink * 0.5
        }
        return max(-1, min(1, value)) * gain
    }
}
