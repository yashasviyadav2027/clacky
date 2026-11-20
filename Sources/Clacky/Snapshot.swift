import AppKit
import SwiftUI

/// `Clacky --snapshot <dir>` renders the popover and settings tabs to PNGs (light + dark)
/// so the UI can be reviewed without clicking through it.
enum Snapshot {
    static func run(into dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let state = AppState()
        let views: [(String, AnyView, CGSize)] = [
            ("popover", AnyView(PopoverView(state: state)), CGSize(width: 320, height: 0)),
            ("general", AnyView(GeneralTab(state: state)), CGSize(width: 500, height: 560)),
            ("sounds", AnyView(SoundsTab(state: state)), CGSize(width: 500, height: 560)),
            ("about", AnyView(AboutTab()), CGSize(width: 500, height: 560)),
        ]
        for (name, view, size) in views {
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height > 0 ? size.height : nil)
                    .background(Color(nsColor: .windowBackgroundColor)))
                // Height 0 = size to fit, like the real popover.
                host.frame = NSRect(origin: .zero, size: size.height > 0 ? size : host.fittingSize)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                if size.height == 0 { host.setFrameSize(host.fittingSize); window.setContentSize(host.fittingSize) }
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                try rep.representation(using: .png, properties: [:])?
                    .write(to: dir.appendingPathComponent("\(name)-\(suffix).png"))
            }
        }
    }
}
