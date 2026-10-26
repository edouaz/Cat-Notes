import XCTest
@testable import OpenNotes

final class ShapeRecognitionTests: XCTestCase {
    func testConservativeRecognition() {
        XCTAssertEqual(ShapeRecognition.recognize([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 1), CGPoint(x: 200, y: 0)])?.count, 2)
        XCTAssertNil(ShapeRecognition.recognize([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 0)]))
        XCTAssertNil(ShapeRecognition.recognize([.zero]))
        let ellipse = (0...32).map { i in let a = Double(i) / 32 * 2 * Double.pi; return CGPoint(x: 100 + cos(a) * 80, y: 100 + sin(a) * 50) }
        XCTAssertEqual(ShapeRecognition.recognize(ellipse)?.count, 65)
    }
}
