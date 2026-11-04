// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DelphiCore",
    platforms: [.macOS(.v15), .iOS(.v17)],
    products: [
        .library(name: "DelphiCore", targets: ["DelphiCore"]),
    ],
    targets: [
        .target(
            name: "DelphiCore",
            resources: [
                .copy("Resources/colour-names.json"),
                .copy("Resources/tailwind-cheatsheet.json"),
                .copy("Resources/shavian-dictionary-core.json"),
                .copy("Resources/shavian-dictionary-full.json"),
                .copy("Resources/nerdamer-all.min.js"),
                .copy("Resources/svgo.browser.js"),
                .copy("Resources/imagetracer_v1.2.6.js"),
                .copy("Resources/world-land.json"),
                .copy("Resources/unicode-blocks.json"),
            ]
        ),
        .testTarget(
            name: "DelphiCoreTests",
            dependencies: ["DelphiCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
