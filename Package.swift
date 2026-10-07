// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DiskCleaner",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "DiskCleaner", path: "Sources/DiskCleaner")
    ]
)
