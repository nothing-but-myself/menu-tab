// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "WhatsHidden",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "WhatsHidden",
            path: "Sources/WhatsHidden"
        )
    ]
)
