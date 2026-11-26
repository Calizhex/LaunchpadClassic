import AppKit
import SwiftUI

enum SettingsTab: Hashable {
    case appearance, general, updates
}

@MainActor
final class SettingsSelection: ObservableObject {
    @Published var tab: SettingsTab = .appearance
}

// MARK: - Okno

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: LaunchpadModel
    private let updater: Updater
    private let selection = SettingsSelection()
    private var window: NSWindow?

    init(model: LaunchpadModel, updater: Updater) {
        self.model = model
        self.updater = updater
    }

    static let size = NSSize(width: 620, height: 760)

    var isVisible: Bool { window?.isVisible ?? false }

    func show(tab: SettingsTab? = nil) {
        if let tab { selection.tab = tab }
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(model: model, updater: updater, selection: selection))
            host.sizingOptions = []
            let w = NSWindow(contentViewController: host)
            w.title = "Ustawienia Launchpad Classic"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.setContentSize(Self.size)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Widok ustawień

struct SettingsView: View {
    @ObservedObject var model: LaunchpadModel
    @ObservedObject var updater: Updater
    @ObservedObject var selection: SettingsSelection

    var body: some View {
        TabView(selection: $selection.tab) {
            AppearanceTab(model: model)
                .tabItem { Label("Wygląd", systemImage: "square.grid.3x3") }
                .tag(SettingsTab.appearance)
            GeneralTab(model: model)
                .tabItem { Label("Ogólne", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            UpdatesTab(updater: updater)
                .tabItem { Label("Aktualizacje", systemImage: "arrow.triangle.2.circlepath") }
                .tag(SettingsTab.updates)
        }
        .padding(.top, 8)
        .frame(width: SettingsWindowController.size.width, height: SettingsWindowController.size.height)
    }
}

// MARK: Wygląd

struct AppearanceTab: View {
    @ObservedObject var model: LaunchpadModel
    @State private var newPresetName = ""

    private let presetColumns = [GridItem(.adaptive(minimum: 118), spacing: 10)]

    var body: some View {
        let a = model.appearance
        Form {
            Section("Podgląd") {
                GridPreview(model: model)
                    .frame(height: 230)
                    .frame(maxWidth: .infinity)
            }
            Section("Gotowe układy") {
                LazyVGrid(columns: presetColumns, spacing: 10) {
                    ForEach(GridPreset.builtIn) { preset in
                        PresetCard(preset: preset, active: a == preset.appearance) {
                            model.applyPreset(preset)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Moje układy") {
                if model.customPresets.isEmpty {
                    Text("Ustaw siatkę po swojemu, nadaj jej nazwę i zapisz – wrócisz do niej jednym kliknięciem.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                } else {
                    LazyVGrid(columns: presetColumns, spacing: 10) {
                        ForEach(model.customPresets) { preset in
                            PresetCard(preset: preset, active: a == preset.appearance,
                                       action: { model.applyPreset(preset) },
                                       onDelete: { model.deletePreset(preset) })
                        }
                    }
                    .padding(.vertical, 4)
                }
                HStack {
                    TextField("Nazwa, np. „Praca – monitor”", text: $newPresetName)
                        .onSubmit(savePreset)
                    Button("Zapisz bieżący układ", action: savePreset)
                        .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section("Ikony na stronie") {
                Stepper(value: $model.appearance.columns, in: AppearanceSettings.columnRange) {
                    LabeledContent("Kolumny", value: "\(a.columns)")
                }
                Stepper(value: $model.appearance.rows, in: AppearanceSettings.rowRange) {
                    LabeledContent("Wiersze", value: "\(a.rows)")
                }
                LabeledContent("Razem na stronie", value: "\(a.columns * a.rows)")
            }
            Section("Rozmiar") {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Wielkość ikon", value: "\(Int((a.iconScale * 100).rounded())) %")
                    Slider(value: $model.appearance.iconScale, in: AppearanceSettings.iconScaleRange, step: 0.05)
                }
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Wielkość podpisów", value: "\(Int(a.labelFontSize)) pt")
                    Slider(value: $model.appearance.labelFontSize, in: AppearanceSettings.fontRange, step: 1)
                }
                Text("Przy dużej liczbie kolumn i wierszy ikony zmniejszają się, żeby się zmieściły.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack {
                Button("Uzupełnij puste miejsca") { model.fillGaps() }
                Spacer()
                Button("Przywróć domyślne") { model.appearance = .standard }
            }
        }
        .formStyle(.grouped)
    }

    private func savePreset() {
        model.saveCurrentPreset(named: newPresetName)
        newPresetName = ""
    }
}

struct PresetCard: View {
    let preset: GridPreset
    let active: Bool
    let action: () -> Void
    var onDelete: (() -> Void)? = nil
    @State private var hovering = false

    var body: some View {
        let a = preset.appearance
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button(action: action) {
            VStack(spacing: 6) {
                GridGlyph(columns: a.columns, rows: a.rows, scale: a.iconScale)
                    .frame(width: 86, height: 54)
                Text(preset.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text("\(a.columns)×\(a.rows) · \(Int((a.iconScale * 100).rounded()))% · \(Int(a.labelFontSize)) pt")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(shape.fill(active ? Color.accentColor.opacity(0.14) : Color.primary.opacity(hovering ? 0.07 : 0.04)))
            .overlay(shape.stroke(active ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: active ? 2 : 0.5))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .overlay(alignment: .topTrailing) {
            if let onDelete, hovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Usuń układ")
                .padding(5)
            }
        }
        .contextMenu {
            if let onDelete {
                Button("Usuń układ „\(preset.name)”", role: .destructive, action: onDelete)
            }
        }
    }
}

/// Miniaturka siatki: tyle kwadracików, ile ikon mieści się na stronie.
struct GridGlyph: View {
    let columns: Int
    let rows: Int
    let scale: Double

    var body: some View {
        GeometryReader { g in
            let inset: CGFloat = 5
            let w = g.size.width - inset * 2
            let h = g.size.height - inset * 2
            let cw = w / CGFloat(max(columns, 1))
            let ch = h / CGFloat(max(rows, 1))
            let dot = min(cw, ch) * CGFloat(0.45 + 0.35 * (scale - 0.5))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                ForEach(0..<(columns * rows), id: \.self) { i in
                    RoundedRectangle(cornerRadius: dot * 0.28, style: .continuous)
                        .fill(Color.accentColor.opacity(0.8))
                        .frame(width: dot, height: dot)
                        .position(x: inset + (CGFloat(i % columns) + 0.5) * cw,
                                  y: inset + (CGFloat(i / columns) + 0.5) * ch)
                }
            }
        }
    }
}

/// Pomniejszona pierwsza strona – dokładnie tak, jak będzie wyglądać na ekranie.
struct GridPreview: View {
    @ObservedObject var model: LaunchpadModel

    var body: some View {
        let screen = NSScreen.main?.frame.size ?? CGSize(width: 1512, height: 982)
        GeometryReader { geo in
            let scale = min(geo.size.width / screen.width, geo.size.height / screen.height)
            let m = GridMetrics(size: screen, appearance: model.appearance)
            let items = Array((model.pages.first ?? []).prefix(m.perPage))
            ZStack(alignment: .topLeading) {
                BackgroundView(image: model.wallpaper)
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    VStack(spacing: m.labelSpacing) {
                        ItemIcon(model: model, item: item, size: m.iconSize)
                            .frame(width: m.iconSize, height: m.iconSize)
                        Text(model.title(of: item))
                            .font(.system(size: m.labelFont))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .frame(width: m.cellSize.width - 6, height: m.labelHeight)
                    }
                    .position(m.cellCenter(i))
                }
            }
            .frame(width: screen.width, height: screen.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: screen.width * scale, height: screen.height * scale, alignment: .topLeading)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

// MARK: Ogólne

struct GeneralTab: View {
    @ObservedObject var model: LaunchpadModel
    @State private var loginEnabled = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("Otwieranie") {
                Picker("Skrót klawiszowy", selection: $model.hotKey) {
                    ForEach(HotKeyOption.allCases) { Text($0.title).tag($0) }
                }
                Picker("Gorący narożnik", selection: $model.hotCorner) {
                    ForEach(HotCorner.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Otwieraj przy logowaniu", isOn: Binding(
                    get: { loginEnabled },
                    set: { LoginItem.set($0); loginEnabled = LoginItem.isEnabled }))
            }
            PerformanceSection(clock: model.clock)
            Section("Ikona aplikacji") {
                Toggle("Pokazuj na pasku menu", isOn: $model.showMenuBarIcon)
                Toggle("Pokazuj w Docku", isOn: $model.showDockIcon)
                Text("Przynajmniej jedna z ikon zawsze zostaje włączona.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section("Układ") {
                HStack {
                    Button("Uzupełnij puste miejsca") { model.fillGaps() }
                    Button("Odśwież listę aplikacji") { model.refreshAll() }
                    Button("Importuj stary układ") { model.importLegacy() }
                    Spacer()
                    Button("Ułóż alfabetycznie") { model.resetLayout() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct PerformanceSection: View {
    @ObservedObject var clock: FrameClock

    var body: some View {
        let hz = NSScreen.main?.maximumFramesPerSecond ?? 60
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        Section("Płynność") {
            LabeledContent("Ekran", value: hz > 60 ? "\(hz) Hz (ProMotion)" : "\(hz) Hz")
            LabeledContent("Animacje", value: lowPower ? "60 Hz – tryb niskiego zużycia energii" : "\(hz) Hz – dopasowane do ekranu")
            Toggle("Pokazuj licznik klatek (FPS)", isOn: $clock.showCounter)
            Text("Launchpad sam dopasowuje się do ekranu: na MacBooku Pro z ProMotion działa w 120 Hz, na MacBooku Air i zwykłych monitorach w 60 Hz. W trybie niskiego zużycia energii ogranicza się do 60 Hz.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Aktualizacje

struct UpdatesTab: View {
    @ObservedObject var updater: Updater
    @State private var token = ""

    var body: some View {
        Form {
            Section("Wersja") {
                LabeledContent("Zainstalowana", value: updater.currentVersionText)
                if let latest = updater.latest {
                    LabeledContent("Najnowsza na GitHubie", value: "build \(latest.build)")
                }
                if let last = updater.lastCheck {
                    LabeledContent("Ostatnie sprawdzenie",
                                   value: last.formatted(date: .abbreviated, time: .shortened))
                }
                Toggle("Sprawdzaj automatycznie (co 6 godzin)", isOn: $updater.autoCheck)
            }

            Section {
                HStack(spacing: 10) {
                    statusView
                    Spacer()
                    if updater.updateAvailable {
                        Button("Pobierz i zainstaluj") { Task { await updater.installLatest() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(updater.status == .downloading || updater.status == .installing)
                    }
                    Button("Sprawdź teraz") { Task { await updater.check(userInitiated: true) } }
                        .disabled(updater.status == .checking || updater.status == .downloading || updater.status == .installing)
                }
                if let latest = updater.latest, updater.updateAvailable {
                    Link("Zobacz wydanie na GitHubie", destination: latest.pageURL)
                        .font(.callout)
                }
            }

            Section("Dostęp do prywatnego repozytorium") {
                HStack {
                    SecureField(updater.hasToken ? "Token zapisany – wpisz nowy, aby zmienić" : "Wklej token GitHuba", text: $token)
                    Button("Zapisz") {
                        updater.setToken(token)
                        token = ""
                    }
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
                    if updater.hasToken {
                        Button("Usuń") { updater.setToken("") }
                    }
                }
                Text("Repozytorium jest prywatne, więc aplikacja potrzebuje tokenu tylko do odczytu. Na GitHubie: Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token. Wybierz tylko repozytorium LaunchpadClassic i uprawnienie Contents: Read-only.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var statusView: some View {
        switch updater.status {
        case .idle:
            Text("Nie sprawdzano jeszcze w tej sesji.").foregroundColor(.secondary)
        case .checking:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Sprawdzanie…") }
        case .upToDate:
            Label("Masz najnowszą wersję", systemImage: "checkmark.circle.fill").foregroundColor(.green)
        case .available:
            Label("Dostępna nowa wersja", systemImage: "arrow.down.circle.fill").foregroundColor(.accentColor)
        case .downloading:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Pobieranie…") }
        case .installing:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Instalowanie i ponowne uruchamianie…") }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Pasek menu

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private let updater: Updater
    var onOpen: (() -> Void)?
    var onSettings: ((SettingsTab?) -> Void)?
    var hotKeyTitle: () -> String = { "" }

    init(updater: Updater) {
        self.updater = updater
    }

    func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let menu = NSMenu()
            menu.delegate = self
            it.menu = menu
            item = it
            refreshIcon()
        } else if !visible, let it = item {
            NSStatusBar.system.removeStatusItem(it)
            item = nil
        }
    }

    func refreshIcon() {
        guard let button = item?.button else { return }
        let name = updater.updateAvailable ? "square.grid.3x3.topleft.filled" : "square.grid.3x3.fill"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Launchpad Classic")
            ?? NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "Launchpad Classic")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.title = updater.updateAvailable ? " •" : ""
        button.toolTip = updater.updateAvailable ? "Launchpad Classic – dostępna aktualizacja" : "Launchpad Classic"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let open = NSMenuItem(title: "Otwórz Launchpad", action: #selector(openLaunchpad), keyEquivalent: "")
        open.target = self
        let hk = hotKeyTitle()
        if !hk.isEmpty { open.title = "Otwórz Launchpad   \(hk)" }
        menu.addItem(open)

        if updater.updateAvailable, let latest = updater.latest {
            menu.addItem(.separator())
            let upd = NSMenuItem(title: "Zainstaluj aktualizację (build \(latest.build))…",
                                 action: #selector(openUpdates), keyEquivalent: "")
            upd.target = self
            menu.addItem(upd)
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Ustawienia…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let check = NSMenuItem(title: "Sprawdź aktualizacje…", action: #selector(checkUpdates), keyEquivalent: "")
        check.target = self
        menu.addItem(check)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Zakończ Launchpad Classic", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func openLaunchpad() { onOpen?() }
    @objc private func openSettings() { onSettings?(nil) }
    @objc private func openUpdates() { onSettings?(.updates) }
    @objc private func checkUpdates() {
        onSettings?(.updates)
        Task { await updater.check(userInitiated: true) }
    }
}
