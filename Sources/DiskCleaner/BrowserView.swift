import SwiftUI

enum BrowserMode: String, CaseIterable, Identifiable {
    case list = "Lista", map = "Mapa"
    var id: String { rawValue }
    var icon: String { self == .list ? "list.bullet" : "square.grid.2x2.fill" }
}

struct BrowserView: View {
    @EnvironmentObject var model: AppModel
    @State private var mode: BrowserMode = .map
    @State private var sortOrder = [KeyPathComparator(\FileNode.size, order: .reverse)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let cur = model.current {
                if cur.children.isEmpty {
                    ContentUnavailableView(cur.unreadable ? "Sin permisos de lectura" : "Carpeta vacía",
                                           systemImage: cur.unreadable ? "lock.fill" : "folder")
                } else if mode == .list {
                    listView(cur)
                } else {
                    TreemapView(folder: cur).id(model.revision)
                }
            }
            Divider()
            footer
        }
    }

    // MARK: Cabecera con ruta

    private var header: some View {
        HStack(spacing: 6) {
            Button { model.goUp() } label: { Image(systemName: "chevron.up") }
                .disabled(model.current?.parent == nil)
                .help("Carpeta superior (⌘↑)")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(model.breadcrumb().enumerated()), id: \.element.id) { i, n in
                        if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                        Button(n.name) { model.navigate(to: n) }
                            .buttonStyle(.plain)
                            .fontWeight(n === model.current ? .semibold : .regular)
                            .foregroundStyle(n === model.current ? .primary : .secondary)
                    }
                }
            }
            Spacer(minLength: 8)
            if let cur = model.current {
                Text("\(Fmt.size(cur.size)) · \(cur.itemCount.formatted()) elementos")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Picker("Vista", selection: $mode) {
                ForEach(BrowserMode.allCases) { m in Image(systemName: m.icon).tag(m) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 90)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // MARK: Lista

    private func listView(_ cur: FileNode) -> some View {
        let rows = cur.children.sorted(using: sortOrder)
        let total = max(cur.size, 1)
        return Table(rows, selection: $model.selection, sortOrder: $sortOrder) {
            TableColumn("Nombre", value: \.name) { n in
                HStack(spacing: 6) {
                    Image(systemName: n.symbol).foregroundStyle(n.tint).frame(width: 18)
                    Text(n.name).lineLimit(1)
                    if n.unreadable { Image(systemName: "lock.fill").foregroundStyle(.orange).help("Sin permisos de lectura") }
                }
            }
            TableColumn("Tamaño", value: \.size) { n in
                Text(Fmt.size(n.size)).monospacedDigit()
            }
            .width(min: 70, ideal: 80, max: 110)
            TableColumn("% de la carpeta") { n in
                let f = Double(n.size) / Double(total)
                HStack(spacing: 6) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        GeometryReader { g in Capsule().fill(n.tint).frame(width: max(2, g.size.width * f)) }
                    }
                    .frame(height: 6)
                    Text(f.formatted(.percent.precision(.fractionLength(f < 0.1 ? 1 : 0))))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
            .width(min: 110, ideal: 140)
            TableColumn("Elementos", value: \.itemCount) { n in
                Text(n.isDirectory ? n.itemCount.formatted() : "—").foregroundStyle(.secondary).monospacedDigit()
            }
            .width(min: 60, ideal: 70, max: 100)
            TableColumn("Modificado", value: \.modifiedSort) { n in
                Text(n.modified > 0 ? Fmt.date.string(from: Date(timeIntervalSince1970: n.modified)) : "—")
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 100, max: 130)
        }
        .id(model.revision)
        .contextMenu(forSelectionType: FileNode.ID.self) { ids in
            let nodes = nodes(for: ids)
            if let n = nodes.first, nodes.count == 1, n.isDirectory {
                Button("Abrir carpeta") { model.navigate(to: n) }
            }
            Button("Mostrar en Finder") { model.revealInFinder(nodes) }
            Divider()
            Button("Eliminar…", role: .destructive) { model.requestDelete(nodes) }
        } primaryAction: { ids in
            let nodes = nodes(for: ids)
            if let n = nodes.first, nodes.count == 1 {
                if n.isDirectory { model.navigate(to: n) } else { model.revealInFinder([n]) }
            }
        }
        .onDeleteCommand { model.requestDelete(selectedNodes) }
    }

    private func nodes(for ids: Set<FileNode.ID>) -> [FileNode] {
        (model.current?.children ?? []).filter { ids.contains($0.id) }
    }

    private var selectedNodes: [FileNode] { nodes(for: model.selection) }

    // MARK: Pie

    private var footer: some View {
        let sel = selectedNodes
        let size = sel.reduce(0) { $0 + $1.size }
        return HStack(spacing: 10) {
            if sel.isEmpty {
                Text("Selecciona elementos (⌘ o ⇧ para varios). Doble clic para abrir carpetas.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("\(sel.count) seleccionado\(sel.count == 1 ? "" : "s") · \(Fmt.size(size))")
                    .font(.callout).fontWeight(.medium)
            }
            Spacer()
            Button("Mostrar en Finder") { model.revealInFinder(sel) }.disabled(sel.isEmpty)
            Button("Eliminar…", role: .destructive) { model.requestDelete(sel) }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(sel.isEmpty || model.isBusy)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

// MARK: - Mapa (treemap)

struct TreemapView: View {
    @EnvironmentObject var model: AppModel
    let folder: FileNode
    @State private var hover: FileNode?

    var body: some View {
        GeometryReader { geo in
            let tiles = Treemap.layout(folder.children, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .bottomLeading) {
                Canvas { ctx, _ in
                    for t in tiles {
                        let r = t.rect.insetBy(dx: 0.5, dy: 0.5)
                        guard r.width > 1, r.height > 1 else { continue }
                        let selected = model.selection.contains(t.node.id)
                        let shade = Double(abs(t.node.name.hashValue) % 100) / 100 * 0.18
                        let base = t.node.kind == .other
                            ? Color(white: 0.42 + shade)
                            : Color(hue: t.node.hue, saturation: 0.55, brightness: 0.52 + shade)
                        ctx.fill(Path(r), with: .color(base))
                        ctx.stroke(Path(r), with: .color(.black.opacity(0.25)), lineWidth: 1)
                        if r.width > 56 && r.height > 30 {
                            var c = ctx
                            c.clip(to: Path(r))
                            c.draw(Text(t.node.name).font(.caption.weight(.semibold)).foregroundStyle(.white),
                                   at: CGPoint(x: r.minX + 5, y: r.minY + 4), anchor: .topLeading)
                            c.draw(Text(Fmt.size(t.node.size)).font(.caption2).foregroundStyle(.white.opacity(0.8)),
                                   at: CGPoint(x: r.minX + 5, y: r.minY + 20), anchor: .topLeading)
                        }
                        if selected {
                            ctx.stroke(Path(r.insetBy(dx: 1.5, dy: 1.5)), with: .color(.white), lineWidth: 3)
                            ctx.stroke(Path(r), with: .color(.accentColor), lineWidth: 2)
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture(count: 2).onEnded { v in
                    if let n = hit(tiles, v.location), n.isDirectory { model.navigate(to: n) }
                })
                .simultaneousGesture(SpatialTapGesture().onEnded { v in
                    click(hit(tiles, v.location))
                })
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p): hover = hit(tiles, p)
                    case .ended: hover = nil
                    }
                }

                if let h = hover {
                    let pct = Double(h.size) / Double(max(folder.size, 1))
                    Text("\(h.name) · \(Fmt.size(h.size)) · \(pct.formatted(.percent.precision(.fractionLength(1))))")
                        .font(.callout)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func hit(_ tiles: [TreemapTile], _ p: CGPoint) -> FileNode? {
        tiles.first { $0.rect.contains(p) }?.node
    }

    private func click(_ node: FileNode?) {
        guard let node else { model.selection = []; return }
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) || flags.contains(.shift) {
            if model.selection.contains(node.id) { model.selection.remove(node.id) } else { model.selection.insert(node.id) }
        } else {
            model.selection = [node.id]
        }
    }
}
