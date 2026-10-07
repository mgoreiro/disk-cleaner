import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            VolumeBar()
            Divider()
            if model.unreadableCount > 0 && model.root != nil { PermissionsBanner() }
            if let msg = model.message { MessageBanner(text: msg) }
            mainContent
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Disco", selection: $model.selectedVolumeID) {
                    ForEach(model.volumes) { v in
                        Text(v.isCustom ? v.name : "\(v.name) · \(Fmt.size(v.total))").tag(v.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 220)
                .disabled(model.isBusy)
            }
            ToolbarItem {
                Button { model.chooseFolder() } label: { Label("Otra carpeta…", systemImage: "folder.badge.plus") }
                    .disabled(model.isBusy)
                    .help("Analizar una carpeta concreta")
            }
            ToolbarItem {
                if model.phase == .scanning {
                    Button { model.cancelScan() } label: { Label("Cancelar", systemImage: "xmark.circle") }
                } else {
                    Button { model.startScan() } label: {
                        Label(model.root == nil ? "Analizar" : "Volver a analizar", systemImage: "magnifyingglass")
                    }
                    .disabled(model.isBusy || model.selectedVolume == nil)
                }
            }
        }
        .confirmationDialog(deleteTitle, isPresented: $model.showDeleteDialog, titleVisibility: .visible) {
            Button("Mover a la papelera") { model.performDelete(permanent: false) }
            Button("Eliminar definitivamente", role: .destructive) { model.performDelete(permanent: true) }
            Button("Cancelar", role: .cancel) { model.pendingDelete = [] }
        } message: {
            Text(deleteMessage)
        }
    }

    private var deleteTitle: String {
        let n = model.pendingDelete.count
        let size = model.pendingDelete.reduce(0) { $0 + $1.size }
        return "¿Eliminar \(n) elemento\(n == 1 ? "" : "s") (\(Fmt.size(size)))?"
    }

    private var deleteMessage: String {
        let names = model.pendingDelete.prefix(5).map { "• " + $0.name }.joined(separator: "\n")
        let more = model.pendingDelete.count > 5 ? "\n… y \(model.pendingDelete.count - 5) más" : ""
        return names + more + "\n\nLa papelera permite recuperarlos, pero el espacio no se libera hasta vaciarla."
    }

    @ViewBuilder
    private var mainContent: some View {
        switch model.phase {
        case .scanning:
            ScanningView()
        case .analyzing where model.root == nil:
            ProgressView("Preparando resultados…").frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            if model.root != nil {
                HSplitView {
                    BrowserView().frame(minWidth: 520)
                    SidePanel().frame(minWidth: 340, idealWidth: 400, maxWidth: 560)
                }
                .overlay(alignment: .top) {
                    if model.phase != .idle {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(model.phase == .deleting ? "Eliminando…" : "Actualizando datos…")
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 8)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("Elige un disco y pulsa Analizar", systemImage: "internaldrive")
                } description: {
                    Text("Se calculará el espacio que ocupa cada carpeta y fichero, y se te sugerirá qué puedes eliminar.")
                } actions: {
                    Button("Analizar") { model.startScan() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.selectedVolume == nil)
                }
            }
        }
    }
}

struct VolumeBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let v = model.selectedVolume, v.total > 0 {
            HStack(spacing: 12) {
                Image(systemName: v.icon).foregroundStyle(.secondary)
                Text(v.name).fontWeight(.medium)
                ProgressView(value: Double(v.used), total: Double(v.total))
                    .frame(maxWidth: 260)
                Text("\(Fmt.size(v.used)) usados de \(Fmt.size(v.total)) · \(Fmt.size(v.available)) libres")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                if let root = model.root, model.scannedMatches(v) {
                    Text("Analizado: \(Fmt.size(root.size))").font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        } else {
            HStack {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(model.selectedVolume?.id ?? "Sin disco seleccionado").foregroundStyle(.secondary)
                Spacer()
                if let root = model.root { Text("Analizado: \(Fmt.size(root.size))").font(.callout).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }
}

struct ScanningView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Analizando…").font(.title3)
            Text("\(model.scanItems.formatted()) elementos · \(Fmt.size(model.scanBytes))")
                .monospacedDigit().foregroundStyle(.secondary)
            Text(model.scanPath)
                .font(.caption).foregroundStyle(.tertiary)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 600)
            Button("Cancelar") { model.cancelScan() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PermissionsBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.trianglebadge.exclamationmark.fill").foregroundStyle(.orange)
            Text("No se pudieron leer \(model.unreadableCount) carpetas por falta de permisos. Concede «Acceso total al disco» a Disk Cleaner y vuelve a analizar para ver todo el espacio.")
                .font(.callout)
            Spacer()
            Button("Abrir Ajustes") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button { model.unreadableCount = 0 } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }
}

struct MessageBanner: View {
    @EnvironmentObject var model: AppModel
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(.blue)
            Text(text).font(.callout)
            Spacer()
            Button { model.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.blue.opacity(0.10))
    }
}
