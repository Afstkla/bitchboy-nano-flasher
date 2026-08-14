// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BitchBoyNano",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Flasher", path: "Sources/Flasher")
    ]
)
