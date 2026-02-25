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

import SWBTestSupport
@_spi(Testing) import SWBUtil
@_spi(Testing) import SWBCore
import SWBProtocol
import SWBMacro

@Suite
fileprivate struct SwiftSDKToolsetSettingsTests: CoreBasedTests {
    private func writeToolsetJSON(_ toolset: SwiftSDK.Toolset, to path: Path) throws {
        try localFS.createDirectory(path.dirname, recursive: true)
        let data = try JSONEncoder().encode(toolset)
        try localFS.write(path, contents: ByteString(data))
    }

    private func createTestSettings(projectBuildSettings: [String: String] = [:]) async throws -> Settings {
        let core = try await getCore()
        let testWorkspace = try TestWorkspace("Workspace",
            projects: [
                TestProject("aProject",
                    groupTree: TestGroup("SomeFiles"),
                    buildConfigurations: [
                        TestBuildConfiguration("Debug", buildSettings: projectBuildSettings)
                    ],
                    targets: [
                        TestStandardTarget("MyTarget", type: .commandLineTool,
                            buildConfigurations: [
                                TestBuildConfiguration("Debug", buildSettings: [
                                    "PRODUCT_NAME": "$(TARGET_NAME)",
                                ])
                            ],
                            buildPhases: [
                                TestSourcesBuildPhase([]),
                            ])
                    ])
            ]).load(core)

        let context = try await contextForTestData(testWorkspace, core: core, fs: localFS)
        let buildRequestContext = BuildRequestContext(workspaceContext: context)
        let testProject = context.workspace.projects[0]
        let testTarget = testProject.targets[0]

        let settings = Settings(workspaceContext: context, buildRequestContext: buildRequestContext,
                                parameters: BuildParameters(action: .build, configuration: "Debug"),
                                project: testProject, target: testTarget)
        return settings
    }

    @Test(.requireSDKs(.host))
    func swiftToolsetBasics() async throws {
        try await withTemporaryDirectory { tmpDir in
            let toolsetPath = tmpDir.join("toolset.json")
            try writeToolsetJSON(SwiftSDK.Toolset(swiftCompiler: .init(extraCLIOptions: ["-static-stdlib"])), to: toolsetPath)
            let settings = try await createTestSettings(projectBuildSettings: ["SWIFT_SDK_TOOLSETS": toolsetPath.str])
            #expect(settings.globalScope.evaluate(BuiltinMacros.OTHER_SWIFT_FLAGS).contains("-static-stdlib"))
            #expect(settings.globalScope.evaluate(BuiltinMacros.OTHER_LDFLAGS).contains("-static-stdlib"))
        }
    }

    @Test(.requireSDKs(.host))
    func multipleToolsets() async throws {
        try await withTemporaryDirectory { tmpDir in
            let toolset1Path = tmpDir.join("toolset1.json")
            let toolset2Path = tmpDir.join("toolset2.json")
            try writeToolsetJSON(SwiftSDK.Toolset(swiftCompiler: .init(extraCLIOptions: ["-DFoo"])), to: toolset1Path)
            try writeToolsetJSON(SwiftSDK.Toolset(swiftCompiler: .init(extraCLIOptions: ["-DBar"])), to: toolset2Path)
            let settings = try await createTestSettings(projectBuildSettings: ["SWIFT_SDK_TOOLSETS": "\(toolset1Path.str) \(toolset2Path.str)"])

            #expect(settings.globalScope.evaluate(BuiltinMacros.OTHER_SWIFT_FLAGS) == ["-DFoo", "-DBar"])
        }
    }

    @Test(.requireSDKs(.host))
    func unsupportedSchemaVersion() async throws {
        try await withTemporaryDirectory { tmpDir in
            let toolsetPath = tmpDir.join("toolset.json")
            try writeToolsetJSON(SwiftSDK.Toolset(schemaVersion: "99.0"), to: toolsetPath)
            let settings = try await createTestSettings(projectBuildSettings: ["SWIFT_SDK_TOOLSETS": toolsetPath.str])
            #expect(settings.errors.only?.hasPrefix("error processing toolset ") == true)
        }
    }
}
