import SwiftUI
import AppKit

enum Phase { case idle, scanning, analyzing, deleting }

struct VolumeInfo: Identifiable, Hashable {
    let id: String          // ruta que se escanea
    let name: String
    let total: Int64
    let available: Int64
    let isInternal: Bool
    let isCustom: Bool

    var used: Int64 { max(0, total - available) }
    var icon: String {
        if isCustom { return "folder" }
        return isInternal ? "internaldrive" : "externaldrive"
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var volumes: [VolumeInfo] = []
    @Published var selectedVolumeID = ""
    @Published var phase: Phase = .idle

    @Published var root: FileNode?
    @Published var current: FileNode?
    @Published var selection = Set<ObjectIdentifier>()
    @Published var revision = 0
    @Published var analysis = Analysis.empty

    @Published var scanItems = 0
    @Published var scanBytes: Int64 = 0
    @Published var scanPath = ""
    @Published var unreadableCount = 0

    @Published var pendingDelete: [FileNode] = []
    @Published var showDeleteDialog = false
    @Published var message: String?

    private var customFolders: [String] = []
    private var activeProgress: ScanProgress?

    init() {
        reloadVolumes()
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reloadVolumes() }
            }
        }
    }

    var selectedVolume: VolumeInfo? { volumes.first { $0.id == selectedVolumeID } }
    var isBusy: Bool { phase != .idle }

    // MARK: Volúmenes

    func reloadVolumes() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        var list: [VolumeInfo] = []
        for url in urls {
            let path = url.path
            if path.hasPrefix("/System/Volumes") || path.hasPrefix("/private") || path.hasPrefix("/Library/Developer") { continue }
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let total = Int64(v.volumeTotalCapacity ?? 0)
            if total == 0 { continue }
            let avail = v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0)
            // En el volumen de arranque los datos del usuario viven en el volumen "Data".
            let scanPath = path == "/" ? "/System/Volumes/Data" : path
            list.append(VolumeInfo(id: scanPath, name: v.volumeName ?? url.lastPathComponent,
                                   total: total, available: avail,
                                   isInternal: v.volumeIsInternal ?? false, isCustom: false))
        }
        list.sort { a, b in
            if (a.id == "/System/Volumes/Data") != (b.id == "/System/Volumes/Data") { return a.id == "/System/Volumes/Data" }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        for f in customFolders {
            list.append(VolumeInfo(id: f, name: (f as NSString).lastPathComponent, total: 0, available: 0,
                                   isInternal: true, isCustom: true))
        }
        volumes = list
        if !list.contains(where: { $0.id == selectedVolumeID }) {
            selectedVolumeID = list.first?.id ?? ""
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Elegir"
        panel.message = "Elige la carpeta que quieres analizar"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !customFolders.contains(url.path) { customFolders.append(url.path) }
        reloadVolumes()
        selectedVolumeID = url.path
    }

    // MARK: Escaneo

    func startScan() {
        guard phase == .idle, let vol = selectedVolume else { return }
        let progress = ScanProgress()
        activeProgress = progress
        phase = .scanning
        root = nil; current = nil
        selection = []
        analysis = .empty
        unreadableCount = 0
        message = nil
        scanItems = 0; scanBytes = 0; scanPath = ""

        let poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard let self else { return }
                let s = progress.snapshot
                self.scanItems = s.items; self.scanBytes = s.bytes; self.scanPath = s.current
            }
        }
        Task {
            let scanner = DiskScanner(progress: progress)
            let node = await Task.detached(priority: .userInitiated) {
                await scanner.scan(rootPath: vol.id, name: vol.name)
            }.value
            poll.cancel()
            if progress.isCancelled {
                phase = .idle
                return
            }
            root = node
            current = node
            unreadableCount = progress.unreadableCount
            await runAnalysis()
            reloadVolumes()
        }
    }

    func cancelScan() { activeProgress?.cancel() }

    private func runAnalysis() async {
        guard let root else { phase = .idle; return }
        phase = .analyzing
        let result = await Task.detached(priority: .userInitiated) { Analyzer.run(root: root) }.value
        analysis = result
        revision += 1
        phase = .idle
    }

    // MARK: Navegación

    func navigate(to node: FileNode) {
        guard node.isDirectory else { return }
        current = node
        selection = []
    }

    func goUp() {
        if let p = current?.parent { navigate(to: p) }
    }

    /// Muestra un elemento en el explorador: va a su carpeta y lo selecciona.
    func show(_ node: FileNode) {
        guard let parent = node.parent else { return }
        current = parent
        selection = [node.id]
    }

    func breadcrumb() -> [FileNode] {
        var chain: [FileNode] = []
        var n = current
        while let x = n { chain.append(x); n = x.parent }
        return chain.reversed()
    }

    func revealInFinder(_ nodes: [FileNode]) {
        let urls = nodes.map { URL(fileURLWithPath: $0.path) }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    // MARK: Borrado

    private static let protectedPrefixes = ["/System", "/usr", "/bin", "/sbin", "/etc", "/private/etc", "/private/var/db"]

    private func logicalPath(_ node: FileNode) -> String {
        let p = node.path
        let data = "/System/Volumes/Data"
        if p.hasPrefix(data) { let s = String(p.dropFirst(data.count)); return s.isEmpty ? "/" : s }
        return p
    }

    private func isProtected(_ node: FileNode) -> Bool {
        guard node.parent != nil else { return true }
        let p = logicalPath(node)
        if p == NSHomeDirectory() { return true }
        if Self.protectedPrefixes.contains(where: { p == $0 || p.hasPrefix($0 + "/") }) { return true }
        // Carpetas de primer nivel del volumen de arranque (/Users, /Library, /Applications…)
        if node.parent === root, root?.path == "/System/Volumes/Data" { return true }
        return false
    }

    func requestDelete(_ nodes: [FileNode]) {
        guard phase == .idle else { return }
        let ids = Set(nodes.map { $0.id })
        let top = nodes.filter { $0.parent != nil && !$0.hasAncestor(in: ids) }
        guard !top.isEmpty else { return }
        pendingDelete = top
        showDeleteDialog = true
    }

    func performDelete(permanent: Bool) {
        let nodes = pendingDelete
        pendingDelete = []
        let allowed = nodes.filter { !isProtected($0) }
        let blocked = nodes.count - allowed.count
        guard !allowed.isEmpty else {
            message = "Los elementos seleccionados están protegidos y no se pueden eliminar."
            return
        }
        let jobs = allowed.map { ($0, $0.path) }
        phase = .deleting

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> ([Int], [String]) in
                let fm = FileManager.default
                var ok: [Int] = []
                var failures: [String] = []
                for (i, job) in jobs.enumerated() {
                    let url = URL(fileURLWithPath: job.1)
                    do {
                        if job.1.hasSuffix("/.Trash") {
                            // Vaciar la papelera sin borrar la carpeta en sí.
                            for item in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                                try fm.removeItem(at: item)
                            }
                        } else if permanent || job.1.contains("/.Trash/") {
                            try fm.removeItem(at: url)
                        } else {
                            try fm.trashItem(at: url, resultingItemURL: nil)
                        }
                        ok.append(i)
                    } catch {
                        failures.append("\(job.0.name): \(error.localizedDescription)")
                    }
                }
                return (ok, failures)
            }.value

            var freed: Int64 = 0
            var formerParents: [ObjectIdentifier: FileNode] = [:]
            for i in outcome.0 {
                let node = jobs[i].0
                freed += node.size
                if jobs[i].1.hasSuffix("/.Trash") {
                    for c in node.children { c.detach() }
                } else if let p = node.detach() {
                    formerParents[node.id] = p
                }
            }
            fixCurrent(formerParents)
            selection = []
            revision += 1

            let trashed = !permanent
            var text: String
            if outcome.0.isEmpty {
                text = "No se pudo eliminar ningún elemento."
            } else if trashed {
                text = "\(outcome.0.count) elemento(s) movidos a la papelera (\(Fmt.size(freed))). El espacio se libera al vaciarla."
            } else {
                text = "\(outcome.0.count) elemento(s) eliminados definitivamente. Liberados \(Fmt.size(freed))."
            }
            if blocked > 0 { text += " \(blocked) protegido(s) omitido(s)." }
            if !outcome.1.isEmpty { text += " Errores: " + outcome.1.prefix(3).joined(separator: "; ") }
            message = text

            reloadVolumes()
            await runAnalysis()
        }
    }

    private func attached(_ n: FileNode) -> Bool {
        var x = n
        while let p = x.parent { x = p }
        return x === root
    }

    private func fixCurrent(_ formerParents: [ObjectIdentifier: FileNode]) {
        guard let cur = current, !attached(cur) else { return }
        var top = cur
        while let p = top.parent { top = p }
        var target = formerParents[top.id]
        while let t = target, !attached(t) {
            var tt = t
            while let p = tt.parent { tt = p }
            target = formerParents[tt.id]
        }
        current = target ?? root
    }
}

extension AppModel {
    func scannedMatches(_ v: VolumeInfo) -> Bool {
        guard let r = root else { return false }
        return r.path == v.id
    }
}
