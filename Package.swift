// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "promote-sandbox",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "promote-sandbox")
    ]
)
