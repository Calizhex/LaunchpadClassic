import AppKit
import SwiftUI

// MARK: - Typy danych układu

struct Folder: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var apps: [String]          // identyfikatory aplikacji (ścieżki bundli)
}

enum Item: Equatable, Identifiable {
    case app(String)
    case folder(Folder)

    var id: String {
        switch self {
        case .app(let path): return "app:" + path
        case .folder(let f): return "folder:" + f.id
        }
    }

    var appID: String? {
        if case .app(let a) = self { return a }
        return nil
    }

    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }
}

struct StoredItem: Codable {
    var app: String?
    var folder: Folder?
}

struct StoredLayout: Codable {
    var version: Int
    var pages: [[StoredItem]]
}

struct Slot: Identifiable {
    let item: Item
    let index: Int
    var id: String { item.id }
}

enum CellContext: Equatable {
    case page(Int)
    case folder(String)
    case search
}

struct DragState {
    var item: Item
    var location: CGPoint
    var grabOffset: CGSize
    var folderID: String?       // gdy przeciągamy wewnątrz otwartego folderu
    var insertIndex: Int

    var iconPosition: CGPoint {
        CGPoint(x: location.x - grabOffset.width, y: location.y - grabOffset.height)
    }
}

private struct Press {
    let itemID: String
    var longFired: Bool
}

// MARK: - Geometria siatki (domyślnie 7 × 5, jak w klasycznym Launchpadzie)

struct GridMetrics {
    let size: CGSize
    let columns: Int
    let rows: Int
    let iconScale: CGFloat
    let fontSize: CGFloat

    init(size: CGSize, appearance: AppearanceSettings) {
        self.size = size
        self.columns = max(appearance.columns, 1)
        self.rows = max(appearance.rows, 1)
        self.iconScale = CGFloat(appearance.iconScale)
        self.fontSize = CGFloat(appearance.labelFontSize)
    }

    var perPage: Int { columns * rows }

    var gridRect: CGRect {
        let top = size.height * 0.13
        let bottom = size.height * 0.12
        let side = max(size.width * 0.09, 40)
        return CGRect(x: side, y: top,
                      width: max(size.width - side * 2, 1),
                      height: max(size.height - top - bottom, 1))
    }

    var cellSize: CGSize {
        CGSize(width: gridRect.width / CGFloat(columns),
               height: gridRect.height / CGFloat(rows))
    }

    var labelFont: CGFloat { fontSize }
    var labelHeight: CGFloat { ceil(labelFont * 1.3) }

    var iconSize: CGFloat {
        let auto = min(cellSize.width * 0.62, cellSize.height * 0.6, 136)
        let maxFit = min(cellSize.width * 0.92, cellSize.height - labelHeight - 10)
        return floor(max(16, min(auto * iconScale, maxFit)))
    }

    var labelSpacing: CGFloat { max(iconSize * 0.08, 5) }
    var iconCenterOffset: CGFloat { (labelSpacing + labelHeight) / 2 }

    func cellCenter(_ i: Int) -> CGPoint {
        let c = i % columns
        let r = i / columns
        return CGPoint(x: gridRect.minX + (CGFloat(c) + 0.5) * cellSize.width,
                       y: gridRect.minY + (CGFloat(r) + 0.5) * cellSize.height)
    }

    func iconCenter(_ i: Int) -> CGPoint {
        let c = cellCenter(i)
        return CGPoint(x: c.x, y: c.y - iconCenterOffset)
    }

    func cellIndex(at p: CGPoint) -> Int? {
        let r = gridRect
        guard r.contains(p) else { return nil }
        let col = min(max(Int((p.x - r.minX) / cellSize.width), 0), columns - 1)
        let row = min(max(Int((p.y - r.minY) / cellSize.height), 0), rows - 1)
        return row * columns + col
    }
}

struct FolderMetrics {
    let grid: GridMetrics
    let count: Int

