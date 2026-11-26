import AppKit
import SwiftUI

func wiggleAngle(_ id: String, time: Double?) -> Double {
    guard let t = time else { return 0 }
    var h: UInt32 = 2166136261
    for b in id.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
    let phase = Double(h % 1000) / 1000 * .pi * 2
    let speed = 4.0 + Double(h % 7) / 10
    return sin(t * 2 * .pi * speed + phase) * 1.7
}

// MARK: - Główny widok

struct RootView: View {
    @ObservedObject var model: LaunchpadModel

    var body: some View {
        GeometryReader { geo in
            let m = GridMetrics(size: geo.size, appearance: model.appearance)
            ZStack(alignment: .topLeading) {
                BackgroundView(image: model.wallpaper)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(model.visible ? 1 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { model.backgroundClicked() }
                    .contextMenu { settingsMenu }

                MainContent(model: model, m: m)
                    .blur(radius: model.openFolderID == nil ? 0 : 22)
                    .opacity(model.visible ? 1 : 0)
                    .scaleEffect(model.visible ? 1 : 1.07)
                    .allowsHitTesting(model.openFolderID == nil)

                if let folder = model.openFolder {
                    FolderOverlay(model: model, folder: folder, m: m)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .zIndex(2)
                }

                if let d = model.drag {
                    DraggedIcon(model: model, item: d.item, size: m.iconSize)
                        .position(d.iconPosition)
                        .allowsHitTesting(false)
                        .zIndex(3)
                }

                if let toast = model.toast {
                    Text(toast)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .position(x: geo.size.width / 2, y: geo.size.height - 100)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .zIndex(4)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .coordinateSpace(name: "root")
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var settingsMenu: some View {
        Button("Ustawienia…") { model.openSettingsHandler?() }
        Divider()
        Menu("Układ siatki") {
            ForEach(model.allPresets) { preset in
                Toggle("\(preset.name)  (\(preset.appearance.columns)×\(preset.appearance.rows))", isOn: Binding(
                    get: { model.appearance == preset.appearance },
                    set: { if $0 { model.applyPreset(preset) } }))
            }
            Divider()
            Button("Uzupełnij puste miejsca") { model.fillGaps() }
        }
        Menu("Skrót klawiszowy") {
            ForEach(HotKeyOption.allCases) { option in
                Toggle(option.title, isOn: Binding(
                    get: { model.hotKey == option },
                    set: { if $0 { model.hotKey = option } }))
            }
        }
        Menu("Gorący narożnik") {
            ForEach(HotCorner.allCases) { corner in
                Toggle(corner.title, isOn: Binding(
                    get: { model.hotCorner == corner },
                    set: { if $0 { model.hotCorner = corner } }))
            }
        }
        Toggle("Otwieraj przy logowaniu", isOn: Binding(
            get: { LoginItem.isEnabled },
            set: { LoginItem.set($0) }))
        Divider()
        Button("Odśwież listę aplikacji") { model.refreshAll() }
        Button("Importuj układ ze starego Launchpada") { model.importLegacy() }
        Button("Ułóż alfabetycznie (resetuj układ)") { model.resetLayout() }
        Divider()
        Button("Zakończ Launchpad Classic") { NSApp.terminate(nil) }
    }
}

struct MainContent: View {
    @ObservedObject var model: LaunchpadModel
    let m: GridMetrics

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.search.isEmpty {
                PagesView(model: model, m: m)
                if model.pages.count > 1 {
                    PageDots(count: model.pages.count, current: model.currentPage) { model.go(to: $0) }
                        .position(x: m.size.width / 2, y: m.size.height * 0.935)
                }
            } else {
                SearchResultsView(model: model, m: m)
            }
            SearchBar(model: model)
                .frame(width: 240, height: 28)
                .position(x: m.size.width / 2, y: max(m.size.height * 0.055, 36))
        }
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
    }
}

// MARK: - Strony

struct PagesView: View {
    @ObservedObject var model: LaunchpadModel
    let m: GridMetrics

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !model.editing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                ForEach(0..<model.pages.count, id: \.self) { p in
                    PageView(model: model, page: p, m: m, time: model.editing ? t : nil)
                        .offset(x: CGFloat(p - model.currentPage) * m.size.width + model.pageOffset)
                }
            }
            .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
        }
    }
}

