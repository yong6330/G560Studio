// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "G560Studio",
    platforms: [.macOS("14.2")],
    targets: [
        .target(name: "G560Core", linkerSettings: [
            .linkedFramework("IOKit"), .linkedFramework("CoreAudio"), .linkedFramework("Accelerate"),
        ]),
        .executableTarget(name: "G560Studio", dependencies: ["G560Core"],
                          exclude: ["Info.plist"]),
        .executableTarget(name: "g560ctl", dependencies: ["G560Core"]),
        .testTarget(name: "G560CoreTests", dependencies: ["G560Core"]),
    ]
)
