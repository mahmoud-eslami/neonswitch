import AppKit
import SwiftUI

// Private CoreGraphics API (same approach AltTab uses) to turn the native ⌘Tab off while we run.
@_silgen_name("CGSSetSymbolicHotKeyEnabled")
private func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ enabled: Bool) -> CGError

enum SystemSwitcher {
    static func setEnabled(_ enabled: Bool) {
        _ = CGSSetSymbolicHotKeyEnabled(1, enabled) // ⌘Tab
        _ = CGSSetSymbolicHotKeyEnabled(2, enabled) // ⌘⇧Tab
    }
}

private enum Key {
    static let tab: Int64 = 48
    static let esc: Int64 = 53
    static let ret: Int64 = 36
    static let left: Int64 = 123
    static let right: Int64 = 124
    static let down: Int64 = 125
    static let up: Int64 = 126
    static let q: Int64 = 12
    static let h: Int64 = 4
}

struct AppItem: Identifiable {
    let id: pid_t
    let app: NSRunningApplication
    let name: String
    let icon: NSImage
}

final class SwitcherModel: ObservableObject {
    @Published var items: [AppItem] = []
    @Published private(set) var selected: Int = 0
    /// Unwrapped ring position (cursor mod count == selected). Lets the highlight
    /// keep rotating forward past the last app instead of spinning back to the first.
    @Published private(set) var cursor: Int = 0

    /// Move by `delta` slots in that direction, wrapping around the ring.
    func step(_ delta: Int) {
        let n = items.count
        guard n > 0 else { return }
        cursor += delta
        selected = ((cursor % n) + n) % n
    }

    /// Jump to `index` along the shortest way around the ring (mouse picks).
    func select(_ index: Int) {
        let n = items.count
        guard items.indices.contains(index), index != selected else { return }
        var diff = (index - selected) % n
        if diff > n / 2 { diff -= n } else if diff < -n / 2 { diff += n }
        cursor += diff
        selected = index
    }

    /// Place the selection without animating (switcher opening, list changes).
    func reset(to index: Int) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            selected = index
            cursor = index
        }
    }
}

final class SwitcherController {
    let model = SwitcherModel()
    private var panel: NSPanel!
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var recency: [pid_t] = []
    private var active = false
    private var showWork: DispatchWorkItem?
    private var previewToken: UUID?
    private var scrollAccum: Double = 0
    var isRunning: Bool { tap != nil }

