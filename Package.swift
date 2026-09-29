// swift-tools-version:5.9
// SPDX-License-Identifier: GPL-3.0-or-later
import PackageDescription

var products: [Product] = [
    .library(name: "ATCCore", targets: ["ATCCore"]),
]
var targets: [Target] = [
    // Foundation only: builds and tests on Linux.
    .target(name: "ATCCore"),
    .testTarget(name: "ATCCoreTests", dependencies: ["ATCCore"]),
]

// AppKit app: only declared on macOS, so the Linux build never sees it.
#if os(macOS)
products.append(.executable(name: "Annunciator", targets: ["Annunciator"]))
targets.append(.executableTarget(name: "Annunciator", dependencies: ["ATCCore"]))
#endif

let package = Package(
    name: "atc-app",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