    var cols: Int { min(5, max(3, count)) }
    var rowsTotal: Int { max(1, Int((Double(count) / Double(cols)).rounded(.up))) }
    var rows: Int { min(3, rowsTotal) }
    var perPage: Int { cols * rows }
    var pageCount: Int { max(1, Int((Double(count) / Double(perPage)).rounded(.up))) }
    var cell: CGSize { grid.cellSize }
    var padding: CGFloat { 26 }

    var panel: CGRect {
        let w = CGFloat(cols) * cell.width + padding * 2
        let h = CGFloat(rows) * cell.height + padding * 2
        return CGRect(x: (grid.size.width - w) / 2,
                      y: grid.size.height * 0.53 - h / 2,
                      width: w, height: h)
    }

    func cellCenter(_ i: Int) -> CGPoint {
        let c = i % cols
        let r = i / cols
        return CGPoint(x: panel.minX + padding + (CGFloat(c) + 0.5) * cell.width,
                       y: panel.minY + padding + (CGFloat(r) + 0.5) * cell.height)
    }

    func iconCenter(_ i: Int) -> CGPoint {
        let c = cellCenter(i)
        return CGPoint(x: c.x, y: c.y - grid.iconCenterOffset)
    }

    func cellIndex(at p: CGPoint) -> Int? {
        let inner = panel.insetBy(dx: padding, dy: padding)
        guard inner.contains(p) else { return nil }
        let col = min(max(Int((p.x - inner.minX) / cell.width), 0), cols - 1)
        let row = min(max(Int((p.y - inner.minY) / cell.height), 0), rows - 1)
        return row * cols + col
    }
}

// MARK: - Model

@MainActor
final class LaunchpadModel: ObservableObject {
    @Published var pages: [[Item]] = [[]]
    @Published private(set) var apps: [String: AppInfo] = [:]
    @Published var currentPage = 0
    @Published var pageOffset: CGFloat = 0
    @Published var visible = false
    @Published var editing = false
    @Published var openFolderID: String?
    @Published var folderPage = 0
    @Published var drag: DragState?
    @Published var folderTarget: String?
    @Published var pressedID: String?
    @Published var selectedIndex: Int?
    @Published var wallpaper: NSImage?
    @Published var toast: String?
    @Published var search = "" {
        didSet { searchChanged(from: oldValue) }
    }
    @Published var hotKey: HotKeyOption = Preferences.hotKey {
        didSet { Preferences.hotKey = hotKey; onSettingsChanged?() }
    }
    @Published var hotCorner: HotCorner = Preferences.hotCorner {
        didSet { Preferences.hotCorner = hotCorner; onSettingsChanged?() }
    }

    @Published var appearance: AppearanceSettings = Preferences.appearance {
        didSet {
            guard appearance != oldValue else { return }
            Preferences.appearance = appearance
            if appearance.columns * appearance.rows != oldValue.columns * oldValue.rows {
                normalize()
                save()
            }
        }
    }
    @Published var showMenuBarIcon: Bool = Preferences.showMenuBarIcon {
        didSet {
            Preferences.showMenuBarIcon = showMenuBarIcon
            if !showMenuBarIcon && !showDockIcon { showDockIcon = true }
            onSettingsChanged?()
        }
    }
    @Published var showDockIcon: Bool = Preferences.showDockIcon {
        didSet {
            Preferences.showDockIcon = showDockIcon
            if !showMenuBarIcon && !showDockIcon { showMenuBarIcon = true }
            onSettingsChanged?()
        }
    }

    var isRenamingFolder = false
    var openSettingsHandler: (() -> Void)?
    var viewSize = CGSize(width: 1440, height: 900)
    weak var searchField: NSTextField?
    var hideHandler: (() -> Void)?
    var onSettingsChanged: (() -> Void)?

