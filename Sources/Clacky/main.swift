import AppKit
import AVFoundation

// `Clacky --export <dir>` writes the built-in sounds as WAV files for auditioning.
if let i = CommandLine.arguments.firstIndex(of: "--export"), i + 1 < CommandLine.arguments.count {
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1], isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let banks = Profile.builtIn.map { ($0.name, SoundEngine.synthesizedBank($0)) }
        + FunSound.allCases.map { ($0.rawValue, SoundEngine.funBank($0)) }
    for (name, bank) in banks {
        for (kind, buffers) in bank where !buffers.isEmpty {
            let url = dir.appendingPathComponent("\(name)-\(kind).wav")
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: Synth.sampleRate,
                                           AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                                           AVLinearPCMIsFloatKey: false]
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffers[0])
        }
    }
    print("Exported to \(dir.path)")
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    _ = NSApplication.shared
    try Snapshot.run(into: URL(fileURLWithPath: CommandLine.arguments[i + 1], isDirectory: true))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
