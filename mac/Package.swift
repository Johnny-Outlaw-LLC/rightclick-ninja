// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RightClickNinja",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RightClickNinja",
            path: "Sources/RightClickNinja"
        )
    ],
    swiftLanguageVersions: [.v5]
)
