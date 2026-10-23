// swift-tools-version: 6.0
import PackageDescription

// Firelight's core logic lives here so the app, the widgets, the share
// extension and the watch app can all reuse it. One package with one
// dependency graph rather than ten packages: the module boundaries are the
// same, cross-module edges stay declarative, and external dependencies are
// pinned once. See PROGRESS.md for the reasoning.
let package = Package(
    name: "FirelightKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .watchOS(.v11)],
    products: [
        .library(name: "ABSKit", targets: ["ABSKit"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "SyncEngine", targets: ["SyncEngine"]),
        .library(name: "PlaybackKit", targets: ["PlaybackKit"]),
        .library(name: "ReaderKit", targets: ["ReaderKit"]),
        .library(name: "ConversionKit", targets: ["ConversionKit"]),
        .library(name: "DownloadKit", targets: ["DownloadKit"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "Features", targets: ["Features"]),
        .library(name: "ABSMockServer", targets: ["ABSMockServer"]),
    ],
    // Approved in SPEC.md: Nuke is MIT. Added in Phase 2, when covers first
    // need loading and caching.
    dependencies: [
        .package(url: "https://github.com/kean/Nuke.git", from: "12.0.0"),
        // Approved in SPEC.md: MIT. Added in Phase 4 for live progress sync.
        .package(url: "https://github.com/socketio/socket.io-client-swift.git", from: "16.1.0"),
        // Approved in SPEC.md: BSD-3. Added in Phase 6 for EPUB reading.
        .package(url: "https://github.com/readium/swift-toolkit.git", from: "3.0.0"),
        // CBR support, approved by Cole on 2026-10-22.
        //
        // The spec names UnrarKit, which has no Package.swift and cannot be
        // added by SPM at all. `Unrar.swift` wraps the *same* rarlab UnRAR
        // source, so the licence position Cole approved is unchanged — and its
        // own wrapper is MIT rather than UnrarKit's BSD-2-Clause, which is
        // marginally better for this project.
        //
        // UnRAR's licence: free use and redistribution, but the source may not
        // be used to build a RAR compressor, and the RAR copyright notice must
        // appear in the documentation. Firelight only ever decompresses.
        .package(url: "https://github.com/mtgto/Unrar.swift.git", from: "0.5.0"),
    ],
    targets: [
        .target(
            name: "ABSKit",
            dependencies: [.product(name: "SocketIO", package: "socket.io-client-swift")]
        ),
        .target(name: "Persistence", dependencies: ["ABSKit"]),
        .target(name: "SyncEngine", dependencies: ["ABSKit", "Persistence"]),
        .target(name: "PlaybackKit", dependencies: ["ABSKit", "SyncEngine", "Persistence", "DesignSystem"]),
        .target(
            name: "ReaderKit",
            dependencies: [
                "ABSKit",
                "SyncEngine",
                "DesignSystem",
                .product(name: "ReadiumShared", package: "swift-toolkit"),
                .product(name: "ReadiumStreamer", package: "swift-toolkit"),
                .product(name: "ReadiumNavigator", package: "swift-toolkit"),
                .product(name: "ReadiumAdapterGCDWebServer", package: "swift-toolkit"),
                .product(name: "Unrar", package: "Unrar.swift"),
            ]
        ),
        .target(name: "ConversionKit", dependencies: ["ABSKit"], resources: [.process("Resources")]),
        .target(name: "DownloadKit", dependencies: ["ABSKit", "Persistence"]),
        .target(
            name: "DesignSystem",
            dependencies: [
                .product(name: "Nuke", package: "Nuke"),
                .product(name: "NukeUI", package: "Nuke"),
            ],
            resources: [.process("Resources")]
        ),
        .target(
            name: "Features",
            dependencies: [
                "ABSKit", "Persistence", "SyncEngine", "PlaybackKit",
                "ReaderKit", "ConversionKit", "DownloadKit", "DesignSystem",
            ],
            resources: [.process("Resources")]
        ),
        // Test support: a URLProtocol-backed stand-in for a real ABS server, so
        // tests exercise the production HTTP stack rather than a fake client.
        .target(name: "ABSMockServer", dependencies: ["ABSKit"], resources: [.process("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)