    private var press: Press?
    private var longPressTimer: Timer?
    private var hoverTimer: Timer?
    private var hoverCandidate: String?
    private var edgeTimer: Timer?
    private var edgeDirection = 0
    private var dragSnapshot: [[Item]]?
    private var scrollLastDelta: CGFloat = 0
    private var scrollAccumulated: CGFloat = 0
    private var lastWheel = Date.distantPast
    private var toastWork: DispatchWorkItem?

    var metrics: GridMetrics { GridMetrics(size: viewSize, appearance: appearance) }
    var perPage: Int { max(appearance.columns * appearance.rows, 1) }

    init() {
        let loaded = load()
        let infos = AppScanner.scan()
        apps = Dictionary(infos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        if !loaded {
            if let legacy = LegacyLaunchpad.importLayout(bundleMap: bundleMap(infos)) {
                pages = legacy
            } else {
                pages = defaultLayout(infos)
            }
        }
        reconcile(infos)
        save()
    }

    // MARK: Pliki

    private var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("LaunchpadClassic", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var layoutURL: URL { supportDir.appendingPathComponent("layout.json") }

    @discardableResult
    private func load() -> Bool {
        guard let data = try? Data(contentsOf: layoutURL),
              let stored = try? JSONDecoder().decode(StoredLayout.self, from: data) else { return false }
        pages = stored.pages.map { page in
            page.compactMap { s -> Item? in
                if let f = s.folder { return .folder(f) }
                if let a = s.app { return .app(a) }
                return nil
            }
        }
        if pages.isEmpty { pages = [[]] }
        return true
    }

    func save() {
        let stored = StoredLayout(version: 1, pages: pages.map { page in
            page.map { item -> StoredItem in
                switch item {
                case .app(let a): return StoredItem(app: a, folder: nil)
                case .folder(let f): return StoredItem(app: nil, folder: f)
                }
            }
        })
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(stored) {
            try? data.write(to: layoutURL, options: .atomic)
        }
    }

    private func backupLayout() {
        let fm = FileManager.default
        let backup = supportDir.appendingPathComponent("layout.backup.json")
        try? fm.removeItem(at: backup)
        try? fm.copyItem(at: layoutURL, to: backup)
    }

    // MARK: Aplikacje i układ

    private func bundleMap(_ infos: [AppInfo]) -> [String: String] {
        var map: [String: String] = [:]
        for info in infos.sorted(by: { $0.id.count < $1.id.count }) {
            if let b = info.bundleID, map[b] == nil { map[b] = info.id }
        }
        return map
    }

    private func sortedByName(_ infos: [AppInfo]) -> [AppInfo] {
        infos.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func defaultLayout(_ infos: [AppInfo]) -> [[Item]] {
        let sorted = sortedByName(infos)
        let system = sorted.filter { $0.isSystem && !$0.isUtility }
        let utilities = sorted.filter { $0.isSystem && $0.isUtility }
        let others = sorted.filter { !$0.isSystem }
        var items: [Item] = system.map { .app($0.id) }
        if !utilities.isEmpty {
            items.append(.folder(Folder(id: UUID().uuidString, name: "Inne", apps: utilities.map { $0.id })))
        }
        items += others.map { .app($0.id) }
        var result: [[Item]] = []
        var i = 0
        while i < items.count {
            result.append(Array(items[i..<min(i + perPage, items.count)]))
            i += perPage
        }
        return result.isEmpty ? [[]] : result
    }

    /// Usuwa nieistniejące aplikacje, dopisuje nowe na końcu.
    @discardableResult
    private func reconcile(_ infos: [AppInfo]) -> Bool {
        let before = pages
        var placed = Set<String>()
        var newPages: [[Item]] = []
        for page in pages {
            var np: [Item] = []
            for item in page {
                switch item {
                case .app(let id):
                    if apps[id] != nil, placed.insert(id).inserted { np.append(item) }
                case .folder(var f):
                    f.apps = f.apps.filter { apps[$0] != nil && placed.insert($0).inserted }
                    if !f.apps.isEmpty { np.append(.folder(f)) }
                }
            }
            newPages.append(np)
        }
        let missing = sortedByName(infos.filter { !placed.contains($0.id) })
        for info in missing {
            if newPages.isEmpty { newPages.append([]) }
            if newPages[newPages.count - 1].count >= perPage { newPages.append([]) }
            newPages[newPages.count - 1].append(.app(info.id))
        }
        pages = newPages
        normalize()
        return pages != before
    }

    /// Przelewa nadmiar ikon na kolejne strony i usuwa puste strony.
    private func normalize() {
        var i = 0
        while i < pages.count {
            if pages[i].count > perPage {
                let overflow = Array(pages[i][perPage...])
                pages[i].removeSubrange(perPage...)
                if i + 1 < pages.count {
                    pages[i + 1].insert(contentsOf: overflow, at: 0)
                } else {
                    pages.append(overflow)
                }
            }
            i += 1
        }
        pages.removeAll { $0.isEmpty }
        if pages.isEmpty { pages = [[]] }
        currentPage = min(max(currentPage, 0), pages.count - 1)
    }

    func rescanAsync() {
        Task.detached(priority: .userInitiated) { [weak self] in
            let infos = AppScanner.scan()
            await self?.applyRescan(infos)
        }
    }

    private func applyRescan(_ infos: [AppInfo]) {
        guard drag == nil else { return }
        let newApps = Dictionary(infos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        guard newApps != apps else { return }
        apps = newApps
        if reconcile(infos) { save() }
    }

    func refreshAll() {
        IconCache.shared.purge()
        apps = [:]
        rescanAsync()
        showToast("Odświeżono listę aplikacji")
    }

    func resetLayout() {
        backupLayout()
        let infos = Array(apps.values)
        pages = defaultLayout(infos)
        reconcile(infos)
        currentPage = 0
        save()
        showToast("Ułożono alfabetycznie (kopia poprzedniego układu: layout.backup.json)")
    }

    func importLegacy() {
        let infos = Array(apps.values)
        guard let legacy = LegacyLaunchpad.importLayout(bundleMap: bundleMap(infos)) else {
            showToast("Nie znaleziono bazy starego Launchpada na tym Macu")
            return
        }
        backupLayout()
        pages = legacy
        reconcile(infos)
        currentPage = 0
        save()
        showToast("Zaimportowano układ ze starego Launchpada")
    }

    func showToast(_ text: String) {
        toastWork?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toast = text }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                withAnimation(.easeIn(duration: 0.3)) { self?.toast = nil }
            }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    // MARK: Zapytania dla widoków

    func title(of item: Item) -> String {
        switch item {
        case .app(let id): return apps[id]?.name ?? URL(fileURLWithPath: id).deletingPathExtension().lastPathComponent
        case .folder(let f): return f.name
        }
    }

    func slots(page p: Int) -> [Slot] {
        guard pages.indices.contains(p) else { return [] }
        var list: [Item?] = pages[p].map { Optional($0) }
        if let d = drag, d.folderID == nil, p == currentPage {
            list.insert(nil, at: min(max(d.insertIndex, 0), list.count))
        }
        var result: [Slot] = []
        for (i, it) in list.enumerated() where i < perPage {
            if let it { result.append(Slot(item: it, index: i)) }
        }
        return result
    }

    func locateFolder(_ id: String) -> (Int, Int)? {
        for (p, page) in pages.enumerated() {
            for (i, item) in page.enumerated() {
                if case .folder(let f) = item, f.id == id { return (p, i) }
            }
        }
        return nil
    }

    func folder(_ id: String) -> Folder? {
        guard let loc = locateFolder(id), case .folder(let f) = pages[loc.0][loc.1] else { return nil }
        return f
    }

    var openFolder: Folder? {
        guard let id = openFolderID else { return nil }
        return folder(id)
    }

    private func mutateFolder(_ id: String, _ body: (inout Folder) -> Void) {
        guard let loc = locateFolder(id), case .folder(var f) = pages[loc.0][loc.1] else { return }
        body(&f)
        pages[loc.0][loc.1] = .folder(f)
    }

    func folderMetrics(_ f: Folder) -> FolderMetrics {
        let extra = (drag?.folderID == f.id) ? 1 : 0
        return FolderMetrics(grid: metrics, count: f.apps.count + extra)
    }

    func folderSlots(_ f: Folder) -> [Slot] {
        var list: [Item?] = f.apps.map { Optional(Item.app($0)) }
        if let d = drag, d.folderID == f.id {
            list.insert(nil, at: min(max(d.insertIndex, 0), list.count))
        }
        let fm = folderMetrics(f)
        let start = folderPage * fm.perPage
        var result: [Slot] = []
        for (i, it) in list.enumerated() where i >= start && i < start + fm.perPage {
            if let it { result.append(Slot(item: it, index: i - start)) }
        }
        return result
    }

    var searchResults: [String] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var ordered: [String] = []
        for page in pages {
            for item in page {
                switch item {
                case .app(let a): ordered.append(a)
                case .folder(let f): ordered.append(contentsOf: f.apps)
                }
            }
        }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var prefix: [String] = []
        var contains: [String] = []
        for id in ordered {
            guard let name = apps[id]?.name else { continue }
            if let r = name.range(of: q, options: opts) {
                if r.lowerBound == name.startIndex { prefix.append(id) } else { contains.append(id) }
            }
        }
        return prefix + contains
    }

    private func searchChanged(from old: String) {
        guard search != old else { return }
        if !search.isEmpty {
            if editing { editing = false }
            if openFolderID != nil { closeFolder() }
        }
        selectedIndex = (search.isEmpty || searchResults.isEmpty) ? nil : 0
    }

    // MARK: Nawigacja

    func go(to page: Int) {
        let p = max(0, min(pages.count - 1, page))
        selectedIndex = nil
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
            currentPage = p
            pageOffset = 0
        }
    }

    func handleScroll(_ e: NSEvent) {
        guard visible, search.isEmpty else { return }
        let dx = e.scrollingDeltaX
        let dy = e.scrollingDeltaY
        let delta = abs(dx) >= abs(dy) ? dx : dy

        if let f = openFolder {
            let fm = folderMetrics(f)
            guard fm.pageCount > 1 else { return }
            if e.hasPreciseScrollingDeltas {
                if e.momentumPhase != [] { return }
                if e.phase == .began { scrollAccumulated = 0 }
                if e.phase == .changed { scrollAccumulated += delta }
                if e.phase == .ended {
                    if scrollAccumulated < -40 { withAnimation { folderPage = min(folderPage + 1, fm.pageCount - 1) } }
                    if scrollAccumulated > 40 { withAnimation { folderPage = max(folderPage - 1, 0) } }
                }
            } else if abs(delta) > 0.1, Date().timeIntervalSince(lastWheel) > 0.3 {
                lastWheel = Date()
                withAnimation {
                    folderPage = delta < 0 ? min(folderPage + 1, fm.pageCount - 1) : max(folderPage - 1, 0)
                }
            }
            return
        }

        if e.hasPreciseScrollingDeltas {
            if e.momentumPhase != [] { return }
            switch e.phase {
            case .began:
                scrollLastDelta = 0
                pageOffset = 0
            case .changed:
                let atStart = currentPage == 0 && pageOffset + delta > 0
                let atEnd = currentPage == pages.count - 1 && pageOffset + delta < 0
                pageOffset += (atStart || atEnd) ? delta * 0.3 : delta
                scrollLastDelta = delta
                selectedIndex = nil
            case .ended, .cancelled:
                let w = viewSize.width
                var target = currentPage
                if pageOffset < -w * 0.12 || scrollLastDelta < -14 { target += 1 }
                else if pageOffset > w * 0.12 || scrollLastDelta > 14 { target -= 1 }
                target = max(0, min(pages.count - 1, target))
                withAnimation(.spring(response: 0.4, dampingFraction: 0.92)) {
                    currentPage = target
                    pageOffset = 0
                }
            default:
                break
            }
        } else {
            guard abs(delta) > 0.1, Date().timeIntervalSince(lastWheel) > 0.3 else { return }
            lastWheel = Date()
            go(to: delta < 0 ? currentPage + 1 : currentPage - 1)
        }
    }

    func moveSelection(dx: Int, dy: Int) {
        guard drag == nil else { return }
        if !search.isEmpty {
            let n = min(searchResults.count, perPage)
            guard n > 0 else { return }
            let i = (selectedIndex ?? 0) + dx + dy * appearance.columns
            selectedIndex = max(0, min(n - 1, i))
            return
        }
        guard openFolderID == nil else { return }
        let count = pages[currentPage].count
        guard count > 0 else { return }
        guard var i = selectedIndex else { selectedIndex = 0; return }
        if dx != 0 {
            i += dx
            if i < 0 {
                if currentPage > 0 {
                    go(to: currentPage - 1)
                    selectedIndex = pages[currentPage].count - 1
                } else {
                    selectedIndex = 0
                }
                return
            }
            if i >= count {
                if currentPage < pages.count - 1 {
                    go(to: currentPage + 1)
                    selectedIndex = 0
                }
                return
            }
        } else {
            let j = i + dy * appearance.columns
            if j >= 0 && j < count { i = j }
        }
        selectedIndex = i
    }

    func activateSelection() {
        if !search.isEmpty {
            let r = searchResults
            let i = selectedIndex ?? 0
            if i < r.count { launch(r[i]) }
            return
        }
        guard openFolderID == nil, let i = selectedIndex, i < pages[currentPage].count else { return }
        activate(pages[currentPage][i])
    }

    func escape() {
        if drag != nil { cancelDrag(); return }
        if !search.isEmpty { search = ""; searchField?.stringValue = ""; return }
        if openFolderID != nil { closeFolder(); return }
        if editing { withAnimation { editing = false }; return }
        hideHandler?()
    }

    func backgroundClicked() {
        if openFolderID != nil { closeFolder(); return }
        if editing { withAnimation { editing = false }; return }
        hideHandler?()
    }

    func resetForHide() {
        if drag != nil { cancelDrag() }
        if openFolderID != nil {
            let id = openFolderID!
            openFolderID = nil
            dissolveIfNeeded(id)
        }
        longPressTimer?.invalidate()
        press = nil
        pressedID = nil
        editing = false
        isRenamingFolder = false
        search = ""
        searchField?.stringValue = ""
        selectedIndex = nil
        pageOffset = 0
    }

    // MARK: Uruchamianie i foldery

    func activate(_ item: Item) {
        switch item {
        case .app(let id):
            if editing { withAnimation { editing = false }; return }
            launch(id)
        case .folder(let f):
            openFolder(f.id)
        }
    }

    func launch(_ id: String) {
        guard let info = apps[id] else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: info.url, configuration: cfg) { _, _ in }
        hideHandler?()
    }

