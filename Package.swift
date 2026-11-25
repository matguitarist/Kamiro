// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Kamiro",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        // The Log page's viewer, shared by my Mac apps.
        .package(url: "https://github.com/matguitarist/LogKit", from: "0.6.0"),
        // Runs ffmpeg, cwebp, ImageMagick, smbutil and the like, shared by my Mac apps.
        .package(url: "https://github.com/matguitarist/ProcessKit", from: "0.1.1"),
    ],
    targets: [
        // File logic with no SwiftUI (paths, names, transfers), so tests run without the app.
        .target(name: "KamiroKit", dependencies: [.product(name: "LogKit", package: "LogKit"),
                                                 .product(name: "ProcessKit", package: "ProcessKit")]),
        .executableTarget(
            name: "Kamiro",
            dependencies: ["KamiroKit", .product(name: "Sparkle", package: "Sparkle"),
                           .product(name: "LogKitUI", package: "LogKit"), .product(name: "ProcessKit", package: "ProcessKit")],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)],
            // Sparkle.framework sits in Contents/Frameworks (build.sh copies it).
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "KamiroKitTests", dependencies: ["KamiroKit", .product(name: "ProcessKit", package: "ProcessKit")]),
    ]
)
