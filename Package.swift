// swift-tools-version: 6.2
import PackageDescription

// The tc4mac plugin SDK: the contract a plugin builds against, and nothing
// else. It depends only on Foundation on purpose — a plugin author should
// never have to take on the app's internals to write one.
let package = Package(
    name: "TCPluginSDK",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TCPluginSDK", targets: ["TCPluginSDK"])
    ],
    targets: [
        .target(name: "TCPluginSDK")
    ]
)
