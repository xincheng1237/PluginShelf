// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PluginShelf",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PluginShelfCore", targets: ["PluginShelfCore"]), .executable(name: "PluginShelf", targets: ["PluginShelf"])],
    targets: [.target(name: "PluginShelfCore", resources: [.process("Resources")]), .executableTarget(name: "PluginShelf", dependencies: ["PluginShelfCore"]), .testTarget(name: "PluginShelfCoreTests", dependencies: ["PluginShelfCore"]), .testTarget(name: "PluginShelfTests", dependencies: ["PluginShelf"])],
    swiftLanguageModes: [.v6]
)