    init() {
        buildPanel()
        seedRecency()
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.touch(app.processIdentifier)
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.recency.removeAll { $0 == app.processIdentifier }
            if self.active { self.refreshItems(keepSelection: true) }
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard tap == nil else { return }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged,
                                    .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                    .rightMouseDown, .rightMouseUp, .scrollWheel]
        let mask = types.reduce(0) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<SwitcherController>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            NSLog("NeonSwitch: failed to create event tap (Accessibility permission?)")
            return
        }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        SystemSwitcher.setEnabled(false)
    }

    func stop() {
        SystemSwitcher.setEnabled(true)
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let cmd = flags.contains(.maskCommand)
        let shift = flags.contains(.maskShift)
        let key = event.getIntegerValueField(.keyboardEventKeycode)

        switch type {
        case .flagsChanged:
            // In sticky mode a visible switcher stays open for mouse/keyboard picking.
            if active && !cmd && !(Settings.shared.stickyMode && panel.isVisible) { commit() }
            return Unmanaged.passUnretained(event)

        case .mouseMoved, .leftMouseDragged:
            guard active, panel.isVisible else { return Unmanaged.passUnretained(event) }
            if Settings.shared.mouseHover, let hit = hitTest(event.location), hit >= 0 {
                model.select(hit)
            }
            return Unmanaged.passUnretained(event)

        case .leftMouseDown:
            guard active, panel.isVisible else { return Unmanaged.passUnretained(event) }
            if let hit = hitTest(event.location) {
                if hit >= 0 { model.select(hit) }
                commit() // icon or center core: switch to selection
            } else {
                cancel() // clicked outside the ring
            }
            return nil

        case .rightMouseDown:
            guard active, panel.isVisible else { return Unmanaged.passUnretained(event) }
            cancel()
            return nil

        case .leftMouseUp, .rightMouseUp:
            return active && panel.isVisible ? nil : Unmanaged.passUnretained(event)

        case .scrollWheel:
            guard active, panel.isVisible else { return Unmanaged.passUnretained(event) }
            let dy = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            scrollAccum += dy
            if abs(scrollAccum) >= 12 {
                step(scrollAccum > 0 ? -1 : 1)
                scrollAccum = 0
            }
            return nil

        case .keyDown:
            if cmd && key == Key.tab {
                if active { step(shift ? -1 : 1) } else { begin(reverse: shift) }
                return nil
            }
            guard active else { return Unmanaged.passUnretained(event) }
            switch key {
            case Key.tab: step(shift ? -1 : 1) // ⌘ already released in sticky mode
            case Key.esc: cancel()
            case Key.ret: commit()
            case Key.left, Key.up: step(-1)
            case Key.right, Key.down: step(1)
            case Key.q: quitSelected()
            case Key.h: hideSelected()
            default: break
            }
            return nil // swallow everything while the switcher is up

        case .keyUp:
            return active ? nil : Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - Switcher actions

    private func begin(reverse: Bool) {
        refreshItems(keepSelection: false)
        guard !model.items.isEmpty else { return }
        active = true
        let n = model.items.count
        model.reset(to: 0)
        if n > 1 { model.step(reverse ? -1 : 1) }
        // Like the native switcher: a quick tap switches without flashing the UI.
        let work = DispatchWorkItem { [weak self] in self?.showPanel() }
        showWork = work
        let delay = Settings.shared.delay.seconds
        if delay == 0 { work.perform() } else { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }
    }

    /// Shows the switcher from the menu bar so settings can be checked; closes itself after a few seconds.
    func preview() {
        if active { dismiss() }
        refreshItems(keepSelection: false)
        guard !model.items.isEmpty else { return }
        active = true
        model.reset(to: 0)
        if model.items.count > 1 { model.step(1) }
        showPanel()
        let token = UUID()
        previewToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.previewToken == token, self.active else { return }
            self.dismiss()
        }
    }

    private func step(_ delta: Int) {
        let n = model.items.count
        guard n > 0 else { return }
        model.step(delta)
        showPanel()
    }

    func commit() {
        guard active else { return }
        let items = model.items
        let idx = model.selected
        dismiss()
        guard items.indices.contains(idx) else { return }
        activate(items[idx].app)
    }

    private func cancel() { dismiss() }

    private func dismiss() {
        active = false
        previewToken = nil
        showWork?.cancel()
        showWork = nil
        panel.orderOut(nil)
    }

    private func quitSelected() {
        guard model.items.indices.contains(model.selected) else { return }
        model.items[model.selected].app.terminate()
    }

    private func hideSelected() {
        guard model.items.indices.contains(model.selected) else { return }
        model.items[model.selected].app.hide()
    }

    private func activate(_ target: NSRunningApplication) {
        if target.isHidden { target.unhide() }
        NSApp.yieldActivation(to: target)
        target.activate(options: [.activateAllWindows])
        // Accessibility fallback: reliable even under cooperative activation rules.
        let ax = AXUIElementCreateApplication(target.processIdentifier)
        AXUIElementSetAttributeValue(ax, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        // Restore minimized windows, if the app has nothing else visible.
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement], !windows.isEmpty {
            let minimized = windows.filter { w in
                var v: CFTypeRef?
                AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &v)
                return (v as? Bool) == true
            }
            if minimized.count == windows.count, let w = minimized.first {
                AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            }
        }
        touch(target.processIdentifier)
    }

    // MARK: - App list

    private func seedRecency() {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        recency = apps.map(\.processIdentifier)
        if let front = NSWorkspace.shared.frontmostApplication { touch(front.processIdentifier) }
    }

    private func touch(_ pid: pid_t) {
        recency.removeAll { $0 == pid }
        recency.insert(pid, at: 0)
    }

    private func refreshItems(keepSelection: Bool) {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != getpid()
                && (Settings.shared.showHiddenApps || !$0.isHidden)
        }
        let byPid = Dictionary(running.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        for app in running where !recency.contains(app.processIdentifier) {
            recency.append(app.processIdentifier)
        }
        recency.removeAll { byPid[$0] == nil }
        if let front = NSWorkspace.shared.frontmostApplication, byPid[front.processIdentifier] != nil {
            touch(front.processIdentifier)
        }
        let previousPid = keepSelection && model.items.indices.contains(model.selected) ? model.items[model.selected].id : nil
        model.items = recency.compactMap { pid in
            guard let app = byPid[pid] else { return nil }
            return AppItem(id: pid, app: app,
                           name: app.localizedName ?? "Unknown",
                           icon: app.icon ?? NSImage(named: NSImage.applicationIconName)!)
        }
        if let previousPid, let i = model.items.firstIndex(where: { $0.id == previousPid }) {
            model.reset(to: i)
        } else {
            model.reset(to: min(model.selected, max(model.items.count - 1, 0)))
        }
    }

    // MARK: - Panel

    private static let panelSize = CGSize(width: 700, height: 700)

    private func buildPanel() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        let host = NSHostingView(rootView: SwitcherView(model: model))
        host.frame = NSRect(origin: .zero, size: Self.panelSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
    }

    /// Maps a global (top-left origin) mouse location onto the ring.
    /// Returns nil outside the switcher, index -1 for the center core, otherwise the app slice under the pointer.
    private func hitTest(_ location: CGPoint) -> Int? {
        guard let primary = NSScreen.screens.first else { return nil }
        let point = CGPoint(x: location.x, y: primary.frame.maxY - location.y) // to Cocoa coords
        let frame = panel.frame
        let scale = Settings.shared.size.scale
        // Offset from center in unscaled view units, y pointing down like SwiftUI.
        let dx = (point.x - frame.midX) / scale
        let dy = (frame.midY - point.y) / scale
        let dist = hypot(dx, dy)
        if dist > SwitcherView.size / 2 - 30 { return nil }
        if dist < 110 { return -1 }
        let n = model.items.count
        guard n > 0 else { return nil }
        // Angle measured clockwise from 12 o'clock, matching icon placement.
        var a = atan2(dy, dx) + .pi / 2
        if a < 0 { a += 2 * .pi }
        let index = Int((a / (2 * .pi) * Double(n)).rounded()) % n
        return index
    }

    private func showPanel() {
        guard active, !panel.isVisible else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let scale = Settings.shared.size.scale
        let size = CGSize(width: Self.panelSize.width * scale, height: Self.panelSize.height * scale)
        let origin = CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }
}
