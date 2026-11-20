import AppKit
import Combine
import SwiftUI

/// Left-click the menu bar icon → popover with everything. Right-click → quick favorites menu.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: AppState!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settings: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        state = AppState()
        state.openSettings = { [weak self] tab in self?.showSettings(tab) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        popover.behavior = .transient
        let host = NSHostingController(rootView: PopoverView(state: state))
        host.sizingOptions = [.preferredContentSize] // popover height follows the content
        popover.contentViewController = host

        state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateIcon() }
            .store(in: &cancellables)
        updateIcon()

        if !state.listening {
            showSettings(.general) // walk through the permission first
        } else if !UserDefaults.standard.bool(forKey: "didShowPopover") {
            UserDefaults.standard.set(true, forKey: "didShowPopover")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showPopover() }
        }
    }

    // Opening Clacky again from Finder/Spotlight shows the popover.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return true
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let symbol = !state.listening ? "exclamationmark.triangle" : (state.enabled ? "keyboard" : "keyboard.badge.ellipsis")
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Clacky")
        button.appearsDisabled = !state.enabled
        button.toolTip = "Clacky — \(state.selectedPack)"
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showQuickMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func showSettings(_ tab: SettingsTab) {
        popover.performClose(nil)
        if settings == nil { settings = SettingsWindowController(state: state) }
        settings?.show(tab)
    }

    // MARK: - Right-click menu

    private func showQuickMenu() {
        popover.performClose(nil)
        let menu = NSMenu()

        let sound = item(state.enabled ? "Sound On" : "Sound Off", #selector(toggleSound))
        sound.state = state.enabled ? .on : .off
        menu.addItem(sound)
        menu.addItem(.separator())

        let header = NSMenuItem(title: "Favorites", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let quick = state.favoritePacks.isEmpty ? Array(state.recentPacks.prefix(3)) : state.favoritePacks
        if quick.isEmpty {
            let empty = NSMenuItem(title: "Star sounds to see them here", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for (index, pack) in quick.enumerated() {
            let i = item(pack.name, #selector(choosePack(_:)), key: index < 9 ? "\(index + 1)" : "")
            i.representedObject = pack.name
            i.state = pack.name == state.selectedPack ? .on : .off
            menu.addItem(i)
        }
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettingsFromMenu), key: ","))
        menu.addItem(NSMenuItem(title: "Quit Clacky", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Attach only for this click so a left-click still opens the popover.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func toggleSound() { state.enabled.toggle() }
    @objc private func openSettingsFromMenu() { showSettings(.general) }

    @objc private func choosePack(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String { state.select(name) }
    }
}
