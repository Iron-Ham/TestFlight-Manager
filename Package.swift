// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "TestFlightManager",
  platforms: [
    .macOS(.v13)
  ],
  dependencies: [
    .package(
      url: "https://github.com/AvdLee/appstoreconnect-swift-sdk.git",
      .upToNextMajor(from: "4.0.0")
    ),
    .package(
      url: "https://github.com/apple/swift-argument-parser.git",
      .upToNextMajor(from: "1.3.0")
    ),
  ],
  targets: [
    .executableTarget(
      name: "TestFlightManager",
      dependencies: [
        .product(name: "AppStoreConnect-Swift-SDK", package: "appstoreconnect-swift-sdk"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .testTarget(
      name: "TestflightManagerTests",
      dependencies: ["TestFlightManager"]
    ),
  ]
)
