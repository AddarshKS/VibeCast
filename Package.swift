// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VibeCast",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VibeCast", targets: ["VibeCast"])
    ],
    targets: [
        .executableTarget(
            name: "VibeCast",
            exclude: ["Resources/VibeCastIcon.png", "Resources/VCMenuBarIcon.png"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(name: "VibeCastTests", dependencies: ["VibeCast"])
    ]
)
