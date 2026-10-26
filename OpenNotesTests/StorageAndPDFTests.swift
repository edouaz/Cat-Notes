import XCTest
import PencilKit
import PDFKit
@testable import OpenNotes

@MainActor
final class StorageAndPDFTests: XCTestCase {
    func makeStore() async -> LibraryStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LibraryStore(root: root); await store.load(); return store
    }
    func testNotebookPersistsTrashRecoveryAndDuplicate() async throws {
        let store = await makeStore()
        let created = await store.create()
        let id = try XCTUnwrap(created)
        let first = try XCTUnwrap(store.library.firstPage(in: id))
        let duplicate = await store.addPage(noteID: id, after: first.id, duplicate: true)
        XCTAssertNotNil(duplicate)
        store.update(id) { $0.title = "Course"; $0.deletedAt = Date() }
        await store.flush()
        let saved = try await store.disk.load()
        XCTAssertEqual(saved.note(id: id)?.title, "Course")
        XCTAssertNotNil(saved.note(id: id)?.deletedAt)
        XCTAssertEqual(saved.pages(in: id).count, 2)
        store.update(id) { $0.deletedAt = nil }; await store.flush()
        let recovered = try await store.disk.load()
        XCTAssertNil(recovered.note(id: id)?.deletedAt)
    }
    func testPDFSourcePreservedAndAnnotatedExport() async throws {
        let store = await makeStore()
        let input = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 700)
        try UIGraphicsPDFRenderer(bounds: bounds).writePDF(to: input) { ctx in
            ctx.beginPage(); ("Searchable original" as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
            ctx.beginPage()
        }
        let original = try Data(contentsOf: input)
        let imported = await store.importFile(input)
        let id = try XCTUnwrap(imported)
        let page = try XCTUnwrap(store.library.firstPage(in: id))
        XCTAssertEqual(page.pdfText?.source, .pdf)
        XCTAssertTrue(page.pdfText?.text.contains("Searchable original") == true)
        XCTAssertNil(page.recognizedText)
        XCTAssertTrue(store.matchingNotes("Searchable original").contains { $0.id == id })
        let previousDate = store.library.note(id: id)?.updatedAt
        let position = try XCTUnwrap(store.library.pages.firstIndex { $0.id == page.id })
        store.library.pages[position].pdfText = nil
        await store.indexPDFText(in: id)
        XCTAssertEqual(store.library.note(id: id)?.updatedAt, previousDate, "Indexing a PDF must not move the notebook in recents")
        XCTAssertTrue(store.library.page(id: page.id)?.pdfText?.text.contains("Searchable original") == true)
        let source = try await store.disk.read(try XCTUnwrap(page.backgroundID))
        XCTAssertEqual(source, original)
        let points = [CGPoint(x: 50, y: 100), CGPoint(x: 400, y: 300)].enumerated().map { i, p in
            PKStrokePoint(location: p, timeOffset: Double(i), size: CGSize(width: 8, height: 8), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let stroke = PKStroke(ink: PKInk(.pen, color: .red), path: PKStrokePath(controlPoints: points, creationDate: Date()))
        let drawing = PKDrawing(strokes: [stroke])
        try await store.disk.write(drawing.dataRepresentation(), name: page.drawingResourceID)
        let archive = try await store.archive(id)
        let output = input.deletingPathExtension().appendingPathExtension("export.pdf")
        try PageRenderer.export(archive, indices: 0...0, output: output)
        let pdf = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(pdf.pageCount, 1)
        XCTAssertTrue(pdf.string?.contains("Searchable original") == true)
        let exported = try XCTUnwrap(pdf.page(at: 0)?.thumbnail(of: CGSize(width: 500, height: 700), for: .mediaBox).pngData())
        let blank = PageRenderer.image(page, data: original).pngData()
        XCTAssertNotEqual(exported, blank)
        let persisted = try await store.disk.read(page.drawingResourceID)
        XCTAssertEqual(try PKDrawing(data: XCTUnwrap(persisted)).strokes.count, 1)
        let roundtrip = try JSONDecoder().decode(NotebookArchive.self, from: CloudSync.encode(archive))
        let copy = try await store.importArchive(roundtrip)
        XCTAssertNotEqual(id, copy)
        XCTAssertEqual(store.library.pages(in: copy).count, 2)
    }
    func testCorruptLibraryIsNotSilentlyReset() async throws {
        let store = await makeStore()
        _ = await store.create(); await store.flush()
        let root = await store.disk.root
        let url = root.appendingPathComponent("library.json")
        let corrupt = Data("broken".utf8)
        try corrupt.write(to: url)
        do { _ = try await store.disk.load(); XCTFail("Corrupt data accepted") } catch { }
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
        do { try await store.disk.write(Data(), name: "../escape"); XCTFail("Path traversal accepted") } catch { }
    }
    func testAutosaveFlushAndReadOnlyPolicy() async throws {
        let store = await makeStore()
        let created = await store.create()
        let id = try XCTUnwrap(created)
        let editor = EditorSession(store: store, noteID: id)
        await editor.open()
        editor.changed(PKDrawing())
        XCTAssertTrue(editor.dirty)
        let flushed = await editor.flush()
        XCTAssertTrue(flushed)
        XCTAssertFalse(editor.dirty)
        let archive = try await store.archive(id)
        XCTAssertNoThrow(try archive.validate())
        var malicious = archive; malicious.resources["../secret"] = Data()
        XCTAssertThrowsError(try malicious.validate())
    }
    func testImageElementsSearchAndCustomPaperPersistence() async throws {
        let store = await makeStore()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 200)).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
        }
        let data = try XCTUnwrap(image.pngData())
        let input = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try data.write(to: input)
        let imported = await store.importFile(input)
        let id = try XCTUnwrap(imported)
        var page = try XCTUnwrap(store.library.firstPage(in: id))
        page.elements = [PageElement(kind: .text, text: "Botanique"), PageElement(kind: .image, resource: page.backgroundID)]
        page.recognizedText = "Extracted PDF text"
        store.updatePage(page)
        store.update(id) { $0.favorite = true; $0.title = "Course" }
        store.library.customPapers.append(CustomPaper(name: "My paper", template: .blank, resource: page.backgroundID, pdfIndex: nil, width: 320, height: 200))
        store.persist(); await store.flush()
        XCTAssertEqual(store.matchingNotes("botanique").map(\.id), [id])
        XCTAssertEqual(store.matchingNotes("Extracted PDF").map(\.id), [id])
        XCTAssertEqual(store.matchingNotes("course", favorites: true).map(\.id), [id])
        let archive = try await store.archive(id)
        XCTAssertEqual(archive.resources[try XCTUnwrap(page.backgroundID)], data)
        let restored = try await store.disk.load()
        XCTAssertEqual(restored.customPapers.count, 1)
        let copy = try await store.importArchive(archive)
        let copied = try XCTUnwrap(store.library.firstPage(in: copy))
        XCTAssertEqual(copied.elements?.count, 2)
        XCTAssertNotEqual(copied.backgroundID, page.backgroundID)
        let copiedArchive = try await store.archive(copy)
        XCTAssertNoThrow(try copiedArchive.validate())
    }
    func testChecksumsDeterministicAndConflictCopiesPreserveOriginal() async throws {
        let store = await makeStore()
        let created = await store.create(title: "Local")
        let id = try XCTUnwrap(created)
        let archive = try await store.archive(id)
        XCTAssertEqual(try CloudSync.encode(archive), try CloudSync.encode(archive))
        var remote = archive; remote.note.title = "Remote conflict"
        let copy = try await store.importArchive(remote)
        XCTAssertEqual(store.library.note(id: id)?.title, "Local")
        XCTAssertEqual(store.library.note(id: copy)?.title, "Remote conflict")
        store.cloud.resolve(SyncConflict(localID: id, remoteCopyID: copy), keep: 1)
        XCTAssertNil(store.library.note(id: id)?.deletedAt)
        XCTAssertNotNil(store.library.note(id: copy)?.deletedAt)
        XCTAssertNotEqual(CloudSync.checksum(try CloudSync.encode(archive)), CloudSync.checksum(try CloudSync.encode(remote)))
    }
}
