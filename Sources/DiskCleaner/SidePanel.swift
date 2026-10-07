import SwiftUI

enum SideTab: String, CaseIterable, Identifiable {
    case suggestions = "Sugerencias", folders = "Carpetas", files = "Ficheros"
    var id: String { rawValue }
}

struct ResultItem: Identifiable {
    let node: FileNode
    var title: String?
    var detail: String?
    var risk: Risk?
    var id: ObjectIdentifier { node.id }
}

struct SidePanel: View {
    @EnvironmentObject var model: AppModel
    @State private var tab: SideTab = .suggestions

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(SideTab.allCases) { t in Text(t.rawValue).tag(t) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(10)
            Divider()
            switch tab {
            case .suggestions: SuggestionsPanel()
            case .folders: FoldersPanel()
            case .files: FilesPanel()
            }
        }
    }
}

struct FoldersPanel: View {
    @EnvironmentObject var model: AppModel
    @State private var selection = Set<ObjectIdentifier>()
    @AppStorage("onlyLeafFolders") private var onlyLeaf = true

    var body: some View {
        let list = onlyLeaf ? model.analysis.leafFolders : model.analysis.topFolders
        ResultsList(items: list.map { ResultItem(node: $0) }, selection: $selection) {
            Toggle("Ocultar carpetas contenedoras", isOn: $onlyLeaf)
                .toggleStyle(.checkbox)
                .help("Muestra solo las carpetas donde realmente está el peso, sin las que solo contienen a otra mayor.")
                .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }
}

struct FilesPanel: View {
    @EnvironmentObject var model: AppModel
    @State private var selection = Set<ObjectIdentifier>()

    var body: some View {
        ResultsList(items: model.analysis.topFiles.map { ResultItem(node: $0) }, selection: $selection) {
            Text("Los 200 ficheros más grandes del disco")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }
}

struct SuggestionsPanel: View {
    @EnvironmentObject var model: AppModel
    @State private var selection = Set<ObjectIdentifier>()

    var body: some View {
        let items = model.analysis.suggestions.map {
            ResultItem(node: $0.node, title: $0.title, detail: $0.reason, risk: $0.risk)
        }
        ResultsList(items: items, selection: $selection) {
            VStack(alignment: .leading, spacing: 6) {
                if items.isEmpty {
                    Text("No se han encontrado candidatos claros a eliminar.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("Recuperable: **\(Fmt.size(model.analysis.reclaimable))** (seguro: \(Fmt.size(model.analysis.safeReclaimable)))")
                        .font(.callout)
                    HStack {
                        Button("Seleccionar seguras") {
                            selection = Set(model.analysis.suggestions.filter { $0.risk == .safe }.map { $0.node.id })
                        }
                        Button("Ninguna") { selection = [] }.disabled(selection.isEmpty)
                    }
                    .controlSize(.small)
                    Text("Son sugerencias heurísticas: revisa cada elemento antes de borrarlo.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }
}

struct ResultsList<Header: View>: View {
    @EnvironmentObject var model: AppModel
    let items: [ResultItem]
    @Binding var selection: Set<ObjectIdentifier>
    @ViewBuilder var header: () -> Header

    var body: some View {
        VStack(spacing: 0) {
            header()
            Divider()
            List(items, selection: $selection) { item in
                row(item)
            }
            .listStyle(.inset)
            .contextMenu(forSelectionType: ObjectIdentifier.self) { ids in
                let nodes = nodes(for: ids)
                if nodes.count == 1, let n = nodes.first {
                    Button("Ver en el explorador") { model.show(n) }
                }
                Button("Mostrar en Finder") { model.revealInFinder(nodes) }
                Divider()
                Button("Eliminar…", role: .destructive) { model.requestDelete(nodes) }
            } primaryAction: { ids in
                if let n = nodes(for: ids).first { model.show(n) }
            }
            .onDeleteCommand { model.requestDelete(nodes(for: selection)) }
            Divider()
            footer
        }
    }

    private func nodes(for ids: Set<ObjectIdentifier>) -> [FileNode] {
        items.filter { ids.contains($0.id) }.map { $0.node }
    }

    private func row(_ item: ResultItem) -> some View {
        let n = item.node
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: n.symbol).foregroundStyle(n.tint).frame(width: 20).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title ?? n.name).fontWeight(.medium).lineLimit(1)
                    if let r = item.risk { RiskBadge(risk: r) }
                }
                if let d = item.detail {
                    Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                Text(n.displayPath).font(.caption2).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Text(Fmt.size(n.size)).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .help(n.displayPath)
    }

    private var footer: some View {
        let sel = nodes(for: selection)
        let size = sel.reduce(0) { $0 + $1.size }
        return HStack(spacing: 8) {
            Text(sel.isEmpty ? "Sin selección" : "\(sel.count) · \(Fmt.size(size))")
                .font(.callout).foregroundStyle(sel.isEmpty ? .secondary : .primary)
            Spacer()
            Button("Mostrar") { model.revealInFinder(sel) }.disabled(sel.isEmpty)
            Button("Eliminar…", role: .destructive) { model.requestDelete(sel) }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(sel.isEmpty || model.isBusy)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

struct RiskBadge: View {
    let risk: Risk

    var body: some View {
        Text(risk.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch risk {
        case .safe: return .green
        case .review: return .orange
        case .caution: return .red
        }
    }
}
