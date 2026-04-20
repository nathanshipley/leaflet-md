// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "MarkdownViewer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MarkdownViewerCore", targets: ["MarkdownViewerCore"]),
        .executable(name: "MarkdownViewer", targets: ["MarkdownViewer"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-cmark.git", from: "0.7.1")
    ],
    targets: [
        .target(
            name: "MarkdownViewerCore",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark")
            ],
            path: "Sources/MarkdownViewer",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "MarkdownViewer",
            dependencies: [
                "MarkdownViewerCore"
            ],
            path: "Sources/MarkdownViewerApp"
        ),
        .testTarget(
            name: "MarkdownViewerTests",
            dependencies: ["MarkdownViewerCore"],
            path: "Tests/MarkdownViewerTests",
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
