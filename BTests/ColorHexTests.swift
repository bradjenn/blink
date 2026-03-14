import SwiftUI
import XCTest
@testable import Blink

final class ColorHexTests: XCTestCase {
    func testParsesSixDigitHex() {
        let components = Color.hexComponents("#080810")
        XCTAssertNotNil(components)
        XCTAssertEqual(components!.red, 8.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(components!.green, 8.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(components!.blue, 16.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(components!.alpha, 1.0)
    }

    func testParsesWithoutHash() {
        let components = Color.hexComponents("c8ff00")
        XCTAssertNotNil(components)
        XCTAssertEqual(components!.red, 200.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(components!.green, 1.0, accuracy: 0.001)
        XCTAssertEqual(components!.blue, 0.0, accuracy: 0.001)
    }

    func testReturnsNilForInvalidHex() {
        XCTAssertNil(Color.hexComponents("xyz"))
        XCTAssertNil(Color.hexComponents("#12"))
        XCTAssertNil(Color.hexComponents(""))
    }

    func testColorInitializerDoesNotCrash() {
        let color = Color(hex: "#0fc5ed")
        XCTAssertNotNil(color)
    }

    func testWithAlpha() {
        let color = Color(hex: "#c8ff00", opacity: 0.2)
        XCTAssertNotNil(color)
    }
}
