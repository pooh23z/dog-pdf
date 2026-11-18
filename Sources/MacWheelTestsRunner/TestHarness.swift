import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

final class TestSuiteRunner {
    private var tests: [(suite: String, name: String, body: @Sendable () async throws -> Void)] = []

    func test(_ suite: String, _ name: String, _ body: @escaping @Sendable () async throws -> Void) {
        tests.append((suite, name, body))
    }

    func run(filter: String?) async -> Int32 {
        let selected = tests.filter { entry in
            guard let filter, !filter.isEmpty else { return true }
            return entry.suite.localizedCaseInsensitiveContains(filter)
                || entry.name.localizedCaseInsensitiveContains(filter)
        }
        var passed = 0
        var failed = 0
        for item in selected {
            do {
                try await item.body()
                print("PASS [\(item.suite)] \(item.name)")
                passed += 1
            } catch {
                print("FAIL [\(item.suite)] \(item.name): \(error)")
                failed += 1
            }
        }
        print("Summary: \(passed) passed, \(failed) failed (total \(selected.count))")
        return failed == 0 && selected.count > 0 ? 0 : 1
    }
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #file, line: Int = #line) throws {
    if actual != expected {
        throw TestFailure(message: "Expected \(expected), got \(actual). \(message) (\(file):\(line))")
    }
}

func assertTrue(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) throws {
    if !condition {
        throw TestFailure(message: "Assertion failed. \(message) (\(file):\(line))")
    }
}

func assertThrowsAsync<E: Error & Equatable>(_ expectedError: E? = nil, _ block: () async throws -> Void, file: String = #file, line: Int = #line) async throws {
    do {
        try await block()
        throw TestFailure(message: "Expected error to be thrown (\(file):\(line))")
    } catch let failure as TestFailure {
        throw failure
    } catch {
        if let expectedError {
            guard let typed = error as? E, typed == expectedError else {
                throw TestFailure(message: "Expected error \(expectedError), got \(error) (\(file):\(line))")
            }
        }
    }
}

func makeTempDirectory(_ name: String = UUID().uuidString) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("MacWheelTests-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
