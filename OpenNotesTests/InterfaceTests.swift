import XCTest
import SwiftUI
import PencilKit
@testable import OpenNotes

@MainActor
final class InterfaceTests: XCTestCase {
    func testLibraryAndEditorLayouts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LibraryStore(root: root)
        await store.load()
        let created = await store.create()
        let id = try XCTUnwrap(created)
        store.update(id) { $0.title = "My ideas today"; $0.favorite = true }
        if var page = store.library.firstPage(in: id) { page.template = .grid; store.updatePage(page) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = UIScreen.main.bounds
        defer { window.endEditing(true); window.isHidden = true; window.rootViewController = nil }

        let library = UIHostingController(rootView: LibraryScreen().environmentObject(store))
        window.rootViewController = library
        window.makeKeyAndVisible()
        try await Task.sleep(nanoseconds: 400_000_000)
        capture(library.view, name: "Library")

        let editor = UIHostingController(rootView: EditorScreen(store: store, noteID: id))
        window.rootViewController = editor
        for _ in 0..<100 {
            editor.view.layoutIfNeeded()
            if findCanvas(editor.view) != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        capture(editor.view, name: "Editor before verification")
        let canvas = try XCTUnwrap(findCanvas(editor.view))
        let frame = canvas.convert(canvas.bounds, to: editor.view)
        XCTAssertGreaterThan(frame.height, 150, "Toolbars must leave usable space for writing")
        XCTAssertGreaterThan(frame.width, 200)
        XCTAssertGreaterThanOrEqual(frame.minY, 0)
        XCTAssertLessThanOrEqual(frame.maxY, editor.view.bounds.maxY + 1)
        capture(editor.view, name: "Editor")

        let largeType = UIHostingController(rootView: LibraryScreen().environmentObject(store).environment(\.dynamicTypeSize, .accessibility3))
        window.rootViewController = largeType
        try await Task.sleep(nanoseconds: 400_000_000)
        capture(largeType.view, name: "Large-text library")
        let darkLibrary = UIHostingController(rootView: LibraryScreen().environmentObject(store).environment(\.colorScheme, .dark))
        window.rootViewController = darkLibrary
        try await Task.sleep(nanoseconds: 400_000_000)
        capture(darkLibrary.view, name: "Dark library")
    }
    func testWorkspaceVisualMatrix() async throws {
        let preferences = UserDefaults.standard
        let keys = ["openNotebooks", "activeNotebook", "nativeTools", "inkTool"]
        let previous = keys.map { preferences.object(forKey: $0) }
        for key in keys { preferences.removeObject(forKey: key) }
        preferences.set(false, forKey: "nativeTools")
        defer { for (key, value) in zip(keys, previous) { preferences.set(value, forKey: key) } }
        let store = LibraryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        await store.load()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = UIScreen.main.bounds
        defer { window.endEditing(true); window.isHidden = true; window.rootViewController = nil }
        let empty = UIHostingController(rootView: LibraryScreen().environmentObject(store).tint(OpenNotesStyle.accent))
        window.rootViewController = empty; window.makeKeyAndVisible()
        try await Task.sleep(nanoseconds: 500_000_000)
        capture(empty.view, name: "Empty library")
        let first = await store.create(title: "Travel notebook")
        let second = await store.create(title: "My ideas today")
        let a = try XCTUnwrap(first), b = try XCTUnwrap(second)
        for id in [a, b] {
            if var page = store.library.firstPage(in: id) { page.template = .grid; store.updatePage(page) }
        }
        for page in store.library.pages { _ = try await store.disk.thumbnail(page, pixels: 640) }
        try await Task.sleep(nanoseconds: 800_000_000)
        capture(empty.view, name: "Populated library")
        let workspace = NotebookWorkspace(store: store)
        await workspace.select(a); await workspace.select(b)
        let session = workspace.session(b)
        await session.open()
        let host = UIHostingController(rootView: NotebookWorkspaceView(workspace: workspace).tint(OpenNotesStyle.accent))
        window.rootViewController = host
        for _ in 0..<100 {
            if !session.busy, findCanvas(host.view) != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        for tool in [DrawingToolKind.pen, .eraser, .lasso] {
            session.selectedTool = tool
            try await Task.sleep(nanoseconds: 600_000_000)
            host.view.layoutIfNeeded()
            let canvas = try XCTUnwrap(findCanvas(host.view))
            XCTAssertGreaterThan(canvas.bounds.height, 150)
            capture(host.view, name: "Workspace \(tool.rawValue)")
        }
        UserDefaults.standard.removeObject(forKey: "openNotebooks")
        UserDefaults.standard.removeObject(forKey: "activeNotebook")
        let large = UIHostingController(rootView: LibraryScreen().environmentObject(store).environment(\.dynamicTypeSize, .accessibility3).tint(OpenNotesStyle.accent))
        window.rootViewController = large
        try await Task.sleep(nanoseconds: 600_000_000)
        capture(large.view, name: "Accessible library")
        let dark = UIHostingController(rootView: LibraryScreen().environmentObject(store).environment(\.colorScheme, .dark).tint(OpenNotesStyle.accent))
        window.rootViewController = dark
        try await Task.sleep(nanoseconds: 800_000_000)
        capture(dark.view, name: "Dark library")
        window.rootViewController = host
        let portraitSize = window.bounds.size
        window.frame = CGRect(origin: .zero, size: CGSize(width: max(portraitSize.width, portraitSize.height), height: min(portraitSize.width, portraitSize.height)))
        host.view.frame = window.bounds; host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 800_000_000)
        capture(host.view, name: "Workspace landscape window")
        window.frame = CGRect(origin: .zero, size: CGSize(width: min(portraitSize.width, portraitSize.height), height: max(portraitSize.width, portraitSize.height)))
        host.view.frame = window.bounds
    }
    func testDiagnosticScreenAndSharingSheet() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = UIScreen.main.bounds
        defer { window.endEditing(true); window.isHidden = true; window.rootViewController = nil }
        let screen = UIHostingController(rootView: DiagnosticsScreen().tint(OpenNotesStyle.accent))
        window.rootViewController = screen; window.makeKeyAndVisible()
        try await Task.sleep(nanoseconds: 400_000_000)
        capture(screen.view, name: "Diagnostic mode")
        let log = Diagnostics(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        log.record("share.test")
        let url = try await log.export(metadata: ["build": "4"])
        let sheet = UIHostingController(rootView: Text("Diagnostic").sheet(isPresented: .constant(true)) { ActivitySheet(url: url) })
        window.rootViewController = sheet
        for _ in 0..<100 {
            if sheet.presentedViewController != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNotNil(sheet.presentedViewController, "The report must open the system share sheet on iPad")
        sheet.dismiss(animated: false)
    }
    func testSmallWindowsAndLargestText() async throws {
        let preferences = UserDefaults.standard
        let keys = ["openNotebooks", "activeNotebook"]
        let previous = keys.map { preferences.object(forKey: $0) }
        for key in keys { preferences.removeObject(forKey: key) }
        defer { for (key, value) in zip(keys, previous) { preferences.set(value, forKey: key) } }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LibraryStore(root: root); await store.load()
        _ = await store.create(title: "Ideas and plans for my next family trip")
        _ = await store.create(title: "My reading notes")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; try? FileManager.default.removeItem(at: root) }
        for size in [CGSize(width: 320, height: 900), CGSize(width: 744, height: 900), CGSize(width: 768, height: 1024)] {
            let width = size.width
            window.frame = CGRect(origin: .zero, size: size)
            let library = UIHostingController(rootView: LibraryScreen().environmentObject(store)
                .environment(\.dynamicTypeSize, .accessibility5).tint(OpenNotesStyle.accent))
            window.rootViewController = library; window.makeKeyAndVisible()
            try await Task.sleep(nanoseconds: 600_000_000)
            capture(library.view, name: "AX5 library width \(Int(width))")
            let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 220)).image { context in
                UIColor.systemBackground.setFill(); context.fill(CGRect(x: 0, y: 0, width: 320, height: 220))
                ("An idea to keep" as NSString).draw(at: CGPoint(x: 20, y: 40), withAttributes: [.font: UIFont.preferredFont(forTextStyle: .title2)])
            }
            let captureSheet = UIHostingController(rootView: CaptureSheet(image: image, insert: {})
                .environment(\.dynamicTypeSize, .accessibility5).tint(OpenNotesStyle.accent))
            window.rootViewController = captureSheet
            try await Task.sleep(nanoseconds: 600_000_000)
            capture(captureSheet.view, name: "AX5 capture width \(Int(width))")
        }
    }
    private func findCanvas(_ view: UIView) -> PKCanvasView? {
        if let canvas = view as? PKCanvasView { return canvas }
        return view.subviews.lazy.compactMap { self.findCanvas($0) }.first
    }
    private func capture(_ view: UIView, name: String) {
        view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { context in view.drawHierarchy(in: view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
