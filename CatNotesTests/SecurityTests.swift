import XCTest
@testable import CatNotes
final class SecurityTests: XCTestCase {
    func testOnlyPublicKeysAccepted() {
        XCTAssertTrue(CloudConfiguration.isPublicKey("sb_publishable_example"))
        XCTAssertFalse(CloudConfiguration.isPublicKey("sb_secret_example"))
        let payload = Data("{\"role\":\"service_role\"}".utf8).base64EncodedString()
        XCTAssertFalse(CloudConfiguration.isPublicKey("header.\(payload).signature"))
        let anon = Data("{\"role\":\"anon\"}".utf8).base64EncodedString()
        XCTAssertTrue(CloudConfiguration.isPublicKey("header.\(anon).signature"))
    }
}
