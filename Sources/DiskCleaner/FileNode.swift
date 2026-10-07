import Foundation

enum FileKind {
    case folder, package, app, image, video, audio, archive, diskImage, document, code, other
}

/// Nodo del árbol de ficheros. Los tamaños son espacio realmente asignado en disco.
final class FileNode: Identifiable, Hashable, @unchecked Sendable {
    let name: String
    let isDirectory: Bool
    var isSymlink = false
    var unreadable = false
    var size: Int64
    /// Número de elementos descendientes (no incluye el propio nodo).
    var itemCount = 0
    var modified: TimeInterval
    var children: [FileNode] = []
    weak var parent: FileNode?
    private let rootPath: String?

    init(name: String, isDirectory: Bool, size: Int64, modified: TimeInterval, rootPath: String? = nil) {
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
        self.rootPath = rootPath
    }

    var id: ObjectIdentifier { ObjectIdentifier(self) }
    static func == (a: FileNode, b: FileNode) -> Bool { a === b }
    func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }

    var path: String {
        var parts: [String] = []
        var n: FileNode? = self
        var base = "/"
        while let x = n {
            if let r = x.rootPath { base = r; break }
            parts.append(x.name)
            n = x.parent
        }
        if parts.isEmpty { return base }
        let rest = parts.reversed().joined(separator: "/")
        return base == "/" ? "/" + rest : base + "/" + rest
    }

    func hasAncestor(in set: Set<ObjectIdentifier>) -> Bool {
        var p = parent
        while let x = p {
            if set.contains(x.id) { return true }
            p = x.parent
        }
        return false
    }

    /// Quita el nodo del árbol y actualiza tamaños de los ancestros. Devuelve el padre anterior.
    @discardableResult
    func detach() -> FileNode? {
        guard let p = parent else { return nil }
        let removedSize = size
        let removedItems = 1 + itemCount
        p.children.removeAll { $0 === self }
        var a: FileNode? = p
        while let x = a {
            x.size -= removedSize
            x.itemCount -= removedItems
            x.children.sort { $0.size > $1.size }
            a = x.parent
        }
        parent = nil
        return p
    }
}
