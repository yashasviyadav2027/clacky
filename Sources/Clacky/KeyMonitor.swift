import AppKit
import CoreGraphics

/// Listens (read-only) to global key events. Only key codes are passed on — never characters.
/// macOS blocks this tap during secure input (password fields), so those keystrokes stay silent.
final class KeyMonitor {
    var onKey: ((_ keyCode: Int64, _ isDown: Bool) -> Void)?

    private var tap: CFMachPort?
    private var heldModifiers = Set<Int64>()

    static let mediaKeyOffset: Int64 = 1000
    private static let systemDefinedType: UInt32 = 14 // NX_SYSDEFINED: media/brightness keys

    static var hasPermission: Bool { CGPreflightListenEventAccess() }
    static func requestPermission() { CGRequestListenEventAccess() }

    var isRunning: Bool { tap != nil }

    /// macOS can switch an event tap off (e.g. after sleep or a slow callback); turn it back on.
    func ensureEnabled() {
        if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            Diagnostics.log.notice("key listener found off — re-enabling")
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    var tapEnabled: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    private(set) var eventCount = 0

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue) | (1 << Self.systemDefinedType)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .listenOnly, eventsOfInterest: CGEventMask(mask),
                                          callback: keyTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            Diagnostics.log.notice("key listener disabled by macOS (\(type.rawValue)) — re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown:
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return } // holding a key = one sound
            eventCount += 1 // counts real key presses only (for the health log)
            onKey?(code, true)
        case .keyUp:
            onKey?(code, false)
        case .flagsChanged:
            if code == KeyMap.capsLock { onKey?(code, true); return } // caps lock only reports presses
            if heldModifiers.remove(code) != nil { onKey?(code, false) }
            else { heldModifiers.insert(code); onKey?(code, true) }
        default:
            guard type.rawValue == Self.systemDefinedType,
                  let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return }
            let data = ns.data1
            let state = (data & 0xFF00) >> 8
            let isRepeat = data & 0x1 == 1
            guard state == 0xA || state == 0xB, !(isRepeat && state == 0xA) else { return }
            onKey?(Self.mediaKeyOffset + Int64((data & 0xFFFF0000) >> 16), state == 0xA)
        }
    }
}

private func keyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                            refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon {
        Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
    }
    return Unmanaged.passUnretained(event)
}
