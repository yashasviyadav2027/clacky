import AppKit
import Combine
import ServiceManagement

/// Shared settings + engine state used by the popover, the right-click menu and the settings window.
final class AppState: ObservableObject {
    static let packsFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Clacky/Packs", isDirectory: true)
    static let bundledPacksFolder = Bundle.main.resourceURL!.appendingPathComponent("Packs", isDirectory: true)
    static let defaultPack = "Holy Panda"

    private let defaults = UserDefaults.standard
    private let sound = SoundEngine()
    private let monitor = KeyMonitor()
    private var banks: [String: SoundBank] = [:]
    private var permissionTimer: Timer?

    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "enabled")
            // Turning sound back on always starts from a fresh audio engine.
            if !enabled { sound.goIdle(reason: "sound switched off") }
        }
    }
    @Published var volume: Double {
        didSet { defaults.set(volume, forKey: "volume"); sound.volume = Float(volume) }
    }
    @Published var keyUpSounds: Bool { didSet { defaults.set(keyUpSounds, forKey: "keyUp") } }
    @Published var stereo: Bool { didSet { defaults.set(stereo, forKey: "stereo") } }
    @Published private(set) var selectedPack: String
    @Published private(set) var packs: [PackInfo] = []
    @Published private(set) var listening = false
    @Published private(set) var hasPermission = false
    /// Non-nil while Secure Input hides keystrokes; the value names the app if known.
    @Published private(set) var secureInputBy: String?
    @Published private(set) var favorites: [String] { didSet { defaults.set(favorites, forKey: "favorites") } }
    @Published private(set) var recent: [String] { didSet { defaults.set(recent, forKey: "recent") } }

    /// Set by the app delegate so views can jump to a settings tab.
    var openSettings: ((SettingsTab) -> Void)?

    var currentPack: PackInfo? { pack(named: selectedPack) }
    var favoritePacks: [PackInfo] { favorites.compactMap(pack(named:)) }
    /// Recently used packs that aren't already favorites, newest first.
    var recentPacks: [PackInfo] {
        recent.filter { !favorites.contains($0) }.prefix(3).compactMap(pack(named:))
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Clacky: launch at login failed: \(error)")
            }
            objectWillChange.send()
        }
    }

    init() {
        Self.migrateFromKeyThock(defaults)
        defaults.register(defaults: ["enabled": true, "profile": Self.defaultPack, "volume": 0.7,
                                     "keyUp": true, "stereo": true])
        if !defaults.bool(forKey: "didAdoptRecordedPacks") { // v0.1 saved a synthesized default
            defaults.set(Self.defaultPack, forKey: "profile")
            defaults.set(true, forKey: "didAdoptRecordedPacks")
        }
        enabled = defaults.bool(forKey: "enabled")
        volume = defaults.double(forKey: "volume")
        keyUpSounds = defaults.bool(forKey: "keyUp")
        stereo = defaults.bool(forKey: "stereo")
        selectedPack = defaults.string(forKey: "profile") ?? Self.defaultPack
        favorites = defaults.stringArray(forKey: "favorites") ?? []
        recent = defaults.stringArray(forKey: "recent") ?? []

        sound.volume = Float(volume)
        reloadPacks()
        // A pack that no longer exists (e.g. a removed fun sound) falls back to the default.
        select(pack(named: selectedPack) == nil ? Self.defaultPack : selectedPack, preview: false)

        monitor.onKey = { [weak self] code, isDown in self?.handleKey(code, isDown) }
        startMonitoring()
        startSelfHealing()
    }

    // MARK: - Self-healing

    private var healthTimer: Timer?

    /// Long uptimes with many sleep/wake cycles could leave Clacky silent until relaunched.
    /// Recover the audio engine and key listener on wake, and check on them periodically.
    private func startSelfHealing() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                Diagnostics.log.notice("\(note.name.rawValue, privacy: .public) — restarting audio and key listener")
                self.sound.goIdle(reason: note.name.rawValue) // next key press starts fresh audio
                self.monitor.ensureEnabled()
                self.refreshStatus()
                // Audio devices can take several seconds to come back after wake;
                // check again once they have.
                for delay in [3.0, 10.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        self?.sound.ensureRunning()
                        self?.monitor.ensureEnabled()
                    }
                }
            }
        }
        var tick = 0, lastEvents = 0, lastPlays = 0
        healthTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.sound.ensureRunning()
            self.monitor.ensureEnabled()
            let secure = Diagnostics.secureInputOn ? (Diagnostics.secureInputApp ?? "") : nil
            if secure != self.secureInputBy { self.secureInputBy = secure }
            tick += 1
            guard tick % 6 == 0 else { return } // heartbeat every 30 s
            let events = self.monitor.eventCount, plays = self.sound.playCount
            Diagnostics.log.notice("""
                heartbeat keys=\(events - lastEvents) sounds=\(plays - lastPlays) \
                listener=\(self.monitor.tapEnabled) audio=\(self.sound.isIdle ? "idle" : String(self.sound.isRunning), privacy: .public) rendering=\(self.sound.isRendering) \
                lastSignal=\(Int(min(self.sound.secondsSinceSignal, 99999)))s rebuilds=\(self.sound.rebuildCount) \
                permission=\(KeyMonitor.hasPermission) enabled=\(self.enabled) \
                volume=\(self.volume, format: .fixed(precision: 2)) secureInput=\(Diagnostics.secureInputOn) \
                secureApp=\(Diagnostics.secureInputApp ?? "-", privacy: .public)
                """)
            lastEvents = events
            lastPlays = plays
        }
    }

    // MARK: - Keys

    private func handleKey(_ code: Int64, _ isDown: Bool) {
        guard enabled, isDown || keyUpSounds else { return }
        let pan = stereo ? KeyMap.pan(for: code) * 0.5 : 0
        sound.play(KeyMap.kind(for: code, isDown: isDown), pan: pan)
    }

    // MARK: - Permission

    private func startMonitoring() {
        refreshStatus()
        if listening { return }
        KeyMonitor.requestPermission()
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            self.refreshStatus()
            if self.listening { timer.invalidate() }
        }
    }

    func refreshStatus() {
        hasPermission = KeyMonitor.hasPermission
        if hasPermission, !monitor.isRunning { monitor.start() }
        listening = hasPermission && monitor.isRunning
    }

    func openInputMonitoringSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    /// macOS sometimes only applies a fresh Input Monitoring grant after the app restarts.
    func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: - Packs

    func reloadPacks() {
        let updated = PackCatalog.all(bundled: Self.subfolders(of: Self.bundledPacksFolder),
                                      custom: Self.subfolders(of: Self.packsFolder))
        if updated != packs { packs = updated }
    }

    func pack(named name: String) -> PackInfo? {
        packs.first { $0.name == name }
    }

    func select(_ name: String, preview: Bool = true) {
        if name != selectedPack { recent = [selectedPack] + recent.filter { $0 != selectedPack && $0 != name } }
        recent = Array(recent.prefix(6))
        sound.use(bank(for: name))
        selectedPack = name
        defaults.set(name, forKey: "profile")
        if preview { playDemo(name) }
    }

    func isFavorite(_ name: String) -> Bool { favorites.contains(name) }

    func toggleFavorite(_ name: String) {
        if let i = favorites.firstIndex(of: name) { favorites.remove(at: i) } else { favorites.append(name) }
    }

    /// Plays a short burst of typing with the given pack (default: the current one).
    func playDemo(_ name: String? = nil) {
        let bank = bank(for: name ?? selectedPack)
        let steps: [(SoundKind, Double)] = [(.down, 0), (.up, 0.07), (.down, 0.15), (.up, 0.21), (.down, 0.29),
                                            (.up, 0.34), (.space, 0.46), (.up, 0.53), (.down, 0.62), (.up, 0.68),
                                            (.down, 0.75), (.up, 0.81), (.enter, 0.98), (.up, 1.06)]
        for (kind, time) in steps where kind != .up || keyUpSounds {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) { [weak self] in
                self?.sound.play(kind, pan: Float.random(in: -0.2...0.2), from: bank)
            }
        }
    }

    func openPacksFolder() {
        try? FileManager.default.createDirectory(at: Self.packsFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Self.packsFolder)
    }

    private func bank(for name: String) -> SoundBank {
        if let cached = banks[name] { return cached }
        // A same-named folder in the user's Packs folder overrides a built-in pack
        // (e.g. Packs/Duck replaces the generated quack with a recording).
        var bank = SoundEngine.loadBank(folder: Self.packsFolder.appendingPathComponent(name))
        if bank.isEmpty, let profile = Profile.builtIn.first(where: { $0.name == name }) {
            bank = SoundEngine.synthesizedBank(profile)
        } else if bank.isEmpty, let fun = FunSound(rawValue: name) {
            bank = SoundEngine.funBank(fun)
        } else if bank.isEmpty {
            bank = SoundEngine.loadBank(folder: Self.bundledPacksFolder.appendingPathComponent(name))
        }
        if bank.isEmpty { return SoundEngine.synthesizedBank(Profile.builtIn[0]) }
        banks[name] = bank
        return bank
    }

    /// The app used to be called KeyThock; carry over its settings and custom packs once.
    private static func migrateFromKeyThock(_ defaults: UserDefaults) {
        guard !defaults.bool(forKey: "didMigrateFromKeyThock") else { return }
        defaults.set(true, forKey: "didMigrateFromKeyThock")
        if let old = UserDefaults(suiteName: "com.yashasviyadav.keythock") {
            for key in ["enabled", "profile", "volume", "keyUp", "stereo", "didAdoptRecordedPacks", "didShowWindow"] {
                if let value = old.object(forKey: key) { defaults.set(value, forKey: key) }
            }
        }
        let fm = FileManager.default
        let oldPacks = packsFolder.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KeyThock/Packs", isDirectory: true)
        if fm.fileExists(atPath: oldPacks.path), !fm.fileExists(atPath: packsFolder.path) {
            try? fm.createDirectory(at: packsFolder.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.moveItem(at: oldPacks, to: packsFolder)
        }
    }

    private static func subfolders(of folder: URL) -> [String] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent).sorted()
    }
}
