import SwiftUI

enum Fmt {
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()
    static func size(_ b: Int64) -> String { formatter.string(fromByteCount: max(0, b)) }

    static let date: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}

extension FileNode {
    var ext: String { (name as NSString).pathExtension.lowercased() }
    var modifiedSort: TimeInterval { modified }

    var kind: FileKind {
        let e = ext
        if isDirectory {
            switch e {
            case "app": return .app
            case "photoslibrary", "musiclibrary", "tvlibrary", "imovielibrary", "vmwarevm", "sparsebundle", "xcarchive":
                return .package
            default: return .folder
            }
        }
        switch e {
        case "jpg", "jpeg", "png", "heic", "gif", "tiff", "tif", "raw", "cr2", "nef", "arw", "webp", "psd", "svg": return .image
        case "mov", "mp4", "m4v", "avi", "mkv", "wmv", "webm", "mpg", "mpeg": return .video
        case "mp3", "m4a", "wav", "aiff", "flac", "aac", "ogg": return .audio
        case "zip", "rar", "7z", "tar", "gz", "tgz", "xz", "bz2": return .archive
        case "dmg", "iso", "pkg", "xip": return .diskImage
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "rtf", "md": return .document
        case "swift", "m", "h", "c", "cpp", "js", "ts", "py", "rb", "go", "rs", "java", "json", "xml", "html", "css": return .code
        default: return .other
        }
    }

    var symbol: String {
        switch kind {
        case .folder: return "folder.fill"
        case .package: return "shippingbox.fill"
        case .app: return "app.fill"
        case .image: return "photo.fill"
        case .video: return "film.fill"
        case .audio: return "music.note"
        case .archive: return "archivebox.fill"
        case .diskImage: return "opticaldiscdrive.fill"
        case .document: return "doc.text.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .other: return isSymlink ? "link" : "doc.fill"
        }
    }

    var hue: Double {
        switch kind {
        case .folder: return 0.58
        case .package: return 0.72
        case .app: return 0.0
        case .image: return 0.33
        case .video: return 0.78
        case .audio: return 0.92
        case .archive, .diskImage: return 0.08
        case .document: return 0.13
        case .code: return 0.48
        case .other: return 0.0
        }
    }

    var tint: Color {
        kind == .other ? Color.secondary : Color(hue: hue, saturation: 0.6, brightness: 0.85)
    }

    var displayPath: String {
        var p = path
        let data = "/System/Volumes/Data"
        if p.hasPrefix(data) {
            p = String(p.dropFirst(data.count))
            if p.isEmpty { p = "/" }
        }
        let home = NSHomeDirectory()
        if p == home { return "~" }
        if p.hasPrefix(home + "/") { return "~" + String(p.dropFirst(home.count)) }
        return p
    }
}

// MARK: - Treemap

struct TreemapTile {
    let node: FileNode
    let rect: CGRect
}

enum Treemap {
    static func layout(_ nodes: [FileNode], in rect: CGRect, limit: Int = 500) -> [TreemapTile] {
        let items = nodes.filter { $0.size > 0 }.prefix(limit)
        let total = items.reduce(0.0) { $0 + Double($1.size) }
        guard total > 0, rect.width > 1, rect.height > 1 else { return [] }
        let scale = Double(rect.width * rect.height) / total
        let scaled = items.map { ($0, Double($0.size) * scale) }

        var tiles: [TreemapTile] = []
        var free = rect
        var row: [(FileNode, Double)] = []
        var i = 0

        func worst(_ r: [(FileNode, Double)], _ w: Double) -> Double {
            let s = r.reduce(0) { $0 + $1.1 }
            let mx = r.map { $0.1 }.max() ?? 0
            let mn = r.map { $0.1 }.min() ?? 0
            guard s > 0, mn > 0 else { return .infinity }
            return max(w * w * mx / (s * s), s * s / (w * w * mn))
        }

        func place(_ r: [(FileNode, Double)]) {
            let s = r.reduce(0) { $0 + $1.1 }
            if free.width >= free.height {
                let w = CGFloat(s) / free.height
                var y = free.minY
                for (n, a) in r {
                    let h = CGFloat(a) / w
                    tiles.append(TreemapTile(node: n, rect: CGRect(x: free.minX, y: y, width: w, height: h)))
                    y += h
                }
                free = CGRect(x: free.minX + w, y: free.minY, width: free.width - w, height: free.height)
            } else {
                let h = CGFloat(s) / free.width
                var x = free.minX
                for (n, a) in r {
                    let w = CGFloat(a) / h
                    tiles.append(TreemapTile(node: n, rect: CGRect(x: x, y: free.minY, width: w, height: h)))
                    x += w
                }
                free = CGRect(x: free.minX, y: free.minY + h, width: free.width, height: free.height - h)
            }
        }

        while i < scaled.count {
            let side = Double(min(free.width, free.height))
            let candidate = row + [scaled[i]]
            if row.isEmpty || worst(candidate, side) <= worst(row, side) {
                row = candidate
                i += 1
            } else {
                place(row)
                row = []
            }
        }
        if !row.isEmpty { place(row) }
        return tiles
    }
}
