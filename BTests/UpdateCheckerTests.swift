import XCTest
@testable import Blink

final class UpdateCheckerTests: XCTestCase {
    func testResolveResultMarksNewerReleaseAsAvailable() {
        let release = AppRelease(
            tagName: "v0.8.0",
            name: "Blink v0.8.0",
            body: "",
            htmlUrl: "https://github.com/bradjenn/blink/releases/tag/v0.8.0"
        )

        let result = UpdateChecker.resolveResult(for: release, currentVersion: "0.7.1")

        guard case .updateAvailable(let availableRelease) = result else {
            return XCTFail("Expected updateAvailable result")
        }

        XCTAssertEqual(availableRelease.tagName, "v0.8.0")
    }

    func testResolveResultMarksMatchingReleaseAsUpToDate() {
        let release = AppRelease(
            tagName: "v0.8.0",
            name: "Blink v0.8.0",
            body: "",
            htmlUrl: "https://github.com/bradjenn/blink/releases/tag/v0.8.0"
        )

        let result = UpdateChecker.resolveResult(for: release, currentVersion: "0.8.0")

        guard case .upToDate(let version) = result else {
            return XCTFail("Expected upToDate result")
        }

        XCTAssertEqual(version, "0.8.0")
    }
}
