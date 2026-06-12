// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DriMacIME",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "DriMacIME",
            dependencies: [],
            swiftSettings: [
                .unsafeFlags(["-enable-implicit-dynamic"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-bundle",
                    "-Xlinker", "-undefined",
                    "-Xlinker", "dynamic_lookup",
                ])
            ]
        ),
    ]
)
