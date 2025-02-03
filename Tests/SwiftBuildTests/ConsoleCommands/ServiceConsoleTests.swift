//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import Testing
import SWBTestSupport
import SWBUtil

#if os(Windows)
import WinSDK
#endif

@Suite
fileprivate struct ServiceConsoleTests {
    @Test
    func emptyInput() async throws {
        // Test against a non-pty.
        let task = SWBUtil.Process()
        task.executableURL = try CLIConnection.swiftbuildToolURL
        task.environment = CLIConnection.environment

        task.standardInput = FileHandle.nullDevice
        try await withExtendedLifetime(Pipe()) { outputPipe in
            let standardOutput = task._makeStream(for: \.standardOutputPipe, using: outputPipe)
            let promise: Promise<Processes.ExitStatus, any Error> = try task.launch()

            let data = try await standardOutput.reduce(into: [], { $0.append($1) })
            let output = String(decoding: data, as: UTF8.self)

            // Verify there were no errors.
            #expect(output == "swbuild> \n")

            // Assert the tool exited successfully.
            await #expect(try promise.value == .exit(0))
        }
    }

    @Test
    func commandLineArguments() async throws {
        // Test against command line arguments.
        let executionResult = try await Process.getOutput(url: try CLIConnection.swiftbuildToolURL, arguments: ["isAlive"], environment: CLIConnection.environment)

        // Verify there were no errors.
        #expect(String(decoding: executionResult.stdout, as: UTF8.self) == "is alive? yes" + String.newline)

        // Assert the tool exited successfully.
        #expect(executionResult.exitStatus == .exit(0))
    }

    /// Test that the build service shuts down if the host dies.
    @Test(.skipHostOS(.windows)) // PTY not supported on Windows
    func serviceShutdown() async throws {
        try await withCLIConnection { cli in
            // Find the service pid.
            try cli.send(command: "dumpPID")
            var reply = try await cli.getResponse()
            let servicePID = try {
                var servicePID = pid_t(-1)
                for line in reply.components(separatedBy: "\n") {
                    if let match = try #/service pid = (?<pid>\d+)/#.firstMatch(in: line) {
                        servicePID = try #require(pid_t(match.output.pid))
                    }
                }
                #expect(servicePID != -1, "unable to find service PID")
                return servicePID
            }()
            #expect(servicePID != cli.processIdentifier, "service PID (\(servicePID)) must not match the CLI PID (\(cli.processIdentifier)) when running in out-of-process mode")

            // Make sure the service has started.
            try cli.send(command: "isAlive")
            reply = try await cli.getResponse()
            #expect(reply.contains("is alive? yes"))

            let serviceExitPromise = try Processes.exitPromise(pid: servicePID)

            // Now terminate the 'swbuild' tool (host process)
            try cli.terminate()

            // Wait for it to exit.
            await #expect(try cli.exitStatus != .exit(0))
            await #expect(try cli.exitStatus.wasSignaled)

            // Now wait for the service subprocess to exit, without any further communication.
            try await serviceExitPromise.value
        }
    }

    /// Tests that the serializedDiagnostics console command is able to print human-readable serialized diagnostics from a .dia file.
    @Test(.skipHostOS(.windows)) // PTY not supported on Windows
    func dumpSerializedDiagnostics() async throws {
        // Generate and compile a C source file that will generate a compiler warning.
        try await withTemporaryDirectory { tmp in
            let diagnosticsPath = tmp.join("foo.dia")
            let sourceFilePath = tmp.join("foo.c")
            try localFS.write(sourceFilePath, contents: "int main() { int foo; *foo = \"string\"; return 0; }")
            _ = try? await runHostProcess(["clang", "-serialize-diagnostics", diagnosticsPath.str, sourceFilePath.str])

            // Run the `serializedDiagnostics --dump` command on the .dia file generated by the compiler.
            try await withCLIConnection { cli in
                try cli.send(command: "serializedDiagnostics --dump \(diagnosticsPath.str)")

                // Verify that all the attributes of the diagnostic were printed (file path, line, column, range info, message, etc.).
                let reply = try await cli.getResponse()
                #expect(reply.contains("foo.c:1:23: [1:24-1:27]: error: [Semantic Issue] indirection requires pointer operand ('int' invalid)"), Comment(rawValue: reply))
            }
        }
    }
}

extension Processes {
    fileprivate static func exitPromise(pid: pid_t) throws -> Promise<Void, any Error> {
        let promise = Promise<Void, any Error>()
        #if os(Windows)
        guard let proc = OpenProcess(DWORD(SYNCHRONIZE), false, DWORD(pid)) else {
            throw StubError.error("OpenProcess failed with error \(GetLastError())")
        }
        defer { CloseHandle(proc) }
        Thread.detachNewThread {
            if WaitForSingleObject(proc, INFINITE) == WAIT_FAILED {
                promise.fail(throwing: StubError.error("WaitForSingleObject failed with error \(GetLastError())"))
                return
            }
            promise.fulfill(with: ())
        }
        #else
        Task<Void, Never>.detached {
            while true {
                // We use getpgid() here to detect when the process has exited (it is not a child). Surprisingly, getpgid() is substantially faster than using kill(pid, 0) here because kill still returns success for zombies, and the service has been reparented to launchd.
                do {
                    if getpgid(pid) < 0 {
                        // We expect the signal to eventually fail with "No such process".
                        if errno != ESRCH {
                            throw StubError.error("unexpected exit code: \(errno)")
                        }
                        break
                    }
                    try await Task.sleep(for: .microseconds(1000))
                } catch {
                    promise.fail(throwing: error)
                    return
                }
            }
            promise.fulfill(with: ())
        }
        #endif
        return promise
    }
}
