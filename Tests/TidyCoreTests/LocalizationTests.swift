import XCTest

/// Checks the string catalog itself: every string the app shows has a Turkish translation,
/// and each translation carries the same placeholders as its English key.
final class LocalizationTests: XCTestCase {
    private func catalog() throws -> [String: [String: Any]] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Localizable.xcstrings")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(root["sourceLanguage"] as? String, "en")
        return try XCTUnwrap(root["strings"] as? [String: [String: Any]])
    }

    /// Placeholders without their position, sorted: "%2$lld … %1$@" and "%@ … %lld" both give ["@", "lld"].
    private func placeholders(_ s: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: "%(?:\\d+\\$)?(lld|@|ld|d|f)")
        let text = s.replacingOccurrences(of: "%%", with: "")
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } }.sorted()
    }

    func testEveryStringHasATurkishTranslationWithMatchingPlaceholders() throws {
        let strings = try catalog()
        XCTAssertGreaterThan(strings.count, 200)
        for (key, entry) in strings where !key.isEmpty {
            XCTAssertNotEqual(entry["extractionState"] as? String, "stale", "no longer used, run ./localize.sh: \(key)")
            let unit = ((entry["localizations"] as? [String: Any])?["tr"] as? [String: Any])?["stringUnit"] as? [String: Any]
            guard let value = unit?["value"] as? String, unit?["state"] as? String == "translated", !value.isEmpty else {
                XCTFail("missing Turkish translation: \(key)"); continue
            }
            XCTAssertEqual(try placeholders(value), try placeholders(key), "placeholders differ: \(key) → \(value)")
        }
    }
}