struct PageView: View {
    @ObservedObject var model: LaunchpadModel
    let page: Int
    let m: GridMetrics
    let time: Double?

    var body: some View {
        let slots = model.slots(page: page)
        ZStack(alignment: .topLeading) {
            ForEach(slots) { slot in
                ItemCell(model: model, item: slot.item, context: .page(page), index: slot.index,
                         m: m, iconCenter: m.iconCenter(slot.index),
                         angle: wiggleAngle(slot.item.id, time: time))
                    .position(m.cellCenter(slot.index))
            }
        }
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.22), value: slots.map { $0.id })
    }
}

struct SearchResultsView: View {
    @ObservedObject var model: LaunchpadModel
    let m: GridMetrics

    var body: some View {
        let results = Array(model.searchResults.prefix(m.perPage))
        ZStack(alignment: .topLeading) {
            if results.isEmpty {
                Text("Brak wyników")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .position(x: m.size.width / 2, y: m.size.height * 0.45)
            }
            ForEach(Array(results.enumerated()), id: \.element) { i, id in
                ItemCell(model: model, item: .app(id), context: .search, index: i,
                         m: m, iconCenter: m.iconCenter(i))
                    .position(m.cellCenter(i))
            }
        }
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
    }
}

// MARK: - Ikona z podpisem

struct ItemCell: View {
    @ObservedObject var model: LaunchpadModel
    let item: Item
    let context: CellContext
    let index: Int
    let m: GridMetrics
    let iconCenter: CGPoint
    var angle: Double = 0

    var body: some View {
        let isTarget = model.folderTarget == item.id
        let pressed = model.pressedID == item.id && model.drag == nil
        VStack(spacing: m.labelSpacing) {
            ZStack {
                if isTarget && !item.isFolder {
                    RoundedRectangle(cornerRadius: m.iconSize * 0.26, style: .continuous)
                        .fill(Color.white.opacity(0.28))
                        .frame(width: m.iconSize * 1.2, height: m.iconSize * 1.2)
                }
                ItemIcon(model: model, item: item, size: m.iconSize)
                    .scaleEffect(isTarget && item.isFolder ? 1.12 : 1)
                    .brightness(pressed ? -0.35 : 0)
            }
            .frame(width: m.iconSize, height: m.iconSize)

            Text(model.title(of: item))
                .font(.system(size: m.labelFont))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .shadow(color: .black.opacity(0.55), radius: 1.5, x: 0, y: 1)
                .frame(width: m.cellSize.width - 6, height: m.labelHeight)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.2 : 0))
                .frame(width: m.iconSize + 30, height: m.iconSize + m.labelSpacing + m.labelHeight + 22)
        )
        .contentShape(Rectangle())
        .rotationEffect(.degrees(angle))
        .animation(.easeOut(duration: 0.15), value: isTarget)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("root"))
                .onChanged { v in
                    model.pressChanged(item: item, context: context, start: v.startLocation,
                                       location: v.location, iconCenter: iconCenter)
                }
                .onEnded { _ in
                    model.pressEnded(item: item, context: context)
                }
        )
        .frame(width: m.cellSize.width, height: m.cellSize.height)
    }

    private var isSelected: Bool {
        switch context {
        case .page(let p): return p == model.currentPage && model.selectedIndex == index && model.openFolderID == nil
        case .search: return model.selectedIndex == index
        case .folder: return false
        }
    }
}

struct ItemIcon: View {
    @ObservedObject var model: LaunchpadModel
    let item: Item
    let size: CGFloat

    var body: some View {
        switch item {
        case .app(let id):
            Image(nsImage: IconCache.shared.icon(for: id))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        case .folder(let f):
            FolderIcon(folder: f, size: size)
        }
    }
}

struct FolderIcon: View {
    let folder: Folder
    let size: CGFloat

