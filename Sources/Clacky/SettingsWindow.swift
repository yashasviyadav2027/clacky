import SwiftUI

enum SettingsTab: Int {
    case general, sounds, about
}

private let tabSize = CGSize(width: 500, height: 560)

/// Standard macOS settings window with General / Sounds / About tabs.
final class SettingsWindowController: NSWindowController {
    private let tabs = NSTabViewController()

    init(state: AppState) {
        tabs.tabStyle = .toolbar
        func item(_ label: String, _ symbol: String, _ view: some View) -> NSTabViewItem {
            let item = NSTabViewItem(viewController: NSHostingController(rootView: view.frame(width: tabSize.width, height: tabSize.height)))
            item.label = label
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            return item
        }
        tabs.addTabViewItem(item("General", "gearshape", GeneralTab(state: state)))
        tabs.addTabViewItem(item("Sounds", "keyboard", SoundsTab(state: state)))
        tabs.addTabViewItem(item("About", "info.circle", AboutTab()))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(tabSize)
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ tab: SettingsTab) {
        tabs.selectedTabViewItemIndex = tab.rawValue
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - General

struct GeneralTab: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Section {
                if state.listening {
                    Label("Clacky is listening to your keyboards", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    PermissionCard(state: state)
                        .listRowInsets(EdgeInsets())
                }
            }

            Section("Sound") {
                Toggle("Play sounds", isOn: $state.enabled)
                LabeledContent("Volume") {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $state.volume, in: 0...1)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                        Button("Test") { state.playDemo() }
                    }
                    .disabled(!state.enabled)
                }
                Toggle("Key release sounds", isOn: $state.keyUpSounds)
                Toggle(isOn: $state.stereo) {
                    Text("Stereo by key position")
                    Text("Keys on the left come from the left speaker").foregroundStyle(.secondary)
                }
            }

            Section("Keyboards") {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Built-in and external keyboards")
                        Text("Works with your MacBook keyboard and any USB or Bluetooth keyboard — just connect it and type.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "keyboard.badge.ellipsis")
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { state.launchAtLogin },
                                                        set: { state.launchAtLogin = $0 }))
            }
        }
        .formStyle(.grouped)
        .onAppear { state.refreshStatus() }
    }
}

// MARK: - Sounds

struct SoundsTab: View {
    @ObservedObject var state: AppState
    @State private var filter: SoundStyle?
    @State private var search = ""
    @State private var favoritesOnly = false

    private var visible: [PackInfo] {
        state.packs.filter { pack in
            (filter == nil || pack.style == filter)
                && (!favoritesOnly || state.isFavorite(pack.name))
                && (search.isEmpty || pack.name.localizedCaseInsensitiveContains(search)
                    || pack.subtitle.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search sounds", text: $search).textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
                Toggle(isOn: $favoritesOnly) {
                    Label("Favorites", systemImage: favoritesOnly ? "star.fill" : "star")
                }
                .toggleStyle(.button)
            }
            FilterChips(filter: $filter)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(groups, id: \.0) { title, symbol, packs in
                        SectionTitle(title: title, symbol: symbol)
                        ForEach(packs) { SoundRow(state: state, pack: $0) }
                    }
                    if visible.isEmpty {
                        Text(favoritesOnly ? "No favorites here yet — tap ☆ next to a sound." : "No sounds match your search.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                }
            }

            Divider()
            HStack {
                Text("Add your own: drop audio files into a folder in Packs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open Packs Folder") { state.openPacksFolder() }
                    .controlSize(.small)
            }
        }
        .padding(16)
        .onAppear { state.reloadPacks() }
    }

    /// Groups the visible packs by sound type, keeping catalog order.
    private var groups: [(String, String, [PackInfo])] {
        var result: [(String, String, [PackInfo])] = []
        for style in SoundStyle.allCases {
            let packs = visible.filter { $0.style == style }
            if !packs.isEmpty { result.append((style.rawValue, style.symbol, packs)) }
        }
        let other = visible.filter { $0.style == nil }
        if !other.isEmpty { result.append(("My Packs", "folder", other)) }
        return result
    }
}

// MARK: - About

struct AboutTab: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Keycap(pack: PackInfo(name: "Clacky", style: .clacky, switchType: "", blurb: "", source: .synthesized),
                   size: 88, glowing: true)
            VStack(spacing: 4) {
                Text("Clacky").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Version \(version)").foregroundStyle(.secondary)
            }
            Text("Mechanical keyboard sounds for your Mac.")
                .font(.headline)
            VStack(spacing: 6) {
                Text("Switch recordings from kbsim by Thomas Lai (MIT License).")
                Link("github.com/tplai/kbsim", destination: URL(string: "https://github.com/tplai/kbsim")!)
                Text("Clacky only reads which key was pressed to pick a sound. It never records what you type.")
                    .padding(.top, 8)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            Spacer()
        }
    }
}
