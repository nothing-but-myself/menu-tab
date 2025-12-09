// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "MenuBarRotator",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "MenuBarRotator",
            path: "MenuBarRotator"
        )
    ]
)
