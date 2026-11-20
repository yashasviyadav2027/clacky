import Foundation

/// Silly, non-keyboard sound packs. A same-named folder in the user's Packs folder
/// (e.g. a real recording in Packs/Duck) replaces the generated fallback.
enum FunSound: String, CaseIterable {
    case duck = "Duck"

    var blurb: String {
        switch self {
        case .duck: return "A quack on every key 🦆"
        }
    }

    func render(_ kind: SoundKind, variant: Int) -> [Float] {
        var rng = SplitMix64(seed: UInt64(variant * 7919 + kindIndex(kind) * 104_729 + 17))
        switch self {
        case .duck: return FunSynth.duck(kind, &rng)
        }
    }

    private func kindIndex(_ kind: SoundKind) -> Int {
        SoundKind.allCases.firstIndex(of: kind) ?? 0
    }
}

/// Two-pole resonant bandpass — used as a formant of the quack.
private struct Resonator {
    private var y1 = 0.0, y2 = 0.0

    mutating func process(_ x: Double, freq: Double, bandwidth: Double) -> Double {
        let sr = Synth.sampleRate
        let r = exp(-Double.pi * bandwidth / sr)
        let y = (1 - r) * x + 2 * r * cos(2 * Double.pi * freq / sr) * y1 - r * r * y2
        y2 = y1
        y1 = y
        return y
    }
}

enum FunSynth {
    private static let sr = Synth.sampleRate

    // MARK: Duck

    static func duck(_ kind: SoundKind, _ rng: inout SplitMix64) -> [Float] {
        switch kind {
        case .up: return []
        case .enter:
            return concat(quack(pitch: 1.05, length: 0.13, &rng), gap: 0.04, quack(pitch: 0.95, length: 0.17, &rng))
        case .space: return quack(pitch: 0.75, length: 0.26, &rng)
        case .backspace: return quack(pitch: 1.25, length: 0.12, &rng)
        case .down: return quack(pitch: Double.random(in: 0.9...1.15, using: &rng), length: 0.16, &rng)
        }
    }

    private static func quack(pitch: Double, length: Double, _ rng: inout SplitMix64) -> [Float] {
        let n = Int(length * sr)
        var out = [Float](repeating: 0, count: n)
        var f1 = Resonator(), f2 = Resonator(), f3 = Resonator()
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sr, x = t / length
            let f0 = (520 - 160 * x) * pitch                     // falling "kwaaa"
            phase = (phase + f0 / sr).truncatingRemainder(dividingBy: 1)
            let rasp = 1 + 0.35 * sin(2 * Double.pi * 38 * t)  // throaty wobble
            let source = (phase < 0.22 ? 1.0 : -0.28) * rasp + 0.08 * Double.random(in: -1...1, using: &rng)
            let y = f1.process(source, freq: (950 - 250 * x) * pitch, bandwidth: 160)
                + 0.7 * f2.process(source, freq: 1750 * pitch, bandwidth: 200)
                + 0.35 * f3.process(source, freq: 2900, bandwidth: 260)
            let env = min(t / 0.008, 1) * pow(1 - x, 1.4)
            out[i] = Float(y * env)
        }
        return normalized(out, peak: 0.35)
    }

    // MARK: Helpers

    private static func concat(_ a: [Float], gap: Double, _ b: [Float]) -> [Float] {
        a + [Float](repeating: 0, count: Int(gap * sr)) + b
    }

    private static func normalized(_ s: [Float], peak target: Float) -> [Float] {
        var s = s
        let peak = s.reduce(0) { max($0, abs($1)) }
        if peak > 0 { for i in s.indices { s[i] *= target / peak } }
        let fade = min(s.count, Int(0.008 * sr))
        for i in 0..<fade { s[s.count - 1 - i] *= Float(i) / Float(fade) }
        return s
    }
}
