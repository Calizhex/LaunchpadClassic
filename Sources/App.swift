import AppKit
import QuartzCore
import SwiftUI

@main
@MainActor
enum LaunchpadClassicMain {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: LaunchpadController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        let c = LaunchpadController()
        controller = c
        c.startServices()
        // Po zalogowaniu (start z elementów logowania) nie pokazujemy nakładki od razu.
        if ProcessInfo.processInfo.systemUptime > 120 {
            c.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.show()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Zakończ Launchpad Classic", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edycja")
        edit.addItem(withTitle: "Wytnij", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopiuj", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Wklej", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Zaznacz wszystko", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}

/// Pełnoekranowy panel nad Dockiem i paskiem menu – jak klasyczny Launchpad.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class LaunchpadController: NSObject, NSWindowDelegate {
    let model: LaunchpadModel
    private let window: OverlayPanel
    private let hotCornerMonitor: HotCornerMonitor
    private var monitors: [Any] = []
    private var pendingHide: DispatchWorkItem?
    private var wallpaperURL: URL?
    let updater: Updater
    private var displayLink: CADisplayLink?
    private var pendingDragPoint: CGPoint?
    private let settings: SettingsWindowController
    private let statusBar: StatusBarController

    override init() {
        model = LaunchpadModel()
        hotCornerMonitor = HotCornerMonitor()
        updater = Updater()
        settings = SettingsWindowController(model: model, updater: updater)
        statusBar = StatusBarController(updater: updater)
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window = OverlayPanel(contentRect: frame,
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered,
                              defer: false)
        super.init()

        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = false
        window.acceptsMouseMovedEvents = true
        window.isMovable = false
        window.animationBehavior = .none
        window.delegate = self

        let host = FirstMouseHostingView(rootView: RootView(model: model))
        host.sizingOptions = []
        window.contentView = host

        // Zegar klatek w rytmie ekranu (ProMotion 120 Hz, Air 60 Hz…). Działa tylko, gdy nakładka jest widoczna.
        let link = host.displayLink(target: self, selector: #selector(frameTick(_:)))
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        displayLink = link
        NotificationCenter.default.addObserver(self, selector: #selector(powerStateChanged),
                                               name: .NSProcessInfoPowerStateDidChange, object: nil)

        model.hideHandler = { [weak self] in self?.hide() }
        model.onSettingsChanged = { [weak self] in self?.applySettings() }
        hotCornerMonitor.action = { [weak self] in self?.toggle() }
        HotKeyCenter.shared.action = { [weak self] in self?.toggle() }
        model.openSettingsHandler = { [weak self] in self?.openSettings(nil) }
        updater.onOpenUpdates = { [weak self] in self?.openSettings(.updates) }
        updater.onStatusChange = { [weak self] in self?.statusBar.refreshIcon() }
        statusBar.onOpen = { [weak self] in self?.show() }
        statusBar.onSettings = { [weak self] tab in self?.openSettings(tab) }
        statusBar.hotKeyTitle = { [weak self] in
            guard let self, self.model.hotKey != .none else { return "" }
            return self.model.hotKey.title
        }

        installMonitors()
        hotCornerMonitor.start()
        applySettings()
    }

    private func applySettings() {
        HotKeyCenter.shared.register(model.hotKey)
        hotCornerMonitor.corner = model.hotCorner
        statusBar.setVisible(model.showMenuBarIcon)
        let policy: NSApplication.ActivationPolicy = model.showDockIcon ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    func startServices() {
        updater.start()
    }

    func openSettings(_ tab: SettingsTab?) {
        if model.visible {
            model.resetForHide()
            model.visible = false
            pendingHide?.cancel()
            window.orderOut(nil)
            displayLink?.isPaused = true
        }
        settings.show(tab: tab)
    }

    // MARK: Pokazywanie / ukrywanie

    func toggle() {
        if model.visible { hide() } else { show() }
    }

    func show() {
        pendingHide?.cancel()
        pendingHide = nil
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main ?? NSScreen.screens[0]
        if model.visible && window.isVisible && window.screen == screen {
            window.makeKeyAndOrderFront(nil)
            return
        }
        window.setFrame(screen.frame, display: false)
        model.viewSize = screen.frame.size
        displayLink?.preferredFrameRateRange = model.clock.configure(for: screen)
        model.clock.reset()
        displayLink?.isPaused = false
        loadWallpaper(for: screen)
        model.rescanAsync()
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        focusSearch()
        withAnimation(.easeOut(duration: 0.22)) { model.visible = true }
    }

    func hide() {
        guard model.visible else { return }
        model.resetForHide()
        withAnimation(.easeIn(duration: 0.18)) { model.visible = false }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.model.visible else { return }
                self.window.orderOut(nil)
                self.displayLink?.isPaused = true
                if NSApp.isActive && !self.settings.isVisible { NSApp.hide(nil) }
            }
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func focusSearch(retry: Bool = true) {
        guard let field = model.searchField else {
            // Przy pierwszym pokazaniu SwiftUI mogło jeszcze nie utworzyć pola – spróbuj po układzie.
            if retry {
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated { self?.focusSearch(retry: false) }
                }
            }
            return
        }
        window.makeFirstResponder(field)
        (field.currentEditor() as? NSTextView)?.insertionPointColor = .white
    }

    func windowDidResignKey(_ notification: Notification) {
        if model.visible { hide() }
    }

    private func loadWallpaper(for screen: NSScreen) {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            model.wallpaper = nil
            return
        }
        if url == wallpaperURL, model.wallpaper != nil { return }
        wallpaperURL = url
        Task.detached(priority: .userInitiated) { [weak self] in
            let image = Wallpaper.blurred(url: url)
            await self?.setWallpaper(image)
        }
    }

    private func setWallpaper(_ image: CGImage?) {
        if let image {
            model.wallpaper = NSImage(cgImage: image, size: .zero)
        } else {
            model.wallpaper = nil
        }
    }

    // MARK: Zdarzenia

    private func installMonitors() {
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            MainActor.assumeIsolated { () -> NSEvent? in
                guard let self else { return event }
                return self.handleKey(event)
            }
        }) { monitors.append(m) }

        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            MainActor.assumeIsolated { () -> NSEvent? in
                guard let self, self.model.visible, event.window === self.window else { return event }
                self.model.handleScroll(event)
                return nil
            }
        }) { monitors.append(m) }

        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp], handler: { [weak self] event in
            MainActor.assumeIsolated { () -> NSEvent? in
                guard let self, self.model.drag != nil else { return event }
                if event.type == .leftMouseDragged {
                    // Pozycję nakładamy raz na klatkę (frameTick) – mysz z wysokim próbkowaniem nie zatyka renderowania.
                    self.pendingDragPoint = self.rootPoint(event)
                } else {
                    if let p = self.pendingDragPoint {
                        self.pendingDragPoint = nil
                        self.model.updateDrag(to: p)
                    }
                    self.model.endDrag()
                }
                return event
            }
        }) { monitors.append(m) }
    }

    @objc private func frameTick(_ link: CADisplayLink) {
        if let p = pendingDragPoint {
            pendingDragPoint = nil
            model.updateDrag(to: p)
        }
        model.applyPendingScroll()
        model.clock.frame(timestamp: link.targetTimestamp, animating: model.editing)
    }

    @objc private func powerStateChanged() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.visible, let screen = self.window.screen else { return }
                self.displayLink?.preferredFrameRateRange = self.model.clock.configure(for: screen)
            }
        }
    }

    private func rootPoint(_ event: NSEvent) -> CGPoint {
        let height = window.contentView?.bounds.height ?? window.frame.height
        let p = event.window === window
            ? event.locationInWindow
            : window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return CGPoint(x: p.x, y: height - p.y)
    }

    private func handleKey(_ e: NSEvent) -> NSEvent? {
        guard model.visible, e.window === window else { return e }
        let code = e.keyCode
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if model.isRenamingFolder {
            if code == 36 || code == 76 || code == 53 {
                model.isRenamingFolder = false
                focusSearch()
                return nil
            }
            return e
        }

        if flags.contains(.command) {
            if code == 123 { model.go(to: model.currentPage - 1); return nil }
            if code == 124 { model.go(to: model.currentPage + 1); return nil }
            switch (e.charactersIgnoringModifiers ?? "").lowercased() {
            case "q": NSApp.terminate(nil); return nil
            case "w": hide(); return nil
            case "v": NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil); return nil
            case "c": NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil); return nil
            case "x": NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil); return nil
            case "a": NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil); return nil
            default: return e
            }
        }

        switch code {
        case 53: model.escape(); return nil                       // Esc
        case 36, 76: model.activateSelection(); return nil        // Return / Enter
        case 123: model.moveSelection(dx: -1, dy: 0); return nil  // ←
        case 124: model.moveSelection(dx: 1, dy: 0); return nil   // →
        case 125: model.moveSelection(dx: 0, dy: 1); return nil   // ↓
        case 126: model.moveSelection(dx: 0, dy: -1); return nil  // ↑
        default:
            if let field = model.searchField, window.firstResponder !== field.currentEditor() {
                focusSearch()
            }
            return e
        }
    }
}
