import Foundation
import Darwin

final class ScanProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var items = 0
    private var bytes: Int64 = 0
    private var current = ""
    private var unreadablePaths: [String] = []
    private var cancelledFlag = false

    func add(items: Int, bytes: Int64, current: String) {
        lock.lock(); defer { lock.unlock() }
        self.items += items
        self.bytes += bytes
        self.current = current
    }

    func addUnreadable(_ path: String) {
        lock.lock(); defer { lock.unlock() }
        unreadablePaths.append(path)
    }

    var snapshot: (items: Int, bytes: Int64, current: String) {
        lock.lock(); defer { lock.unlock() }
        return (items, bytes, current)
    }

    var unreadableCount: Int {
        lock.lock(); defer { lock.unlock() }
        return unreadablePaths.count
    }

    func cancel() { lock.lock(); cancelledFlag = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelledFlag }
}

private struct DirEntry {
    let name: String
    let mode: mode_t
    let dev: dev_t
    let ino: UInt64
    let nlink: UInt16
    let blocks: Int64
    let mtime: TimeInterval
}

/// Escáner POSIX: no sigue enlaces simbólicos, no cruza a otros volúmenes y
/// cuenta una sola vez los hard links.
final class DiskScanner: @unchecked Sendable {
    private let progress: ScanProgress
    private var rootDev: dev_t = 0
    private let linkLock = NSLock()
    private var seenLinks = Set<UInt64>()

    init(progress: ScanProgress) { self.progress = progress }

    func scan(rootPath: String, name: String) async -> FileNode {
        var st = stat()
        _ = lstat(rootPath, &st)
        rootDev = st.st_dev
        let node = FileNode(name: name, isDirectory: true, size: 0,
                            modified: TimeInterval(st.st_mtimespec.tv_sec), rootPath: rootPath)
        await fill(node, path: rootPath, depth: 0)
        return node
    }

    private func fill(_ node: FileNode, path: String, depth: Int) async {
        if progress.isCancelled { return }
        guard let subdirs = populate(node, path: path) else { return }

        if depth < 3 && subdirs.count > 1 {
            await withTaskGroup(of: Void.self) { group in
                for (child, p) in subdirs {
                    group.addTask { await self.fill(child, path: p, depth: depth + 1) }
                }
            }
        } else {
            for (child, p) in subdirs { await fill(child, path: p, depth: depth + 1) }
        }
        finalize(node)
    }

    private func finalize(_ node: FileNode) {
        var total: Int64 = 0
        var count = 0
        for c in node.children {
            total += c.size
            count += 1 + c.itemCount
        }
        node.size = total
        node.itemCount = count
        node.children.sort { $0.size > $1.size }
    }

    /// Lee un directorio y crea los hijos. Devuelve los subdirectorios pendientes de recorrer.
    private func populate(_ node: FileNode, path: String) -> [(FileNode, String)]? {
        guard let entries = readEntries(path) else {
            node.unreadable = true
            progress.addUnreadable(path)
            return nil
        }
        var children: [FileNode] = []
        children.reserveCapacity(entries.count)
        var subdirs: [(FileNode, String)] = []
        var items = 0
        var bytes: Int64 = 0

        for e in entries {
            let type = e.mode & S_IFMT
            if type == S_IFDIR {
                if e.dev != rootDev { continue }
                let child = FileNode(name: e.name, isDirectory: true, size: 0, modified: e.mtime)
                child.parent = node
                children.append(child)
                subdirs.append((child, path == "/" ? "/" + e.name : path + "/" + e.name))
            } else {
                var size = e.blocks * 512
                if type == S_IFREG && e.nlink > 1 && !firstSighting(e.ino) { size = 0 }
                let child = FileNode(name: e.name, isDirectory: false, size: size, modified: e.mtime)
                child.isSymlink = type == S_IFLNK
                child.parent = node
                children.append(child)
                items += 1
                bytes += size
            }
        }
        node.children = children
        progress.add(items: items + subdirs.count, bytes: bytes, current: path)
        return subdirs
    }

    private func firstSighting(_ ino: UInt64) -> Bool {
        linkLock.lock(); defer { linkLock.unlock() }
        return seenLinks.insert(ino).inserted
    }

    private func readEntries(_ path: String) -> [DirEntry]? {
        guard let dir = opendir(path) else { return nil }
        defer { closedir(dir) }
        let fd = dirfd(dir)
        var result: [DirEntry] = []
        while let ent = readdir(dir) {
            let name: String = withUnsafePointer(to: &ent.pointee.d_name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 1024) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            var st = stat()
            if fstatat(fd, name, &st, AT_SYMLINK_NOFOLLOW) != 0 { continue }
            result.append(DirEntry(name: name, mode: st.st_mode, dev: st.st_dev, ino: UInt64(st.st_ino),
                                   nlink: st.st_nlink, blocks: Int64(st.st_blocks),
                                   mtime: TimeInterval(st.st_mtimespec.tv_sec)))
        }
        return result
    }
}
