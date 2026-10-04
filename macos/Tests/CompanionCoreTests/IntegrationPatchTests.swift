import XCTest
@testable import CompanionCore

final class IntegrationPatchTests: XCTestCase {
    func testInstallPreservesOtherPluginsAndIsIdempotent() throws {
        let original = "# user's plugin\n- insert:\n    - id: existing\n      name: existing-plugin\n"
        let installed = try IntegrationPatch.installing(into: original, pluginEntry: "/path with spaces/index.js")
        XCTAssertTrue(installed.hasPrefix(original))
        XCTAssertEqual(try IntegrationPatch.installing(into: installed, pluginEntry: "/path with spaces/index.js"), installed)
        XCTAssertEqual(try IntegrationPatch.removing(from: installed), original)
    }
    func testEmptyArrayBecomesValidPatchList() throws {
        let installed = try IntegrationPatch.installing(into: "[]\n", pluginEntry: "/plugin.js")
        XCTAssertFalse(installed.contains("[]")); XCTAssertTrue(installed.contains("- insert:"))
    }
    func testMalformedMarkersDoNotDeleteUserContent() {
        XCTAssertThrowsError(try IntegrationPatch.removing(from: "# BEGIN DSH ALWAYS ON MANAGED\nuser content"))
        XCTAssertThrowsError(try IntegrationPatch.removing(from: "# END DSH ALWAYS ON MANAGED"))
    }
    func testUnsupportedYamlIsNotBlindlyAppended() {
        XCTAssertThrowsError(try IntegrationPatch.installing(into: "plugins: {}", pluginEntry: "/plugin.js"))
        XCTAssertThrowsError(try IntegrationPatch.installing(into: "---\n[]", pluginEntry: "/plugin.js"))
    }
}
