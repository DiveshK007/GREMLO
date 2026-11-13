// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Gremlo",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic and offscreen drawing (no AppKit), unit-tested.
        .target(name: "GremloCore"),
        .executableTarget(name: "Gremlo", dependencies: ["GremloCore"], resources: [.copy("Resources/gremlo-hook.sh"), .copy("Resources/gremlo-git-hook.sh")]),
        .executableTarget(name: "GremloCLI", dependencies: ["GremloCore"]),
        .testTarget(name: "GremloCoreTests", dependencies: ["GremloCore"], exclude: ["__Snapshots__"], resources: [.copy("Fixtures")]),
    ]
)
