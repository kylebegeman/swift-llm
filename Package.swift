// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "swift-llm",
  platforms: [
    .iOS(.v26),
    .macOS(.v26),
    .visionOS(.v26),
  ],
  products: [
    .library(name: "SwiftLLM", targets: ["SwiftLLM"]),
    .library(name: "SwiftLLMFoundationModels", targets: ["SwiftLLMFoundationModels"]),
    .library(name: "SwiftLLMEvaluation", targets: ["SwiftLLMEvaluation"]),
  ],
  targets: [
    .target(name: "SwiftLLM"),
    .target(
      name: "SwiftLLMFoundationModels",
      dependencies: ["SwiftLLM"]
    ),
    .target(
      name: "SwiftLLMEvaluation",
      dependencies: ["SwiftLLM"]
    ),
    .testTarget(
      name: "SwiftLLMTests",
      dependencies: [
        "SwiftLLM",
        "SwiftLLMFoundationModels",
        "SwiftLLMEvaluation",
      ]
    ),
  ]
)
