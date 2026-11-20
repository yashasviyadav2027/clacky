import SwiftUI

/// Everything you need in one click from the menu bar: current sound, on/off, volume,
/// favorites, recently used and all sounds.
struct PopoverView: View {
    @ObservedObject var state: AppState
    @State private var filter: SoundStyle?

    /// The list grows with its content up to this height, then scrolls.
    private let maxListHeight: CGFloat = 400

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 36) // room so an auto-hiding menu bar doesn't crop the header
                .padding(.bottom, 10)
            controls
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            if !state.listening {
                PermissionCard(state: state, compact: true)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
            Divider()
            FilterChips(filter: $filter, noneTitle: "Favorites", noneSymbol: "star.fill")
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            // Short lists show at their natural height; long ones scroll.
            ViewThatFits(in: .vertical) {
                soundList
                ScrollView { soundList }
            }
            .frame(maxHeight: maxListHeight)
            Divider()
            footer
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { state.refreshStatus(); state.reloadPacks() }
    }

    private var soundList: some View {
        VStack(alignment: .leading, spacing: 1) {
            if filter == nil {
                if state.favoritePacks.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "star")
                            .font(.system(size: 22))
                            .foregroundStyle(.yellow)
                        Text("No favorites yet")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Pick a type above and tap ☆ next to a sound to keep it here, one click away.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
                ForEach(state.favoritePacks) { SoundRow(state: state, pack: $0) }

                if !state.recentPacks.isEmpty {
                    SectionTitle(title: "Recently Used", symbol: "clock")
                    ForEach(state.recentPacks) { SoundRow(state: state, pack: $0) }
                }
            } else {
                ForEach(state.packs.filter { $0.style == filter }) {
                    SoundRow(state: state, pack: $0)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Keycap(pack: state.currentPack, size: 40, glowing: state.enabled && state.listening)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.currentPack?.name ?? state.selectedPack)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                statusLine
            }
            Spacer()
            Button { state.openSettings?(.general) } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if !state.listening {
            Label("Needs permission", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 11))
        } else if let app = state.secureInputBy, state.enabled {
            Label(app.isEmpty ? "Paused: a password field is active" : "Paused: \(app) is in secure typing mode",
                  systemImage: "lock.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 11))
                .lineLimit(1)
                .help("macOS hides your keystrokes from every app while a password field or secure-entry mode is active. Clacky resumes on its own when it ends.")
        } else if !state.enabled {
            Label("Sound off", systemImage: "speaker.slash.fill")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
        } else {
            HStack(spacing: 5) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("Playing as you type").foregroundStyle(.secondary)
            }
            .font(.system(size: 11))
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Toggle("Sound", isOn: $state.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .help(state.enabled ? "Turn sound off" : "Turn sound on")
            Image(systemName: "speaker.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Slider(value: $state.volume, in: 0...1)
                .controlSize(.small)
                .disabled(!state.enabled)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Button { state.playDemo() } label: {
                Image(systemName: "play.circle.fill").font(.system(size: 17))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help("Test the current sound")
        }
    }

    private var footer: some View {
        HStack {
            Button { state.openSettings?(.sounds) } label: {
                Label("Search Sounds", systemImage: "magnifyingglass")
            }
            Spacer()
            Button("Quit Clacky") { NSApp.terminate(nil) }
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

