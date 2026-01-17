// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "PersistentHistoryTrackingKit",
  platforms: [
    .iOS(.v17),  // V2: iOS 17+ for CoreDataEvolution
    .macOS(.v14),  // V2: macOS 14+
    .macCatalyst(.v17),
    .tvOS(.v17),
    .watchOS(.v10),
  ],
  products: [
    .library(
      name: "PersistentHistoryTrackingKit",
      targets: ["PersistentHistoryTrackingKit"]
    )
  ],
  dependencies: [
    // CoreDataEvolution - iOS 17+, Swift 6
    .package(
      url: "https://github.com/fatbobman/CoreDataEvolution.git", .upToNextMajor(from: "0.5.0"))
  ],
  targets: [
    .target(
      name: "PersistentHistoryTrackingKit",
      dependencies: [
        .product(name: "CoreDataEvolution", package: "CoreDataEvolution")
      ],
      swiftSettings: [
        .enableUpcomingFeature("InternalImportsByDefault"),
        .swiftLanguageMode(.v6),
      ]
    ),
    .testTarget(
      name: "PersistentHistoryTrackingKitTests",
      dependencies: ["PersistentHistoryTrackingKit"],
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),
  ]
)
