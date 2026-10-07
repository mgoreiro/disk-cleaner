import Foundation

enum Risk: Int, Comparable, Sendable {
    case safe = 0, review, caution
    static func < (a: Risk, b: Risk) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .safe: return "Seguro"
        case .review: return "Revisar"
        case .caution: return "Precaución"
        }
    }
}

struct Suggestion: Identifiable, Sendable {
    let id = UUID()
    let node: FileNode
    let title: String
    let reason: String
    let risk: Risk
}

struct Analysis: Sendable {
    var topFolders: [FileNode] = []
    var leafFolders: [FileNode] = []
    var topFiles: [FileNode] = []
    var suggestions: [Suggestion] = []
    static let empty = Analysis()

    var reclaimable: Int64 { suggestions.reduce(0) { $0 + $1.node.size } }
    var safeReclaimable: Int64 { suggestions.filter { $0.risk == .safe }.reduce(0) { $0 + $1.node.size } }
}

enum Analyzer {
    static func run(root: FileNode) -> Analysis {
        var folders: [FileNode] = []
        var files: [FileNode] = []
        let minFolder: Int64 = 10 << 20
        let minFile: Int64 = 5 << 20

        func collect(_ n: FileNode) {
            for c in n.children {
                if c.isDirectory {
                    if c.size < minFile { continue }
                    if c.size >= minFolder { folders.append(c) }
                    collect(c)
                } else if c.size >= minFile {
                    files.append(c)
                }
            }
        }
        collect(root)
        folders.sort { $0.size > $1.size }
        files.sort { $0.size > $1.size }

        // "Carpeta final": ninguna subcarpeta concentra más de la mitad de su contenido.
        let leaf = folders.filter { f in
            let biggestSub = f.children.first(where: { $0.isDirectory })?.size ?? 0
            return Double(biggestSub) < 0.5 * Double(f.size)
        }

        let finder = SuggestionFinder()
        finder.start(root: root)
        let suggestions = finder.results.sorted { $0.node.size > $1.node.size }

        return Analysis(topFolders: Array(folders.prefix(300)),
                        leafFolders: Array(leaf.prefix(200)),
                        topFiles: Array(files.prefix(200)),
                        suggestions: Array(suggestions.prefix(200)))
    }
}

private final class SuggestionFinder {
    var results: [Suggestion] = []
    private let homes: Set<String>
    private let now = Date().timeIntervalSince1970

    init() {
        let h = NSHomeDirectory()
        homes = [h, "/System/Volumes/Data" + h]
    }

    private static let skipTop: Set<String> = ["private", "Library", "System", "usr", "bin", "sbin", "opt",
                                               "cores", "var", "etc", "dev", "Volumes", "Applications"]
    private static let packageExt: Set<String> = ["app", "photoslibrary", "musiclibrary", "tvlibrary",
                                                  "imovielibrary", "vmwarevm", "pvm", "sparsebundle",
                                                  "sparseimage", "xcarchive", "framework"]

    private static let dirRules: [String: (String, String, Risk)] = [
        ".Trash": ("Papelera", "Elementos ya descartados. Se eliminan de forma definitiva.", .safe),
        "Library/Logs": ("Registros de apps", "Archivos de log; se vuelven a generar.", .safe),
        "Library/Developer/Xcode/DerivedData": ("Xcode · DerivedData", "Compilaciones intermedias; Xcode las regenera.", .safe),
        "Library/Developer/Xcode/iOS DeviceSupport": ("Xcode · iOS DeviceSupport", "Símbolos de dispositivos; se descargan de nuevo al conectarlos.", .safe),
        "Library/Developer/Xcode/watchOS DeviceSupport": ("Xcode · watchOS DeviceSupport", "Símbolos de dispositivos; se descargan de nuevo al conectarlos.", .safe),
        "Library/Developer/Xcode/Archives": ("Xcode · Archives", "Builds archivados; conserva los que necesites para simbolizar crashes.", .review),
        "Library/Developer/CoreSimulator/Devices": ("Simuladores de iOS", "Datos de simuladores. Puedes limpiar los no usados con «xcrun simctl delete unavailable».", .review),
        "Library/Application Support/MobileSync/Backup": ("Copias de seguridad de iPhone/iPad", "Backups locales de dispositivos; borra solo si ya no los necesitas.", .caution),
        "Library/Containers/com.docker.docker": ("Docker Desktop", "Imágenes, contenedores y volúmenes; se perderían sus datos.", .caution),
        ".npm/_cacache": ("Caché de npm", "Se vuelve a descargar cuando hace falta.", .safe),
        ".gradle/caches": ("Caché de Gradle", "Se vuelve a descargar cuando hace falta.", .safe),
        ".cache": ("Cachés de herramientas (~/.cache)", "Cachés de línea de comandos; se regeneran.", .safe),
        ".m2/repository": ("Repositorio local de Maven", "Dependencias; se descargan de nuevo.", .review),
        ".cargo/registry": ("Registro de Cargo", "Crates descargados; se vuelven a bajar.", .review),
        ".android/avd": ("Emuladores de Android", "Dispositivos virtuales; se pueden recrear.", .review),
        "Library/Application Support/Code/CachedData": ("Caché de VS Code", "Se regenera automáticamente.", .safe),
    ]

