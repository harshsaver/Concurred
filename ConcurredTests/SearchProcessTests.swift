import XCTest
@testable import Concurred

final class SearchProcessTests: XCTestCase {
    private func script(_ text: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ConcurredSearchTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("search.sh")
        try Data(("#!/bin/sh\n" + text).utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    func testLargeStderrCannotDeadlockSearch() async throws {
        let executable = try script("""
        /usr/bin/head -c 131072 /dev/zero >&2
        printf '{"results":[{"title":"Result","url":"https://example.com","snippet":"Excerpt"}]}'
        """)
        let runner = SearchProcess(executable: executable.path, query: "--query-that-starts-with-a-dash")
        let data = try await runner.run()
        let results = try WebSearchService.decodeResults(data)
        XCTAssertEqual(results.first?.title, "Result")
    }

    func testCancellationStopsTheRunningProcess() async throws {
        let executable = try script("/usr/bin/touch \"$4\"\nexec /bin/sleep 30\n")
        let ready = executable.deletingLastPathComponent().appendingPathComponent("ready")
        let runner = SearchProcess(executable: executable.path, query: ready.path)
        let task = Task { try await runner.run() }
        let deadline = ContinuousClock.now + .seconds(2)
        while !FileManager.default.fileExists(atPath: ready.path) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: ready.path))
        runner.cancel(with: CancellationError())
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testFailedCLIExitIsReported() async throws {
        let executable = try script("exit 1\n")
        do {
            _ = try await SearchProcess(executable: executable.path, query: "query").run()
            XCTFail("Expected failed command")
        } catch { XCTAssertEqual(error.localizedDescription, WebSearchService.SearchError.failed.localizedDescription) }
    }
}
