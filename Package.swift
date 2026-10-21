// swift-tools-version: 5.9
import PackageDescription
let package = Package(
  name: "QuickTalk",
  platforms: [.macOS(.v14)],
  products: [.library(name: "QuickTalkCore", targets: ["QuickTalkCore"])],
  targets: [
    .target(name: "QuickTalkCore", path: "Sources/QuickTalkCore"),
    .testTarget(name: "QuickTalkCoreTests", dependencies: ["QuickTalkCore"], path: "Tests/QuickTalkCoreTests")
  ]
)
