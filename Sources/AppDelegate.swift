import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let switcher = SwitcherController()
    private let settings = Settings.shared
    private var trustTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        installSignalHandlers()
        if settings.enabled { enableSwitcher(prompt: true) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        switcher.stop()
    }

    // MARK: - Enable / disable

    private func enableSwitcher(prompt: Bool) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            switcher.start()
            updateStatusIcon()
            return
        }
        // Wait for the user to grant Accessibility access, then start.
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] t in
            guard let self, AXIsProcessTrusted() else { return }
            t.invalidate()
            if self.settings.enabled { self.switcher.start() }
            self.updateStatusIcon()
        }
    }

    private func disableSwitcher() {
        trustTimer?.invalidate()
        switcher.stop()
        updateStatusIcon()
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "circle.hexagongrid.circle",
                                           accessibilityDescription: "NeonSwitch")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        statusItem?.button?.appearsDisabled = !switcher.isRunning
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let trusted = AXIsProcessTrusted()

        let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        header.attributedTitle = NSAttributedString(string: "NEON.SWITCH", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .heavy),
            .foregroundColor: settings.theme.nsColor,
        ])
        menu.addItem(header)
        let status: String
        if switcher.isRunning { status = "● Active — replacing ⌘Tab" }
        else if settings.enabled && !trusted { status = "○ Waiting for Accessibility access" }
        else { status = "○ Paused — using macOS ⌘Tab" }
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        menu.addItem(item("Use as Default ⌘Tab Switcher", checked: settings.enabled, key: "d") { [weak self] in
            guard let self else { return }
            self.settings.enabled.toggle()
            self.settings.enabled ? self.enableSwitcher(prompt: true) : self.disableSwitcher()
        })
        menu.addItem(item("Preview Switcher", key: "p") { [weak self] in
            // Let the menu close first so the panel isn't covered.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.switcher.preview() }
        })
        menu.addItem(.separator())

        menu.addItem(submenu("Theme", NeonTheme.allCases.map { theme in
            let i = item(theme.title, checked: settings.theme == theme) { [weak self] in self?.settings.theme = theme }
            i.image = Self.swatch(theme.nsColor, theme.nsAccent)
            return i
        }))
        menu.addItem(submenu("Size", SwitcherSize.allCases.map { size in
            item(size.title, checked: settings.size == size) { [weak self] in self?.settings.size = size }
        }))
        menu.addItem(submenu("Popup Delay", ShowDelay.allCases.map { delay in
            item(delay.title, checked: settings.delay == delay) { [weak self] in self?.settings.delay = delay }
        }))
        menu.addItem(submenu("Effects", [
            item("Animated Rings", checked: settings.animations) { [weak self] in self?.settings.animations.toggle() },
            item("Glitch Text", checked: settings.glitch) { [weak self] in self?.settings.glitch.toggle() },
            item("Scanlines", checked: settings.scanlines) { [weak self] in self?.settings.scanlines.toggle() },
        ]))
        menu.addItem(submenu("Mouse", [
            item("Hover to Select", checked: settings.mouseHover) { [weak self] in self?.settings.mouseHover.toggle() },
            item("Stay Open After Releasing ⌘", checked: settings.stickyMode) { [weak self] in self?.settings.stickyMode.toggle() },
        ]))
        menu.addItem(item("Show Hidden Apps", checked: settings.showHiddenApps) { [weak self] in
            self?.settings.showHiddenApps.toggle()
        })
        menu.addItem(.separator())

        menu.addItem(item("Launch at Login", checked: SMAppService.mainApp.status == .enabled) {
            do {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
                else { try SMAppService.mainApp.register() }
            } catch {
                NSLog("NeonSwitch: login item error: \(error)")
            }
        })
        if !trusted {
            menu.addItem(item("Grant Accessibility Access…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            })
        }
        menu.addItem(item("Reset Appearance to Defaults") { [weak self] in self?.settings.resetToDefaults() })
        menu.addItem(.separator())
        menu.addItem(item("Quit NeonSwitch", key: "q") { NSApp.terminate(nil) })
    }

    // MARK: - Menu helpers

    private final class ActionItem: NSMenuItem {
        var handler: (() -> Void)?
        @objc func fire() { handler?() }
    }

    private func item(_ title: String, checked: Bool = false, key: String = "", action: @escaping () -> Void) -> NSMenuItem {
        let i = ActionItem(title: title, action: #selector(ActionItem.fire), keyEquivalent: key)
        i.target = i
        i.handler = action
        i.state = checked ? .on : .off
        return i
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu(title: title)
        items.forEach(sub.addItem)
        parent.submenu = sub
        return parent
    }

    /// Two-tone dot: primary on the left half, accent on the right.
    private static func swatch(_ primary: NSColor, _ accent: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let dot = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            dot.addClip()
            primary.setFill()
            NSRect(x: 0, y: 0, width: rect.midX, height: rect.height).fill()
            accent.setFill()
            NSRect(x: rect.midX, y: 0, width: rect.midX, height: rect.height).fill()
            return true
        }
    }

    /// Make sure the system ⌘Tab switcher is restored if we get killed.
    private func installSignalHandlers() {
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig) { _ in
                SystemSwitcher.setEnabled(true)
                exit(0)
            }
        }
    }
}