    var body: some View {
        let box = size * 0.86
        let gap = box * 0.075
        let mini = (box - gap * 4) / 3
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: box * 0.24, style: .continuous)
                .fill(Color.white.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: box * 0.24, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                )
            ForEach(Array(folder.apps.prefix(9).enumerated()), id: \.offset) { i, id in
                Image(nsImage: IconCache.shared.icon(for: id))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: mini, height: mini)
                    .offset(x: gap + CGFloat(i % 3) * (mini + gap),
                            y: gap + CGFloat(i / 3) * (mini + gap))
            }
        }
        .frame(width: box, height: box)
        .frame(width: size, height: size)
    }
}

struct DraggedIcon: View {
    @ObservedObject var model: LaunchpadModel
    let item: Item
    let size: CGFloat

    var body: some View {
        ItemIcon(model: model, item: item, size: size)
            .scaleEffect(1.08)
            .opacity(0.92)
            .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 6)
    }
}

// MARK: - Folder otwarty

struct FolderOverlay: View {
    @ObservedObject var model: LaunchpadModel
    let folder: Folder
    let m: GridMetrics
    @FocusState private var titleFocused: Bool

    var body: some View {
        let fm = model.folderMetrics(folder)
        let slots = model.folderSlots(folder)
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.12)
                .contentShape(Rectangle())
                .onTapGesture { model.closeFolder() }

            shape
                .fill(Color.white.opacity(0.12))
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                .frame(width: fm.panel.width, height: fm.panel.height)
                .position(x: fm.panel.midX, y: fm.panel.midY)
                .onTapGesture {
                    if model.editing { withAnimation { model.editing = false } }
                }

            TextField("", text: Binding(
                get: { model.folder(folder.id)?.name ?? folder.name },
                set: { model.renameFolder(folder.id, to: $0) }))
                .textFieldStyle(.plain)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .focused($titleFocused)
                .frame(width: max(fm.panel.width, 360))
                .position(x: fm.panel.midX, y: fm.panel.minY - 42)
                .onChange(of: titleFocused) { _, focused in
                    model.isRenamingFolder = focused
                }

            TimelineView(.animation(minimumInterval: nil, paused: !model.editing)) { ctx in
                let t: Double? = model.editing ? ctx.date.timeIntervalSinceReferenceDate : nil
                ZStack(alignment: .topLeading) {
                    ForEach(slots) { slot in
                        ItemCell(model: model, item: slot.item, context: .folder(folder.id), index: slot.index,
                                 m: m, iconCenter: fm.iconCenter(slot.index),
                                 angle: wiggleAngle(slot.item.id, time: t))
                            .position(fm.cellCenter(slot.index))
                    }
                }
                .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
                .animation(.easeInOut(duration: 0.22), value: slots.map { $0.id })
            }

            if fm.pageCount > 1 {
                PageDots(count: fm.pageCount, current: model.folderPage) { p in
                    withAnimation { model.folderPage = p }
                }
                .position(x: fm.panel.midX, y: fm.panel.maxY + 22)
            }
        }
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
    }
}

// MARK: - Elementy pomocnicze

struct PageDots: View {
    let count: Int
    let current: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(i == current ? 0.95 : 0.35))
                    .frame(width: 7, height: 7)
                    .padding(5)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(i) }
            }
        }
    }
}

struct SearchBar: View {
    @ObservedObject var model: LaunchpadModel

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            SearchField(model: model)
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(shape.fill(Color.white.opacity(0.16)))
        .overlay(shape.stroke(Color.white.opacity(0.22), lineWidth: 0.5))
    }
}

struct SearchField: NSViewRepresentable {
    @ObservedObject var model: LaunchpadModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: "")
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = .white
        field.font = .systemFont(ofSize: 13)
        field.placeholderAttributedString = NSAttributedString(string: "Szukaj", attributes: [
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
            .font: NSFont.systemFont(ofSize: 13),
        ])
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        model.searchField = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != model.search { field.stringValue = model.search }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: LaunchpadModel
        init(model: LaunchpadModel) { self.model = model }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            model.search = field.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            (obj.userInfo?["NSFieldEditor"] as? NSTextView)?.insertionPointColor = .white
        }
    }
}

struct BackgroundView: View {
    let image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Color.clear.overlay(
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fill)
                )
                .clipped()
            } else {
                VisualEffectBackground()
            }
            Color.black.opacity(0.22)
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .fullScreenUI
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
