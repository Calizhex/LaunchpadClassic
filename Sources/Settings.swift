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

struct AppearanceSettings: Equatable, Codable {
    var columns: Int
    var rows: Int
    var iconScale: Double       // 0.5 … 1.5 (1 = jak w klasycznym Launchpadzie)
    var labelFontSize: Double   // punkty

    static let standard = AppearanceSettings(columns: 7, rows: 5, iconScale: 1.0, labelFontSize: 13)

    static let columnRange = 4...12
    static let rowRange = 3...8
    static let iconScaleRange = 0.5...1.5
    static let fontRange = 9.0...20.0
}

/// Zapisany układ siatki (gotowy albo własny).
struct GridPreset: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var appearance: AppearanceSettings

    static let builtIn: [GridPreset] = [
        GridPreset(id: "classic", name: "Klasyczny",
                   appearance: AppearanceSettings(columns: 7, rows: 5, iconScale: 1.0, labelFontSize: 13)),
        GridPreset(id: "comfort", name: "Wygodny",
                   appearance: AppearanceSettings(columns: 6, rows: 5, iconScale: 1.1, labelFontSize: 13)),
        GridPreset(id: "large", name: "Duże ikony",
                   appearance: AppearanceSettings(columns: 6, rows: 4, iconScale: 1.3, labelFontSize: 15)),
        GridPreset(id: "minimal", name: "Minimalistyczny",
                   appearance: AppearanceSettings(columns: 5, rows: 3, iconScale: 1.5, labelFontSize: 16)),
        GridPreset(id: "compact", name: "Kompaktowy",
                   appearance: AppearanceSettings(columns: 8, rows: 6, iconScale: 0.85, labelFontSize: 12)),
        GridPreset(id: "monitor", name: "Duży monitor",
                   appearance: AppearanceSettings(columns: 10, rows: 6, iconScale: 0.9, labelFontSize: 13)),
        GridPreset(id: "max", name: "Maksimum",
                   appearance: AppearanceSettings(columns: 12, rows: 8, iconScale: 0.7, labelFontSize: 10)),
    ]
}

enum Preferences {
    private static var d: UserDefaults { .standard }

    static var customPresets: [GridPreset] {
        get {
            guard let data = d.data(forKey: "customPresets"),
                  let list = try? JSONDecoder().decode([GridPreset].self, from: data) else { return [] }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { d.set(data, forKey: "customPresets") }
        }
    }

    static var appearance: AppearanceSettings {
        get {
            let s = AppearanceSettings.standard
            let cols = d.object(forKey: "columns") as? Int ?? s.columns
            let rows = d.object(forKey: "rows") as? Int ?? s.rows
            let scale = d.object(forKey: "iconScale") as? Double ?? s.iconScale
            let font = d.object(forKey: "labelFontSize") as? Double ?? s.labelFontSize
            return AppearanceSettings(
                columns: min(max(cols, AppearanceSettings.columnRange.lowerBound), AppearanceSettings.columnRange.upperBound),
                rows: min(max(rows, AppearanceSettings.rowRange.lowerBound), AppearanceSettings.rowRange.upperBound),
                iconScale: min(max(scale, AppearanceSettings.iconScaleRange.lowerBound), AppearanceSettings.iconScaleRange.upperBound),
                labelFontSize: min(max(font, AppearanceSettings.fontRange.lowerBound), AppearanceSettings.fontRange.upperBound))
        }
        set {
            d.set(newValue.columns, forKey: "columns")
            d.set(newValue.rows, forKey: "rows")
            d.set(newValue.iconScale, forKey: "iconScale")
            d.set(newValue.labelFontSize, forKey: "labelFontSize")
        }
    }

    static var showMenuBarIcon: Bool {
        get { d.object(forKey: "showMenuBarIcon") as? Bool ?? true }
        set { d.set(newValue, forKey: "showMenuBarIcon") }
    }

    static var showDockIcon: Bool {
        get { d.object(forKey: "showDockIcon") as? Bool ?? true }
        set { d.set(newValue, forKey: "showDockIcon") }
    }

    static var showFPS: Bool {
        get { d.bool(forKey: "showFPS") }
        set { d.set(newValue, forKey: "showFPS") }
    }

    static var autoCheckUpdates: Bool {
        get { d.object(forKey: "autoCheckUpdates") as? Bool ?? true }
        set { d.set(newValue, forKey: "autoCheckUpdates") }
    }

    static var lastUpdateCheck: Date? {
        get { d.object(forKey: "lastUpdateCheck") as? Date }
        set { d.set(newValue, forKey: "lastUpdateCheck") }
    }

    static var skippedBuild: Int {
        get { d.integer(forKey: "skippedBuild") }
        set { d.set(newValue, forKey: "skippedBuild") }
    }

    /// Token GitHuba trzymany w pliku z uprawnieniami 0600 (pęk kluczy pytałby o zgodę po każdej aktualizacji,
    /// bo aplikacja nie ma stałego podpisu dewelopera).
    private static var tokenURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("LaunchpadClassic", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("github-token")
    }

    static var githubToken: String? {
        get {
            guard let s = try? String(contentsOf: tokenURL, encoding: .utf8) else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        set {
            let fm = FileManager.default
            if let v = newValue?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                fm.createFile(atPath: tokenURL.path, contents: Data(v.utf8), attributes: [.posixPermissions: 0o600])
            } else {
                try? fm.removeItem(at: tokenURL)
            }
        }
    }

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
