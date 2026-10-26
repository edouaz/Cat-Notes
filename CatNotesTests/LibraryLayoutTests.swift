import XCTest
import SwiftUI
@testable import CatNotes

@MainActor
final class LibraryLayoutTests: XCTestCase {
    func testTabsShareAvailableWidthAndOverflowWithoutShrinkingControls() {
        for width: CGFloat in [320, 700, 1100] {
            XCTAssertEqual(CatNotesStyle.notebookTabWidth(availableWidth: width, count: 1), width / 2)
        }
        for count in 2...5 {
            let available: CGFloat = 1100
            let width = CatNotesStyle.notebookTabWidth(availableWidth: available, count: count)
            XCTAssertEqual(width * CGFloat(count) + CGFloat(count - 1) * 4, available, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(width, 180)
        }
        let overflow = CatNotesStyle.notebookTabWidth(availableWidth: 700, count: 6)
        XCTAssertEqual(overflow, 180)
        XCTAssertGreaterThan(overflow * 6 + 20, 700)
        XCTAssertEqual(CatNotesStyle.notebookTabWidth(availableWidth: 0, count: 3), 0)
        XCTAssertEqual(CatNotesStyle.notebookTabWidth(availableWidth: 700, count: 0), 0)
    }

    func testMixedLibraryVisualMatrix() async throws {
        let preferences = UserDefaults.standard
        let keys = ["openNotebooks", "activeNotebook", "librarySort"]
        let previous = keys.map { preferences.object(forKey: $0) }
        keys.forEach { preferences.removeObject(forKey: $0) }
        defer { for (key, value) in zip(keys, previous) { preferences.set(value, forKey: key) } }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LibraryStore(root: root)
        await store.load()
        let folderID = try XCTUnwrap(store.library.folders.first?.id)
        _ = store.apply(.init(kind: .createFolder, parentID: folderID, name: "Projets et idées pour le prochain semestre"))
        let titles = ["A", "Notes de lecture et réflexions sur les paysages de mon prochain voyage", "Voyage"]
        for (index, title) in titles.enumerated() {
            let created = await store.create(title: title, folderID: folderID)
            let id = try XCTUnwrap(created)
            store.update(id) { $0.favorite = index == 1; $0.updatedAt = Date(timeIntervalSince1970: 1_792_728_000 - Double(index * 60)) }
            if var page = store.library.firstPage(in: id) {
                page.template = index == 0 ? .grid : .ruled
                store.updatePage(page)
                _ = try await store.disk.thumbnail(page, pixels: 640)
            }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; try? FileManager.default.removeItem(at: root) }
        for (size, type, scheme, name) in [
            (CGSize(width: 744, height: 1133), DynamicTypeSize.large, ColorScheme.light, "Bibliothèque mixte portrait"),
            (CGSize(width: 1133, height: 744), .large, .light, "Bibliothèque mixte paysage"),
            (CGSize(width: 480, height: 900), .large, .light, "Bibliothèque mixte fenêtre étroite"),
            (CGSize(width: 744, height: 1133), .large, .dark, "Bibliothèque mixte sombre"),
            (CGSize(width: 320, height: 900), .accessibility5, .light, "Bibliothèque mixte AX5")
        ] {
            window.frame = CGRect(origin: .zero, size: size)
            let host = UIHostingController(rootView: LibraryScreen().environmentObject(store)
                .environment(\.dynamicTypeSize, type).environment(\.colorScheme, scheme).tint(CatNotesStyle.accent))
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(nanoseconds: 500_000_000)
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            XCTAssertEqual(host.view.bounds.width, size.width, accuracy: 1)
        }
    }
}
