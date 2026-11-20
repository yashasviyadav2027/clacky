import SwiftUI

extension SoundStyle {
    var tint: Color {
        switch self {
        case .thocky: return Color(red: 0.42, green: 0.36, blue: 0.72)
        case .creamy: return Color(red: 0.93, green: 0.84, blue: 0.66)
        case .clacky: return Color(red: 0.29, green: 0.56, blue: 0.90)
        case .clicky: return Color(red: 0.15, green: 0.69, blue: 0.61)
        case .fun: return Color(red: 1.00, green: 0.79, blue: 0.20)
        }
    }

    var symbol: String {
        switch self {
        case .thocky: return "circle.bottomhalf.filled"
        case .creamy: return "drop.fill"
        case .clacky: return "bolt.fill"
        case .clicky: return "cursorarrow.click"
        case .fun: return "face.smiling"
        }
    }

    /// Light tints need dark text on top of them.
    var onTint: Color {
        switch self {
        case .creamy, .fun: return Color(red: 0.30, green: 0.22, blue: 0.10)
        default: return .white
        }
    }
}

/// A little keycap icon for a sound pack, colored by its sound type.
struct Keycap: View {
    let pack: PackInfo?
    var size: CGFloat = 28
    var glowing = false

    var body: some View {
        let tint = pack?.style?.tint ?? Color.gray
        let label = pack?.keycapLabel ?? "?"
        let isEmoji = label.unicodeScalars.contains { $0.properties.isEmojiPresentation }
        let radius = size * 0.24
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: radius)
                .fill(tint)
                .overlay(RoundedRectangle(cornerRadius: radius).fill(Color.black.opacity(0.22)))
            RoundedRectangle(cornerRadius: radius * 0.8)
                .fill(tint)
                .overlay(
                    RoundedRectangle(cornerRadius: radius * 0.8)
                        .fill(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.04)],
                                             startPoint: .top, endPoint: .bottom))
                )
                .overlay(
                    Text(label)
                        .font(.system(size: size * (isEmoji ? 0.4 : 0.3), weight: .bold, design: .rounded))
                        .foregroundStyle(pack?.style?.onTint ?? .white)
                        .minimumScaleFactor(0.5)
                )
                .frame(width: size * 0.78, height: size * 0.72)
                .padding(.top, size * 0.06)
        }
        .frame(width: size, height: size)
        .shadow(color: glowing ? tint.opacity(0.75) : .black.opacity(0.18),
                radius: glowing ? size * 0.22 : 1, y: glowing ? 0 : 1)
    }
}

struct StarButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "star.fill" : "star")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn ? Color.yellow : Color.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOn ? "Remove from Favorites" : "Add to Favorites")
    }
}

/// Animated speaker shown next to the sound that's currently in use.
///
/// The animation runs only while its window is on screen. A closed popover keeps its view
/// alive, and a repeating symbol effect there kept a display link firing (~5% CPU while idle).
struct NowPlayingIcon: View {
    @State private var windowVisible = false

    var body: some View {
        let icon = Image(systemName: "speaker.wave.2.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 22, height: 22)
            .background(WindowVisibilityReader(isVisible: $windowVisible))
        if #available(macOS 14.0, *) {
            icon.symbolEffect(.variableColor.iterative, options: .repeating, isActive: windowVisible)
        } else {
            icon
        }
    }
}

/// Reports whether the hosting window is actually visible on screen (ordered in and not occluded).
private struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = { visible in
            DispatchQueue.main.async { if isVisible != visible { isVisible = visible } }
        }
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {}

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { onChange?(false); return }
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                object: window, queue: .main) { [weak self] _ in self?.report() })
            observers.append(center.addObserver(forName: NSWindow.willCloseNotification,
                                                object: window, queue: .main) { [weak self] _ in self?.onChange?(false) })
            report()
        }

        private func report() {
            guard let window else { onChange?(false); return }
            onChange?(window.isVisible && window.occlusionState.contains(.visible))
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}

/// One sound in a list: keycap, name, type, preview on hover, favorite star. Click to use it.
struct SoundRow: View {
    @ObservedObject var state: AppState
    let pack: PackInfo
    @State private var hovering = false

    var body: some View {
        let selected = pack.name == state.selectedPack
        HStack(spacing: 10) {
            Keycap(pack: pack, size: 28, glowing: selected)
            VStack(alignment: .leading, spacing: 1) {
                Text(pack.name)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Text(pack.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if selected {
                NowPlayingIcon()
            } else if hovering {
                Button { state.playDemo(pack.name) } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Preview without switching")
            }
            StarButton(isOn: state.isFavorite(pack.name)) { state.toggleFavorite(pack.name) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.14) : (hovering ? Color.primary.opacity(0.06) : .clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { state.select(pack.name) }
        .help(pack.blurb)
    }
}

/// "All · Thocky · Creamy · …" capsule filter. The first chip (nil) can be relabeled,
/// e.g. "★ Favorites" in the popover.
struct FilterChips: View {
    @Binding var filter: SoundStyle?
    var noneTitle = "All"
    var noneSymbol: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(noneTitle, symbol: noneSymbol, style: nil)
                ForEach(SoundStyle.allCases) { chip($0.rawValue, style: $0) }
            }
            .padding(.horizontal, 2)
        }
    }

    private func chip(_ title: String, symbol: String? = nil, style: SoundStyle?) -> some View {
        let selected = filter == style
        return Button { filter = style } label: {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) }
                Text(title)
            }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(selected ? (style?.tint ?? Color.accentColor) : Color.primary.opacity(0.07)))
                .foregroundStyle(selected ? (style?.onTint ?? .white) : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct SectionTitle: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

/// Shown when Clacky can't hear the keyboard yet, with the steps to fix it.
struct PermissionCard: View {
    @ObservedObject var state: AppState
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Clacky can't hear your keyboard yet", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
            Text(compact
                 ? "Turn on Clacky in Input Monitoring, then restart it."
                 : "Open Input Monitoring and switch Clacky on. If it's already on, remove it with − and add it again with +. Then click Restart.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Open Input Monitoring") { state.openInputMonitoringSettings() }
                    .buttonStyle(.borderedProminent)
                Button("Restart Clacky") { state.relaunch() }
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
    }
}
