import AppKit
import Carbon
import os

/// Health logging, readable with:
///   log show --last 1h --predicate 'subsystem == "com.yashasviyadav.clacky"'
/// Only counts key presses — never which keys.
enum Diagnostics {
    static let log = Logger(subsystem: "com.yashasviyadav.clacky", category: "health")

    /// True while some app has Secure Input on (password fields etc.); macOS then hides
    /// all keystrokes from Clacky.
    static var secureInputOn: Bool { IsSecureEventInputEnabled() }

    /// The app holding Secure Input (it hides every keystroke from Clacky), if macOS says.
    static var secureInputApp: String? {
        guard secureInputOn,
              let dict = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = dict["kCGSSessionSecureInputPID"] as? Int32,
              let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        return app.localizedName
    }
}
