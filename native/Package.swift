// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Ribbon",
  platforms: [.macOS("15.0")],
  products: [
    .executable(name: "Ribbon", targets: ["Ribbon"]),
    .executable(name: "RibbonFixture", targets: ["RibbonFixture"]),
  ],
  targets: [
    .target(name: "RibbonCore"),
    .executableTarget(name: "Ribbon", dependencies: ["RibbonCore"]),
    .executableTarget(name: "RibbonFixture", dependencies: ["RibbonCore"]),
    .testTarget(name: "RibbonCoreTests", dependencies: ["RibbonCore"]),
    .testTarget(name: "RibbonUITests", dependencies: ["Ribbon", "RibbonCore"]),
  ]
)
