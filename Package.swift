// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacSlap",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MacSlap",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
            ]
        )
    ]
)
