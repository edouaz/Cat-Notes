import XCTest
@testable import CatNotes

final class DiagnosticsTests: XCTestCase {
    func testPersistenceDisableAndClear() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "diagnostics-test-\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let log = Diagnostics(root: root, preferences: preferences)
        log.record("page.open.begin", ["page": "stable-id"], file: "Test.swift", line: 42)
        log.failure("save.failure", error: NSError(domain: "TestDomain", code: 12, userInfo: [NSLocalizedDescriptionKey: "PRIVATE-DOCUMENT-NAME"]))
        log.setEnabled(false); log.record("must-not-appear")
        let output = try await log.export(metadata: ["os": "16.7.16", "build": "4"])
        let bytes = try Data(contentsOf: output)
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        XCTAssertFalse(text.contains("PRIVATE-DOCUMENT-NAME")); XCTAssertFalse(text.contains("must-not-appear"))
        XCTAssertTrue(text.contains("Test.swift:42")); XCTAssertTrue(text.contains("TestDomain:12"))
        let reopened = Diagnostics(root: root, preferences: preferences)
        let persisted = try await reopened.export(metadata: [:])
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: persisted)) as? [String: Any])
        XCTAssertEqual((report["events"] as? [Any])?.count, 2)
        try await reopened.clear()
        let cleared = try await reopened.export(metadata: [:])
        let empty = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: cleared)) as? [String: Any])
        XCTAssertEqual((empty["events"] as? [Any])?.count, 0)
    }
    func testRotationStaysBoundedAndSurfacesDiskFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "diagnostics-test-\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let log = Diagnostics(root: root, preferences: preferences, limit: 800)
        for index in 0..<100 { log.record("event", ["index": String(index)]) }
        let exported = try await log.export(metadata: [:])
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: exported)) as? [String: Any])
        let events = try XCTUnwrap(report["events"] as? [[String: Any]])
        XCTAssertLessThan(events.count, 100); XCTAssertFalse(events.isEmpty)
        XCTAssertEqual((events.last?["fields"] as? [String: String])?["index"], "99")
        for name in ["current.jsonl", "previous.jsonl"] {
            let size = try root.appendingPathComponent(name).resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            XCTAssertLessThanOrEqual(size, 800)
        }
        let blocked = root.appendingPathComponent("not-a-directory")
        try Data().write(to: blocked)
        let broken = Diagnostics(root: blocked, preferences: preferences)
        broken.record("blocked")
        let failureFile = try await broken.export(metadata: [:])
        let failure = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: failureFile)) as? [String: Any])
        XCTAssertNotEqual(failure["logWriteError"] as? String, "none")
    }
}
