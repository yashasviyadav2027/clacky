import AVFoundation
import CoreAudio
import ObjCCatch
import os

typealias SoundBank = [SoundKind: [AVAudioPCMBuffer]]

/// Plays key sounds.
///
/// Why it is built this way (each point fixed a real "Clacky stopped" report):
/// - A long-lived AVAudioEngine can end up attached to a dead output after sleep/wake, so
///   when anything looks wrong we throw the engine away and build a new one.
/// - AVAudioPlayerNode.play() raises an Objective-C exception (which kills the app) if the
///   output vanishes at the wrong moment, e.g. while the Mac drifts into sleep. So there are
///   no player nodes: one source node mixes all key sounds itself in its render callback,
///   and every AVFAudio call that could raise runs inside an exception catcher.
final class SoundEngine {
    static let format = AVAudioFormat(standardFormatWithSampleRate: Synth.sampleRate, channels: 1)!
    static let variantsPerKind = 8
    private static let outputFormat = AVAudioFormat(standardFormatWithSampleRate: Synth.sampleRate, channels: 2)!

    private var engine: AVAudioEngine?
    private let mixer = VoiceMixer()
    private var bank: SoundBank = [:]
    private var configObserver: NSObjectProtocol?
    private var lastPlay: CFAbsoluteTime = 0
    private var lastRebuild: CFAbsoluteTime = 0
    private var pendingRebuild: DispatchWorkItem?
    private var retryDelay: TimeInterval = 0.5
    private(set) var rebuildCount = 0
    private(set) var playCount = 0

    var volume: Float = 0.7 {
        didSet { mixer.masterVolume = volume }
    }

    /// After this long without a key sound, the engine is shut down so the speaker (and the
    /// system audio service) can go idle and the Mac can sleep. The next key press starts it.
    static let idleTimeout: CFAbsoluteTime = 15

    init() {}  // starts on the first key press

    // MARK: - Lifecycle

    /// Asks for a fresh engine. Requests are coalesced (wake sends several notifications at
    /// once) and run shortly after, once CoreAudio has had a moment to bring devices back.
    func rebuild(reason: String, after delay: TimeInterval = 0.75) {
        if pendingRebuild != nil { return }
        Diagnostics.log.notice("audio rebuild requested (\(reason, privacy: .public))")
        let work = DispatchWorkItem { [weak self] in
            self?.pendingRebuild = nil
            self?.performRebuild()
        }
        pendingRebuild = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func performRebuild() {
        rebuildCount += 1
        teardown()
        build()
    }

    /// Releases the speaker. Also used instead of repairing after wake or a device change:
    /// the next key press simply builds a fresh engine.
    func goIdle(reason: String) {
        pendingRebuild?.cancel()
        pendingRebuild = nil
        guard engine != nil else { return }
        Diagnostics.log.notice("audio off (\(reason, privacy: .public))")
        teardown()
    }

    private func teardown() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        if let engine {
            if let problem = ClackyCatchException({ engine.stop() }) {
                Diagnostics.log.error("audio stop raised \(problem, privacy: .public)")
            }
        }
        engine = nil
    }

