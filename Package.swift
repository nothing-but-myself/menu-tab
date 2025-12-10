// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "MenuTab",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "MenuTab",
            path: "MenuTab"
        )
    ]
)
