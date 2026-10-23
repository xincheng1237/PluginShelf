// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PluginShelf",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PluginShelfCore", targets: ["PluginShelfCore"]), .executable(name: "PluginShelf", targets: ["PluginShelf"])],
    targets: [.target(name: "PluginShelfCore"), .executableTarget(name: "PluginShelf", dependencies: ["PluginShelfCore"]), .testTarget(name: "PluginShelfCoreTests", dependencies: ["PluginShelfCore"])],
    swiftLanguageModes: [.v6]
)
