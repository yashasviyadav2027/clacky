import Foundation

enum SoundKind: CaseIterable {
    case down, up, space, enter, backspace
}

/// A damped sine "mode" — one resonance of the switch/plate/case.
struct Mode {
    let freq: ClosedRange<Double>
    let decay: Double // seconds (time constant)
    let amp: Double
}

struct Profile {
    let name: String
    let modes: [Mode]
    let noiseAmp: Double
    let noiseDecay: Double
    let noiseBrightness: Double // one-pole lowpass coefficient, 0 (dark) ... 1 (bright)
    let clickJacket: Bool       // blue-switch style click before bottom-out

    static let builtIn: [Profile] = [
        Profile(name: "Thocky",
                modes: [Mode(freq: 140...185, decay: 0.020, amp: 0.9),
                        Mode(freq: 420...600, decay: 0.011, amp: 0.45),
                        Mode(freq: 1700...2300, decay: 0.003, amp: 0.2)],
                noiseAmp: 0.35, noiseDecay: 0.0025, noiseBrightness: 0.25, clickJacket: false),
        Profile(name: "Creamy",
                modes: [Mode(freq: 210...270, decay: 0.013, amp: 0.75),
                        Mode(freq: 650...900, decay: 0.008, amp: 0.45),
                        Mode(freq: 2400...3100, decay: 0.0025, amp: 0.3)],
                noiseAmp: 0.4, noiseDecay: 0.002, noiseBrightness: 0.4, clickJacket: false),
        Profile(name: "Clacky",
                modes: [Mode(freq: 300...380, decay: 0.008, amp: 0.45),
                        Mode(freq: 1050...1450, decay: 0.006, amp: 0.6),
                        Mode(freq: 3400...4400, decay: 0.002, amp: 0.5)],
                noiseAmp: 0.6, noiseDecay: 0.0015, noiseBrightness: 0.75, clickJacket: false),
        Profile(name: "Clicky",
                modes: [Mode(freq: 260...330, decay: 0.010, amp: 0.55),
                        Mode(freq: 900...1200, decay: 0.006, amp: 0.5),
                        Mode(freq: 3000...3800, decay: 0.002, amp: 0.35)],
                noiseAmp: 0.5, noiseDecay: 0.0015, noiseBrightness: 0.7, clickJacket: true),
    ]
}

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Procedurally renders keystroke sounds: a noise transient plus a few damped resonances.
enum Synth {
    static let sampleRate = 48_000.0

    static func render(_ p: Profile, kind: SoundKind, seed: UInt64) -> [Float] {
        var rng = SplitMix64(seed: seed)
        var pitch = 1.0, decayMul = 1.0, gain = 1.0, length = 0.12
        var stabilized = false
        switch kind {
        case .down: break
        case .up: pitch = 1.3; decayMul = 0.55; gain = 0.4
        case .space: pitch = 0.7; decayMul = 1.7; length = 0.2; stabilized = true
        case .enter: pitch = 0.82; decayMul = 1.3; gain = 0.95; length = 0.16; stabilized = true
        case .backspace: pitch = 0.88; decayMul = 1.2; gain = 0.9; length = 0.15; stabilized = true
        }
        pitch *= Double.random(in: 0.95...1.05, using: &rng)

        let n = Int(sampleRate * length)
        var out = [Float](repeating: 0, count: n)

        func addMode(freq: Double, decay: Double, amp: Double, at start: Double) {
            let s = Int(start * sampleRate)
            guard s < n else { return }
            let w = 2 * Double.pi * freq / sampleRate
            for i in s..<n {
                let t = Double(i - s)
                out[i] += Float(amp * exp(-t / (decay * sampleRate)) * sin(w * t))
            }
        }

        func addNoise(amp: Double, decay: Double, brightness: Double, at start: Double) {
            let s = Int(start * sampleRate)
            guard s < n else { return }
            var lp = 0.0
            let end = min(n, s + Int(decay * 8 * sampleRate))
            for i in s..<end {
                let t = Double(i - s)
                lp += brightness * (Double.random(in: -1...1, using: &rng) - lp)
                out[i] += Float(amp * exp(-t / (decay * sampleRate)) * lp)
            }
        }

        func addImpact(at start: Double, scale: Double, pitchMul: Double) {
            for m in p.modes {
                addMode(freq: Double.random(in: m.freq, using: &rng) * pitch * pitchMul,
                        decay: m.decay * decayMul * Double.random(in: 0.85...1.15, using: &rng),
                        amp: m.amp * scale * Double.random(in: 0.8...1.2, using: &rng),
                        at: start)
            }
            addNoise(amp: p.noiseAmp * scale, decay: p.noiseDecay * decayMul,
                     brightness: p.noiseBrightness, at: start)
        }

        var impact = 0.0
        if p.clickJacket {
            let clickAmp = kind == .up ? 0.5 : 0.9
            addNoise(amp: clickAmp, decay: 0.0004, brightness: 0.95, at: 0)
            addMode(freq: Double.random(in: 4500...5500, using: &rng), decay: 0.0015, amp: clickAmp * 0.6, at: 0)
            impact = kind == .up ? 0.003 : 0.007
        }
        addImpact(at: impact, scale: 1, pitchMul: 1)
        if stabilized {
            // Stabilizer wire settling a few ms after the main hit.
            addImpact(at: impact + Double.random(in: 0.005...0.009, using: &rng), scale: 0.25, pitchMul: 1.6)
        }

        let peak = out.reduce(0) { max($0, abs($1)) }
        if peak > 0 {
            let k = Float(0.9 / Double(peak) * gain)
            for i in 0..<n { out[i] *= k }
        }
        let fade = Int(0.01 * sampleRate)
        for i in 0..<fade { out[n - 1 - i] *= Float(i) / Float(fade) }
        return out
    }
}
