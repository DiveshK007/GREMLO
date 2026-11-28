// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Gremlo",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic and offscreen drawing (no AppKit), unit-tested.
        .target(name: "GremloCore"),
        .executableTarget(name: "Gremlo", dependencies: ["GremloCore", "Sparkle"],
                          resources: [.copy("Resources/gremlo-hook.sh"), .copy("Resources/gremlo-git-hook.sh")],
                          // release-mac.sh puts Sparkle.framework in Contents/Frameworks
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "GremloCLI", dependencies: ["GremloCore"]),
        // auto-update: Sparkle 2.10.1's release build, pinned by checksum (no clone of the Sparkle repo). To bump:
        // swift package compute-checksum on the new Sparkle-for-Swift-Package-Manager.zip, and the same hash in release.yml.
        .binaryTarget(name: "Sparkle", url: "https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-for-Swift-Package-Manager.zip",
                      checksum: "4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a"),
        .testTarget(name: "GremloCoreTests", dependencies: ["GremloCore"], exclude: ["__Snapshots__"], resources: [.copy("Fixtures")]),
    ]
)