    private static let installerExt: Set<String> = ["dmg", "pkg", "iso", "xip"]
    private static let archiveExt: Set<String> = ["zip", "rar", "7z", "tar", "gz", "tgz", "xz", "bz2"]

    func start(root: FileNode) {
        let rootPath = root.path
        let rel: String? = homes.contains(rootPath) ? "" : nil
        visit(root, path: rootPath, rel: rel, depth: 0)
    }

    private func add(_ node: FileNode, _ title: String, _ reason: String, _ risk: Risk) {
        results.append(Suggestion(node: node, title: title, reason: reason, risk: risk))
    }

    private func visit(_ dir: FileNode, path: String, rel: String?, depth: Int) {
        for c in dir.children {
            if c.isDirectory {
                if c.size == 0 { continue }
                if depth == 0 && rel == nil && Self.skipTop.contains(c.name) { continue }
                let cpath = path == "/" ? "/" + c.name : path + "/" + c.name
                var crel: String?
                if let rel {
                    crel = depth > 7 ? nil : (rel.isEmpty ? c.name : rel + "/" + c.name)
                } else if depth <= 4, homes.contains(cpath) {
                    crel = ""
                }

                if let crel {
                    if let rule = Self.dirRules[crel] {
                        add(c, rule.0, rule.1, rule.2)
                        continue
                    }
                    if crel == "Library/Caches" {
                        for sub in c.children where sub.size >= 50 << 20 {
                            add(sub, "Caché · " + sub.name, "Caché de la app; se regenera al usarla.", .safe)
                        }
                        continue
                    }
                }
                if let rule = projectRule(c, siblings: dir.children) {
                    add(c, rule.0, rule.1, .review)
                    continue
                }
                if c.name == "node_modules" || c.name == ".git" { continue }
                if Self.packageExt.contains(c.ext) { continue }
                visit(c, path: cpath, rel: crel, depth: depth + 1)
            } else {
                fileRule(c, rel: rel)
            }
        }
    }

    private func projectRule(_ c: FileNode, siblings: [FileNode]) -> (String, String)? {
        guard c.size >= 50 << 20 else { return nil }
        func sibling(_ n: String) -> Bool { siblings.contains { $0.name == n } }
        switch c.name {
        case "node_modules" where sibling("package.json"):
            return ("node_modules · " + parentName(c), "Dependencias de Node; se reinstalan con npm/yarn/pnpm install.")
        case ".next" where sibling("package.json"):
            return (".next · " + parentName(c), "Salida de compilación de Next.js; se regenera.")
        case ".build" where sibling("Package.swift"):
            return (".build · " + parentName(c), "Compilación de Swift Package; se regenera.")
        case "target" where sibling("Cargo.toml"):
            return ("target · " + parentName(c), "Compilación de Rust; se regenera con cargo build.")
        case "Pods" where sibling("Podfile"):
            return ("Pods · " + parentName(c), "Dependencias de CocoaPods; se reinstalan con pod install.")
        case ".venv", "venv":
            if c.children.contains(where: { $0.name == "pyvenv.cfg" }) {
                return (c.name + " · " + parentName(c), "Entorno virtual de Python; se recrea desde requirements.")
            }
            return nil
        default:
            return nil
        }
    }

    private func parentName(_ c: FileNode) -> String { c.parent?.name ?? "" }

    private func fileRule(_ c: FileNode, rel: String?) {
        guard c.size >= 50 << 20, !c.isSymlink else { return }
        let ext = c.ext
        if Self.installerExt.contains(ext) {
            add(c, c.name, "Instalador o imagen de disco; normalmente ya no hace falta tras instalar.", .review)
        } else if Self.archiveExt.contains(ext) && c.size >= 200 << 20 {
            add(c, c.name, "Archivo comprimido grande; si ya está extraído puedes eliminarlo.", .review)
        } else if ext == "log" {
            add(c, c.name, "Archivo de registro grande.", .review)
        } else if c.size >= 1 << 30, c.modified > 0, now - c.modified > 365 * 86400 {
            if let rel, rel.hasPrefix("Library") { return }
            let months = Int((now - c.modified) / (30 * 86400))
            add(c, c.name, "Más de 1 GB y sin modificar desde hace \(months) meses.", .review)
        }
    }
}
