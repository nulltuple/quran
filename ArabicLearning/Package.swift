// swift-tools-version:6.0

// ArabicLearning: the modules of the Arabican app (App Store Connect "Arabican",
// bundle com.nulltup.arabican). It is NOT part of the Quran (MemQuran) app.
// QuranEngine (the root package, "..") never depends on this package.
// See Documentation/ArabicLearning/02-ADR-0001-foundation-and-architecture.md §4.

import PackageDescription

let package = Package(
    name: "ArabicLearning",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(name: "LearningModel", targets: ["LearningModel"]),
        .library(name: "LearningUI", targets: ["LearningUI"]),
    ],
    dependencies: [
        .package(name: "QuranEngine", path: ".."),
    ],
    targets: [
        .target(name: "LearningModel"),
        .testTarget(name: "LearningModelTests", dependencies: ["LearningModel"]),

        .target(name: "LearningUI", dependencies: [
            "LearningModel",
            .product(name: "NoorUI", package: "QuranEngine"),
        ], resources: [
            .process("Resources"),
        ]),
        .testTarget(name: "LearningUITests", dependencies: ["LearningUI"]),
    ]
)