    private func build() {
        lastRebuild = CFAbsoluteTimeGetCurrent()
        mixer.markRendered()
        let engine = AVAudioEngine()
        var started = false
        var failure: String?
        let exception = ClackyCatchException {
            // No usable output device (e.g. mid-wake): don't touch the graph yet.
            let out = engine.outputNode.outputFormat(forBus: 0)
            guard out.sampleRate > 0, out.channelCount > 0 else {
                failure = "no output device yet"
                return
            }
            let mixer = self.mixer
            let source = AVAudioSourceNode(format: Self.outputFormat) { _, _, frames, abl in
                mixer.render(frames: Int(frames), into: UnsafeMutableAudioBufferListPointer(abl))
                return noErr
            }
            engine.attach(source)
            engine.connect(source, to: engine.mainMixerNode, format: Self.outputFormat)
            engine.prepare()
            do {
                try engine.start()
                started = engine.isRunning
            } catch {
                failure = error.localizedDescription
            }
        }
        if let exception { failure = exception }

        guard started else {
            Diagnostics.log.notice("audio not ready (\(failure ?? "engine not running", privacy: .public)) — retrying in \(self.retryDelay, format: .fixed(precision: 1)) s")
            ClackyCatchException { engine.stop() }
            let delay = retryDelay
            retryDelay = min(retryDelay * 2, 10)
            rebuild(reason: "start retry", after: delay)
            return
        }
        retryDelay = 0.5
        self.engine = engine
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.goIdle(reason: "output device or format changed")
        }
    }

    /// Called every few seconds. Rebuilds the engine if anything about it looks wrong.
    func ensureRunning() {
        if pendingRebuild != nil { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastRebuild > 2 else { return } // give a fresh engine a moment to settle
        guard let engine else { return } // idle: speaker released, nothing to check
        if now - lastPlay > Self.idleTimeout, mixer.isQuiet {
            goIdle(reason: "idle for \(Int(Self.idleTimeout)) s")
        } else if !engine.isRunning {
            rebuild(reason: "engine stopped")
        } else if now - mixer.lastRender > 3 {
            rebuild(reason: "engine not rendering")
        } else if let current = outputDevice(of: engine), let wanted = Self.defaultOutputDevice, current != wanted {
            rebuild(reason: "engine on old output device \(current), default is \(wanted)")
        } else if lastPlay > lastRebuild, now - lastPlay > 0.5, mixer.lastConsumed < lastPlay - 0.5 {
            rebuild(reason: "sounds queued but never played")
        }
    }

    var isRunning: Bool { engine?.isRunning ?? false }
    var isIdle: Bool { engine == nil && pendingRebuild == nil }
    var isRendering: Bool { CFAbsoluteTimeGetCurrent() - mixer.lastRender < 3 }
    /// Seconds since a key sound was last actually mixed into the output.
    var secondsSinceSignal: Double { CFAbsoluteTimeGetCurrent() - mixer.lastConsumed }

    private func outputDevice(of engine: AVAudioEngine) -> AudioDeviceID? {
        guard let unit = engine.outputNode.audioUnit else { return nil }
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let err = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                       kAudioUnitScope_Global, 0, &id, &size)
        return err == noErr && id != 0 ? id : nil
    }

    private static var defaultOutputDevice: AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return err == noErr && id != 0 ? id : nil
    }

    func use(_ newBank: SoundBank) {
        bank = newBank
    }

    func play(_ kind: SoundKind, pan: Float, from other: SoundBank? = nil) {
        let bank = other ?? self.bank
        guard let buffers = bank[kind] ?? bank[kind == .up ? .up : .down], let buffer = buffers.randomElement() else { return }
        if engine == nil, pendingRebuild == nil {
            build() // wake the speaker on demand
        } else if let engine, !engine.isRunning {
            rebuild(reason: "engine stopped at key press")
        }
        playCount += 1
        lastPlay = CFAbsoluteTimeGetCurrent()
        mixer.trigger(buffer, pan: pan, gain: Float.random(in: 0.85...1.0))
    }

    // MARK: - Banks

    static func synthesizedBank(_ profile: Profile) -> SoundBank {
        var bank: SoundBank = [:]
        for (k, kind) in SoundKind.allCases.enumerated() {
            bank[kind] = (0..<variantsPerKind).compactMap { v in
                makeBuffer(Synth.render(profile, kind: kind, seed: UInt64(k * 100 + v + 1)))
            }
        }
        return bank
    }

    /// Fun packs leave key release silent (an empty `.up` list).
    static func funBank(_ fun: FunSound) -> SoundBank {
        var bank: SoundBank = [:]
        for kind in SoundKind.allCases {
            bank[kind] = (0..<variantsPerKind).compactMap { v in
                let samples = fun.render(kind, variant: v)
                return samples.isEmpty ? nil : makeBuffer(samples)
            }
        }
        return bank
    }

    /// Loads a folder of audio files. File name prefix picks the key type:
    /// space*, enter*/return*, backspace*/delete*, up*; everything else is a normal key-down.
    static func loadBank(folder: URL) -> SoundBank {
        let exts: Set<String> = ["wav", "aif", "aiff", "caf", "mp3", "m4a"]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var bank: SoundBank = [:]
        for url in files where exts.contains(url.pathExtension.lowercased()) {
            let name = url.lastPathComponent.lowercased()
            let kind: SoundKind
            if name.hasPrefix("space") { kind = .space }
            else if name.hasPrefix("enter") || name.hasPrefix("return") { kind = .enter }
            else if name.hasPrefix("backspace") || name.hasPrefix("delete") { kind = .backspace }
            else if name.hasPrefix("up") { kind = .up }
            else { kind = .down }
            if let buf = loadFile(url) { bank[kind, default: []].append(buf) }
        }
        return bank
    }

    private static func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        buf.frameLength = buf.frameCapacity
        samples.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        return buf
    }

    private static func loadFile(_ url: URL) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url),
              let src = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: src)) != nil else { return nil }
        if src.format == format { return src }

        guard let conv = AVAudioConverter(from: src.format, to: format) else { return nil }
        conv.downmix = true
        let capacity = AVAudioFrameCount(Double(src.frameLength) * format.sampleRate / src.format.sampleRate) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        conv.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return src
        }
        return error == nil ? out : nil
    }
}

