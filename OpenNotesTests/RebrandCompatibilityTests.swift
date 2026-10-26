import XCTest
@testable import OpenNotes

@MainActor
final class RebrandCompatibilityTests: XCTestCase {
    func testNewIdentityKeepsExistingInstallationStorageAndSharing() async {
        let store = LibraryStore()
        let root = await store.disk.root
        XCTAssertEqual(root.lastPathComponent, "CatNotes")
        XCTAssertEqual(Bundle.main.bundleIdentifier, "fr.catnotes.app")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "OpenNotes")
        XCTAssertEqual(ShareInbox.group, "group.fr.catnotes.app")
        let types = Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]]
        XCTAssertEqual(types?.first?["UTTypeIdentifier"] as? String, "fr.catnotes.notebook")
    }
}
