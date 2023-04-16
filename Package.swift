// swift-tools-version: 5.5

import PackageDescription

let package = Package(
 name: "Shell",
 products: [.library(name: "Shell", targets: ["Shell"])],
 dependencies: [
//  .package(path: "../Core"),
//  .package(path: "../Github/Files"),
//  .package(path: "../Regex"),
//  .package(path: "../Github/Chalk")
  .package(url: "https://github.com/neutralradiance/core", branch: "main"),
  .package(url: "https://github.com/neutralradiance/Files", branch: "master"),
  .package(url: "https://github.com/neutralradiance/regex", branch: "main"),
  .package(url: "https://github.com/mxcl/Chalk", branch: "master"),
 ],
 targets: [
  .target(
   name: "Shell", dependencies: [
    .product(name: "Extensions", package: "Core"),
    .product(name: "Regex", package: "regex"),
    "Files",
    "Chalk"
   ]
  )/*,
  .testTarget(
   name: "ShellTests",
   dependencies: ["Shell", .product(name: "Extensions", package: "Core")]
  )*/
 ]
)
