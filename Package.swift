// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "StatusBarRotater",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "StatusBarRotater",
            path: "StatusBarRotater"
        )
    ]
)
