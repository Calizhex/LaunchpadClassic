import AppKit
import Carbon
import ServiceManagement

enum HotKeyOption: String, CaseIterable, Identifiable {
    case none, ctrlCmdL, optCmdL, optSpace, ctrlOptSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Brak"
        case .ctrlCmdL: return "⌃⌘L"
        case .optCmdL: return "⌥⌘L"
        case .optSpace: return "⌥ Spacja"
        case .ctrlOptSpace: return "⌃⌥ Spacja"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .ctrlCmdL, .optCmdL: return 37        // L
        case .optSpace, .ctrlOptSpace: return 49   // Spacja
        case .none: return 0
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .ctrlCmdL: return UInt32(controlKey | cmdKey)
        case .optCmdL: return UInt32(optionKey | cmdKey)
        case .optSpace: return UInt32(optionKey)
        case .ctrlOptSpace: return UInt32(controlKey | optionKey)
        case .none: return 0
        }
    }
}

enum HotCorner: String, CaseIterable, Identifiable {
    case none, topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Brak"
        case .topLeft: return "Lewy górny"
        case .topRight: return "Prawy górny"
        case .bottomLeft: return "Lewy dolny"
        case .bottomRight: return "Prawy dolny"
        }
    }
}

enum Preferences {
    static var hotKey: HotKeyOption {
        get { HotKeyOption(rawValue: UserDefaults.standard.string(forKey: "hotKey") ?? "") ?? .ctrlCmdL }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "hotKey") }
    }

    static var hotCorner: HotCorner {
        get { HotCorner(rawValue: UserDefaults.standard.string(forKey: "hotCorner") ?? "") ?? .none }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "hotCorner") }
    }
}

/// Globalny skrót klawiszowy (Carbon – nie wymaga uprawnień Dostępności).
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    var action: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false

    func register(_ option: HotKeyOption) {
        if let ref {
            UnregisterEventHotKey(ref)
            self.ref = nil
        }
        guard option != .none else { return }
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { (_, _, _) -> OSStatus in
                Task { @MainActor in HotKeyCenter.shared.action?() }
                return OSStatus(noErr)
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C50_4144), id: 1)   // 'LPAD'
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(option.keyCode, option.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &newRef)
        if status == OSStatus(noErr) { ref = newRef }
    }
}

/// Własny „gorący narożnik” – śledzenie myszy nie wymaga dodatkowych uprawnień.
@MainActor
final class HotCornerMonitor {
    var corner: HotCorner = .none
    var action: (() -> Void)?
    private var monitors: [Any] = []
    private var inCorner = false

    func start() {
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] e in
            MainActor.assumeIsolated { self?.check() }
            return e
        }) { monitors.append(l) }
    }

    private func check() {
        guard corner != .none else { inCorner = false; return }
        let p = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(p) }) else { return }
        let f = screen.frame
        let t: CGFloat = 3
        let left = p.x <= f.minX + t
        let right = p.x >= f.maxX - t
        let top = p.y >= f.maxY - t
        let bottom = p.y <= f.minY + t
        let hit: Bool
        switch corner {
        case .topLeft: hit = top && left
        case .topRight: hit = top && right
        case .bottomLeft: hit = bottom && left
        case .bottomRight: hit = bottom && right
        case .none: hit = false
        }
        if hit && !inCorner { action?() }
        inCorner = hit
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("LaunchpadClassic: login item error: \(error.localizedDescription)")
        }
    }
}
