// swift-tools-version: 6.0

import PackageDescription

let pythonExtensionNames = [
  "_asyncio", "_bisect", "_blake2", "_bz2", "_codecs_cn", "_codecs_hk",
  "_codecs_iso2022", "_codecs_jp", "_codecs_kr", "_codecs_tw", "_contextvars",
  "_csv", "_ctypes", "_datetime", "_dbm", "_decimal",
  "_elementtree", "_hashlib", "_heapq", "_interpchannels", "_interpqueues",
  "_interpreters", "_json", "_lsprof", "_lzma", "_md5", "_multibytecodec",
  "_opcode", "_pickle", "_queue", "_random", "_sha1", "_sha2", "_sha3",
  "_socket", "_sqlite3", "_ssl", "_statistics", "_struct", "_uuid", "_zoneinfo", "array",
  "binascii",
  "cmath", "fcntl", "math", "mmap", "pyexpat", "resource", "select", "termios",
  "unicodedata", "zlib",
]

let iOSRuntimeDependencies: [Target.Dependency] =
  [
    .target(name: "CYTDLPPythonBridge", condition: .when(platforms: [.iOS])),
    .target(name: "PythonRuntime", condition: .when(platforms: [.iOS])),
  ]
  + pythonExtensionNames.map {
    .target(name: $0, condition: .when(platforms: [.iOS]))
  }

let pythonBinaryTargets: [Target] =
  [
    .binaryTarget(
      name: "PythonRuntime",
      path: "Vendor/PythonRuntime/PythonRuntime.xcframework"
    )
  ]
  + pythonExtensionNames.map {
    .binaryTarget(
      name: $0,
      path: "Vendor/PythonRuntime/Extensions/\($0).xcframework"
    )
  }

let package = Package(
  name: "YTDLPKit",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
  ],
  products: [
    .library(name: "YTDLPKit", targets: ["YTDLPKit"])
  ],
  targets: [
    .target(
      name: "YTDLPKit",
      dependencies: iOSRuntimeDependencies,
      resources: [
        .process("PrivacyInfo.xcprivacy"),
        .copy("Resources/PythonRuntime"),
        .copy("Resources/Python"),
        .copy("Resources/Licenses"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("ExistentialAny")
      ]
    ),
    .target(
      name: "CYTDLPPythonBridge",
      dependencies: ["PythonRuntime"],
      publicHeadersPath: "include"
    ),
    .testTarget(
      name: "YTDLPKitTests",
      dependencies: ["YTDLPKit"],
      path: "Tests",
      sources: ["YTDLPKitTests"],
      resources: [
        .process("Fixtures")
      ],
      swiftSettings: [
        .enableUpcomingFeature("ExistentialAny")
      ]
    ),
  ] + pythonBinaryTargets,
  swiftLanguageModes: [.v6]
)