/// Mixes key sounds in the audio render callback. The main thread only appends trigger
/// commands under a lock; the render thread drains them with a try-lock (never blocking)
/// and owns the voices outright.
private final class VoiceMixer: @unchecked Sendable {
    private struct Voice {
        var buffer: AVAudioPCMBuffer
        var samples: UnsafePointer<Float>
        var length: Int
        var position = 0
        var gainL: Float
        var gainR: Float
        var queuedAt: CFAbsoluteTime
    }

    private static let maxVoices = 32
    private let lock: UnsafeMutablePointer<os_unfair_lock> = {
        let p = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        p.initialize(to: os_unfair_lock())
        return p
    }()
    private var pending: [Voice] = []   // guarded by lock
    private var voices: [Voice] = []    // render thread only

    var masterVolume: Float = 0.7       // single aligned word; tearing is impossible
    var lastRender: CFAbsoluteTime = 0
    var lastConsumed: CFAbsoluteTime = 0

    init() {
        pending.reserveCapacity(64)
        voices.reserveCapacity(Self.maxVoices + 8)
    }

    /// True when nothing is playing or waiting to play.
    var isQuiet: Bool {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return pending.isEmpty && voicesActive == 0
    }
    private var voicesActive = 0

    func markRendered() {
        lastRender = CFAbsoluteTimeGetCurrent()
    }

    func trigger(_ buffer: AVAudioPCMBuffer, pan: Float, gain: Float) {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let angle = (max(-1, min(1, pan)) + 1) * .pi / 4  // equal-power pan
        let voice = Voice(buffer: buffer, samples: UnsafePointer(data[0]), length: Int(buffer.frameLength),
                          gainL: cos(angle) * gain * 1.414, gainR: sin(angle) * gain * 1.414,
                          queuedAt: CFAbsoluteTimeGetCurrent())
        os_unfair_lock_lock(lock)
        if pending.count < 64 { pending.append(voice) }
        os_unfair_lock_unlock(lock)
    }

    func render(frames: Int, into abl: UnsafeMutableAudioBufferListPointer) {
        let now = CFAbsoluteTimeGetCurrent()
        lastRender = now
        if os_unfair_lock_trylock(lock) {
            if !pending.isEmpty {
                // Skip clicks that waited too long (audio was still starting) so a late
                // start doesn't play a burst of old keystrokes at once.
                for v in pending where now - v.queuedAt < 0.3 { voices.append(v) }
                pending.removeAll(keepingCapacity: true)
                lastConsumed = now
            }
            os_unfair_lock_unlock(lock)
        }
        if voices.count > Self.maxVoices { voices.removeFirst(voices.count - Self.maxVoices) } // drop oldest

        guard abl.count >= 2,
              let left = abl[0].mData?.assumingMemoryBound(to: Float.self),
              let right = abl[1].mData?.assumingMemoryBound(to: Float.self) else {
            for b in abl { if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) } }
            return
        }
        memset(left, 0, frames * MemoryLayout<Float>.size)
        memset(right, 0, frames * MemoryLayout<Float>.size)
        let master = masterVolume
        var i = 0
        while i < voices.count {
            let n = min(frames, voices[i].length - voices[i].position)
            let src = voices[i].samples + voices[i].position
            let gl = voices[i].gainL * master, gr = voices[i].gainR * master
            for f in 0..<n {
                let s = src[f]
                left[f] += s * gl
                right[f] += s * gr
            }
            voices[i].position += n
            if voices[i].position >= voices[i].length { voices.remove(at: i) } else { i += 1 }
        }
        voicesActive = voices.count
    }
}
