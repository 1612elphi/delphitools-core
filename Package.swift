// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DelphiCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "DelphiCore", targets: ["DelphiCore"]),
        .library(name: "DelphiMacros", targets: ["DelphiMacros"]),
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
        .target(name: "DelphiMacros"),
        .testTarget(
            name: "DelphiCoreTests",
            dependencies: ["DelphiCore"]
        ),
        .testTarget(
            name: "DelphiMacrosTests",
            dependencies: ["DelphiMacros"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
