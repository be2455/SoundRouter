// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SoundRouter",
    // 有了 defaultLocalization，SwiftPM 才會處理 .lproj 目錄。
    defaultLocalization: "zh-Hant",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AudioRouterCore", targets: ["AudioRouterCore"]),
        .executable(name: "audiorouter", targets: ["audiorouter"]),
        .executable(name: "SoundRouterApp", targets: ["SoundRouterApp"]),
    ],
    targets: [
        .target(
            name: "AudioRouterCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "audiorouter",
            dependencies: ["AudioRouterCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            // 命令列工具沒有 .app bundle，但 process tap 的 TCC 授權需要看到
            // Info.plist 裡的用途說明，所以直接把 plist 嵌進 Mach-O 的 __TEXT 段。
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-sectcreate",
                "-Xlinker", "__TEXT",
                "-Xlinker", "__info_plist",
                "-Xlinker", "Packaging/CLIInfo.plist",
            ])]
        ),
        .executableTarget(
            name: "SoundRouterApp",
            dependencies: ["AudioRouterCore"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AudioRouterCoreTests",
            dependencies: ["AudioRouterCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
