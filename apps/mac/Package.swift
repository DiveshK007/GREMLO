// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Notchi",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic and offscreen drawing (no AppKit), unit-tested.
        .target(name: "NotchiCore"),
        .executableTarget(name: "Notchi", dependencies: ["NotchiCore"], resources: [.copy("Resources/notchi-hook.sh"), .copy("Resources/notchi-git-hook.sh")]),
        .testTarget(name: "NotchiCoreTests", dependencies: ["NotchiCore"], exclude: ["__Snapshots__"]),
    ]
)
