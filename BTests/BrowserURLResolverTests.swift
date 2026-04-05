import XCTest
@testable import Blink

final class BrowserURLResolverTests: XCTestCase {
    func testResolveAbsoluteHTTPSURL() {
        XCTAssertEqual(
            BrowserURLResolver.resolve("https://example.com/docs")?.absoluteString,
            "https://example.com/docs"
        )
    }

    func testResolveBareHostDefaultsToHTTPS() {
        XCTAssertEqual(
            BrowserURLResolver.resolve("example.com/docs")?.absoluteString,
            "https://example.com/docs"
        )
    }

    func testResolveLocalhostDefaultsToHTTP() {
        XCTAssertEqual(
            BrowserURLResolver.resolve("localhost:3000/auth")?.absoluteString,
            "http://localhost:3000/auth"
        )
    }

    func testResolveCustomLocalDomainDefaultsToHTTP() {
        XCTAssertEqual(
            BrowserURLResolver.resolve("app.local/login")?.absoluteString,
            "http://app.local/login"
        )
    }

    func testResolvePlainSearchTextToGoogleSearch() {
        XCTAssertEqual(
            BrowserURLResolver.resolve("blink browser docs")?.absoluteString,
            "https://www.google.com/search?q=blink%20browser%20docs"
        )
    }

    func testResolveSingleWordToGoogleSearch() {
        XCTAssertEqual(
            BrowserURLResolver.resolve("blink")?.absoluteString,
            "https://www.google.com/search?q=blink"
        )
    }
}
