//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import Testing

import SWBCore
import SWBTaskConstruction
import SWBTestSupport
@_spi(Testing) import SWBUtil

@Suite
fileprivate struct ToolsetTaskConstructionTests: CoreBasedTests {
    @Test(.requireSDKs(.host))
    func toolsetCustomization() async throws {
        try await withTemporaryDirectory { tmpDir in
            let core = try await getCore()
            let toolchainBinDir = tmpDir.join("custom-toolchain").join("bin")
            try localFS.createDirectory(toolchainBinDir, recursive: true)
            let customClang = toolchainBinDir.join(core.hostOperatingSystem.imageFormat.executableName(basename: "clang"))
            let customClangxx = toolchainBinDir.join(core.hostOperatingSystem.imageFormat.executableName(basename: "clang++"))
            let customSwiftc = toolchainBinDir.join(core.hostOperatingSystem.imageFormat.executableName(basename: "swiftc"))
            try localFS.symlink(customClang, target: try await clangCompilerPath)
            try localFS.symlink(customClangxx, target: try await clangPlusPlusCompilerPath)
            try localFS.symlink(customSwiftc, target: try await swiftCompilerPath)

            let toolsetPath = tmpDir.join("toolset.json")
            let toolset = SwiftSDK.Toolset(
                cCompiler: .init(path: customClang.str, extraCLIOptions: ["-DTOOLSET_C"]),
                cxxCompiler: .init(path: customClangxx.str, extraCLIOptions: ["-DTOOLSET_CXX"]),
                swiftCompiler: .init(path: customSwiftc.str, extraCLIOptions: ["-DTOOLSET_SWIFT"]),
                linker: .init(path: Path.root.join("some").join("path").join("to").join(core.hostOperatingSystem.imageFormat.executableName(basename: "ld")).str, extraCLIOptions: ["-ltoolset-lib"]),
                librarian: .init(path: Path.root.join("some").join("path").join("to").join(core.hostOperatingSystem.imageFormat.executableName(basename: "ar")).str, extraCLIOptions: ["-ltoolset-archive"])
            )
            let toolsetData = try JSONEncoder().encode(toolset)
            try localFS.createDirectory(toolsetPath.dirname, recursive: true)
            try localFS.write(toolsetPath, contents: ByteString(toolsetData))

            let testProject = TestProject(
                "aProject",
                groupTree: TestGroup(
                    "SomeFiles",
                    children: [
                        TestFile("file.c"),
                        TestFile("file.cpp"),
                        TestFile("file.swift"),
                    ]),
                buildConfigurations: [
                    TestBuildConfiguration("Debug", buildSettings: [
                        "PRODUCT_NAME": "$(TARGET_NAME)",
                        "SWIFT_VERSION": try await swiftVersion,
                        "CLANG_USE_RESPONSE_FILE": "NO",
                        "SWIFT_SDK_TOOLSETS": toolsetPath.strWithPosixSlashes,
                    ]),
                ],
                targets: [
                    TestStandardTarget(
                        "DynamicLib",
                        type: .dynamicLibrary,
                        buildConfigurations: [
                            TestBuildConfiguration("Debug", buildSettings: [
                                "LINKER_DRIVER": "swiftc",
                            ]),
                        ],
                        buildPhases: [
                            TestSourcesBuildPhase(["file.c", "file.cpp", "file.swift"]),
                        ],
                        dependencies: ["StaticLib"]
                    ),
                    TestStandardTarget(
                        "StaticLib",
                        type: .staticLibrary,
                        buildConfigurations: [
                            TestBuildConfiguration("Debug", buildSettings: [
                                "LINKER_DRIVER": "clang"
                            ]),
                        ],
                        buildPhases: [
                            TestSourcesBuildPhase(["file.c", "file.cpp", "file.swift"]),
                        ]
                    ),
                ])

            let tester = try TaskConstructionTester(core, testProject)

            await tester.checkBuild(BuildParameters(configuration: "Debug"), runDestination: .host, fs: localFS) { results in
                results.checkNoDiagnostics()

                results.checkTarget("DynamicLib") { target in
                    results.checkTask(.matchTarget(target), .matchRuleType("CompileC"), .matchRuleItemPattern(.suffix("file.c"))) { task in
                        task.checkCommandLineContains([customClang.str])
                        task.checkCommandLineContains(["-DTOOLSET_C"])
                    }

                    results.checkTask(.matchTarget(target), .matchRuleType("CompileC"), .matchRuleItemPattern(.suffix("file.cpp"))) { task in
                        task.checkCommandLineContains([customClangxx.str])
                        task.checkCommandLineContains(["-DTOOLSET_CXX"])
                    }

                    results.checkTask(.matchTarget(target), .matchRuleType("SwiftDriver Compilation")) { task in
                        task.checkCommandLineContains([customSwiftc.str])
                        task.checkCommandLineContains(["-DTOOLSET_SWIFT"])
                    }

                    results.checkTask(.matchTarget(target), .matchRuleType("Ld")) { task in
                        task.checkCommandLineContains(["-ld-path=\(Path.root.join("some").join("path").join("to").join(core.hostOperatingSystem.imageFormat.executableName(basename: "ld")).str)"])
                        task.checkCommandLineContains(["-ltoolset-lib"])
                        task.checkCommandLineContains(["-DTOOLSET_SWIFT"])
                    }
                }

                results.checkTarget("StaticLib") { target in
                    results.checkTask(.matchTarget(target), .matchRuleType("CompileC"), .matchRuleItemPattern(.suffix("file.c"))) { task in
                        task.checkCommandLineContains([customClang.str])
                        task.checkCommandLineContains(["-DTOOLSET_C"])
                    }

                    results.checkTask(.matchTarget(target), .matchRuleType("CompileC"), .matchRuleItemPattern(.suffix("file.cpp"))) { task in
                        task.checkCommandLineContains([customClangxx.str])
                        task.checkCommandLineContains(["-DTOOLSET_CXX"])
                    }

                    results.checkTask(.matchTarget(target), .matchRuleType("SwiftDriver Compilation")) { task in
                        task.checkCommandLineContains([customSwiftc.str])
                        task.checkCommandLineContains(["-DTOOLSET_SWIFT"])
                    }

                    results.checkTask(.matchTarget(target), .matchRuleType("Libtool")) { task in
                        task.checkCommandLineContains([Path.root.join("some").join("path").join("to").join(core.hostOperatingSystem.imageFormat.executableName(basename: "ar")).str])
                        task.checkCommandLineContains(["-ltoolset-archive"])
                        task.checkCommandLineDoesNotContain("-DTOOLSET_SWIFT")
                    }
                }
            }
        }
    }
}