    func openFolder(_ id: String) {
        selectedIndex = nil
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            openFolderID = id
            folderPage = 0
        }
    }

    func closeFolder() {
        guard let id = openFolderID else { return }
        isRenamingFolder = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            openFolderID = nil
            dissolveIfNeeded(id)
        }
        if let f = searchField { f.window?.makeFirstResponder(f) }
        save()
    }

    /// Folder z jedną aplikacją zamienia się w tę aplikację, pusty znika.
    private func dissolveIfNeeded(_ id: String) {
        guard let loc = locateFolder(id), case .folder(var f) = pages[loc.0][loc.1] else { return }
        if f.apps.isEmpty {
            pages[loc.0].remove(at: loc.1)
        } else if f.apps.count == 1 {
            pages[loc.0][loc.1] = .app(f.apps[0])
        } else if f.name.trimmingCharacters(in: .whitespaces).isEmpty {
            f.name = suggestedFolderName(f.apps)
            pages[loc.0][loc.1] = .folder(f)
        }
        if drag == nil { normalize() }
    }

    func renameFolder(_ id: String, to name: String) {
        mutateFolder(id) { $0.name = name }
        save()
    }

    private func suggestedFolderName(_ ids: [String]) -> String {
        for id in ids {
            if let raw = apps[id]?.category, let name = AppScanner.categoryName(raw) { return name }
        }
        return "Folder"
    }

    // MARK: Naciśnięcia, długie przytrzymanie, przeciąganie

    func pressChanged(item: Item, context: CellContext, start: CGPoint, location: CGPoint, iconCenter: CGPoint) {
        guard drag == nil else { return }
        if press?.itemID != item.id {
            press = Press(itemID: item.id, longFired: false)
            pressedID = item.id
            longPressTimer?.invalidate()
            if context != .search {
                longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.longPressFired() }
                }
            }
        }
        let distance = hypot(location.x - start.x, location.y - start.y)
        if distance > 5, context != .search {
            longPressTimer?.invalidate()
            beginDrag(item: item, context: context, cursor: location, iconCenter: iconCenter)
        }
    }

    func pressEnded(item: Item, context: CellContext) {
        longPressTimer?.invalidate()
        let current = press
        press = nil
        pressedID = nil
        guard drag == nil, let p = current, p.itemID == item.id, !p.longFired else { return }
        if context == .search, case .app(let id) = item {
            launch(id)
        } else {
            activate(item)
        }
    }

    private func longPressFired() {
        guard press != nil, drag == nil else { return }
        press?.longFired = true
        pressedID = nil
        withAnimation(.easeOut(duration: 0.2)) { editing = true }
    }

    private func beginDrag(item: Item, context: CellContext, cursor: CGPoint, iconCenter: CGPoint) {
        dragSnapshot = pages
        var state = DragState(item: item, location: cursor,
                              grabOffset: CGSize(width: cursor.x - iconCenter.x, height: cursor.y - iconCenter.y),
                              folderID: nil, insertIndex: 0)
        switch context {
        case .page(let p):
            guard pages.indices.contains(p),
                  let i = pages[p].firstIndex(where: { $0.id == item.id }) else { return }
            pages[p].remove(at: i)
            state.insertIndex = i
        case .folder(let fid):
            guard case .app(let appID) = item, let f = folder(fid),
                  let i = f.apps.firstIndex(of: appID) else { return }
            mutateFolder(fid) { $0.apps.remove(at: i) }
            state.folderID = fid
            state.insertIndex = i
        case .search:
            return
        }
        selectedIndex = nil
        pressedID = nil
        if !editing { withAnimation(.easeOut(duration: 0.2)) { editing = true } }
        drag = state
    }

    func updateDrag(to location: CGPoint) {
        guard var d = drag else { return }
        d.location = location
        let iconPos = d.iconPosition

        // Wewnątrz otwartego folderu
        if let fid = d.folderID, let f = folder(fid) {
            let fm = FolderMetrics(grid: metrics, count: f.apps.count + 1)
            if fm.panel.insetBy(dx: -24, dy: -24).contains(location) {
                if let k = fm.cellIndex(at: iconPos) {
                    d.insertIndex = min(folderPage * fm.perPage + k, f.apps.count)
                }
                drag = d
                return
            }
            // Wyciągnięcie ikony poza folder: zamknij folder, kontynuuj na stronie
            d.folderID = nil
            d.insertIndex = pages[currentPage].count
            drag = d
            isRenamingFolder = false
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                openFolderID = nil
                dissolveIfNeeded(fid)
            }
        } else {
            drag = d
        }

        handleEdge(location)

        let m = metrics
        guard let k = m.cellIndex(at: iconPos) else { clearHover(); return }
        let slots = self.slots(page: currentPage)
        if let s = slots.first(where: { $0.index == k }) {
            let c = m.iconCenter(k)
            let near = hypot(iconPos.x - c.x, iconPos.y - c.y) < m.iconSize * 0.3
            if near, d.item.appID != nil {
                setHover(s.item.id)
                return
            }
            clearHover()
            drag?.insertIndex = min(k, pages[currentPage].count)
        } else {
            clearHover()
            let placeholder = min(max(d.insertIndex, 0), pages[currentPage].count)
            if k != placeholder { drag?.insertIndex = pages[currentPage].count }
        }
    }

    private func setHover(_ id: String) {
        guard hoverCandidate != id else { return }
        hoverTimer?.invalidate()
        hoverCandidate = id
        folderTarget = nil
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.drag != nil, self.hoverCandidate == id else { return }
                self.folderTarget = id
            }
        }
    }

    private func clearHover() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        hoverCandidate = nil
        if folderTarget != nil { folderTarget = nil }
    }

    private func handleEdge(_ location: CGPoint) {
        let w = viewSize.width
        let dir = location.x < 36 ? -1 : (location.x > w - 36 ? 1 : 0)
        if dir == 0 {
            edgeTimer?.invalidate()
            edgeTimer = nil
            edgeDirection = 0
            return
        }
        if dir == edgeDirection, edgeTimer != nil { return }
        edgeDirection = dir
        edgeTimer?.invalidate()
        edgeTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.edgeFlip() }
        }
    }

    private func edgeFlip() {
        guard drag != nil, drag?.folderID == nil else { return }
        if edgeDirection < 0 {
            guard currentPage > 0 else { return }
            go(to: currentPage - 1)
        } else if edgeDirection > 0 {
            if currentPage == pages.count - 1 {
                if pages[currentPage].isEmpty { return }
                pages.append([])
            }
            go(to: currentPage + 1)
        }
        drag?.insertIndex = pages[currentPage].count
        clearHover()
    }

    private func stopDragTimers() {
        edgeTimer?.invalidate(); edgeTimer = nil; edgeDirection = 0
        hoverTimer?.invalidate(); hoverTimer = nil; hoverCandidate = nil
    }

    func endDrag() {
        guard let d = drag else { return }
        stopDragTimers()
        withAnimation(.easeInOut(duration: 0.22)) {
            if let fid = d.folderID, case .app(let a) = d.item {
                mutateFolder(fid) { $0.apps.insert(a, at: min(max(d.insertIndex, 0), $0.apps.count)) }
            } else if let t = folderTarget, case .app(let a) = d.item,
                      let idx = pages[currentPage].firstIndex(where: { $0.id == t }) {
                switch pages[currentPage][idx] {
                case .app(let other):
                    let f = Folder(id: UUID().uuidString, name: suggestedFolderName([other, a]), apps: [other, a])
                    pages[currentPage][idx] = .folder(f)
                case .folder(var f):
                    f.apps.append(a)
                    pages[currentPage][idx] = .folder(f)
                }
            } else {
                let i = min(max(d.insertIndex, 0), pages[currentPage].count)
                pages[currentPage].insert(d.item, at: i)
            }
            drag = nil
            folderTarget = nil
            press = nil
            pressedID = nil
            normalize()
        }
        dragSnapshot = nil
        save()
    }

    func cancelDrag() {
        guard drag != nil else { return }
        stopDragTimers()
        withAnimation(.easeInOut(duration: 0.22)) {
            if let snap = dragSnapshot { pages = snap }
            drag = nil
            folderTarget = nil
            press = nil
            pressedID = nil
            normalize()
        }
        dragSnapshot = nil
    }
}
