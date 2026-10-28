import Foundation
import UIKit

struct NotebookArchive: Codable, Sendable {
    var version = 2
    var note: NoteDocument
    var pages: [NotePage]
    var resources: [String: Data]

    func validate() throws {
        guard (1...2).contains(version), !pages.isEmpty, pages.count <= 10000,
              Set(pages.map(\.id)).count == pages.count,
              note.pageIDs == pages.map(\.id), pages.allSatisfy({ $0.noteID == note.id }),
              resources.keys.allSatisfy(Self.safeResource),
              pages.allSatisfy({ Self.validText($0.pdfText) && Self.validText($0.ocrText) && resources[$0.drawingResourceID] != nil &&
                  ($0.backgroundID == nil || resources[$0.backgroundID!] != nil) &&
                  ($0.width ?? 794) > 0 && ($0.width ?? 794) <= 20000 &&
                  ($0.elements ?? []).allSatisfy { item in
                      item.x.isFinite && item.y.isFinite && item.width > 0 && item.width <= 20000 && item.height > 0 && item.height <= 20000 &&
                      (item.kind != .image || item.resource.flatMap { resources[$0] } != nil)
                  } &&
                  ($0.height ?? 1123) > 0 && ($0.height ?? 1123) <= 20000 }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
    static func validText(_ content: PageTextContent?) -> Bool {
        guard let content else { return true }
        return content.text.count <= 5_000_000 && content.blocks.count <= 100_000 && content.blocks.allSatisfy { block in
            block.x.isFinite && block.y.isFinite && block.width.isFinite && block.height.isFinite &&
            block.width > 0 && block.height > 0 && block.width <= 20000 && block.height <= 20000 &&
            abs(block.x) <= 20000 && abs(block.y) <= 20000 &&
            (block.confidence == nil || (block.confidence!.isFinite && (0...1).contains(block.confidence!)))
        }
    }
    static func safeResource(_ name: String) -> Bool {
        !name.isEmpty && name.count < 128 && name != "." && name != ".." &&
        name.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_ ")).contains($0) }
    }
}

actor DiskStore {
    private var renderingThumbnail = false
    private var thumbnailWaiters: [CheckedContinuation<Void, Never>] = []
    private func acquireThumbnailRenderer() async {
        if renderingThumbnail { await withCheckedContinuation { thumbnailWaiters.append($0) } }
        else { renderingThumbnail = true }
    }
    private func releaseThumbnailRenderer() {
        if thumbnailWaiters.isEmpty { renderingThumbnail = false }
        else { thumbnailWaiters.removeFirst().resume() }
    }
    private var thumbnails: [Data: UIImage] = [:]
    private var resourceGeneration: [String: Int] = [:]
    private var thumbnailOrder: [Data] = []
    private var thumbnailBytes = 0
    let root: URL
    init(root: URL) { self.root = root }
    func thumbnail(_ page: NotePage, pixels requestedPixels: Int = 160) async throws -> UIImage {
        let pixels = min(1600, max(80, requestedPixels))
        await acquireThumbnailRenderer()
        defer { releaseThumbnailRenderer() }
        try Task.checkCancellation()
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        var key = try encoder.encode(page)
        let names = Set([page.drawingResourceID] + [page.backgroundID].compactMap { $0 } + (page.elements ?? []).compactMap(\.resource)).sorted()
        let generations = names.map { resourceGeneration[$0, default: 0] }
        key.append(try encoder.encode(generations)); key.append(Data("pixels:\(pixels)".utf8))
        if let cached = thumbnails[key] { return cached }
        let drawing = try read(page.drawingResourceID)
        var resources: [String: Data] = [:]
        for item in page.elements ?? [] { if let name = item.resource { resources[name] = try read(name) } }
        let background = try page.backgroundID.flatMap { try read($0) }
        let work = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let rendered = PageRenderer.image(page, data: background, drawing: try drawing.map(InkDrawing.init(data:)), resources: resources, scale: CGFloat(pixels) / max(PageRenderer.size(page).width, PageRenderer.size(page).height))
            guard let pixels = rendered.cgImage else { throw CocoaError(.fileReadCorruptFile) }
            // iOS 16 CoreUI rejects sub-1x UIImage scales when SwiftUI registers an image asset.
            return UIImage(cgImage: pixels, scale: 1, orientation: .up)
        }
        let image = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
        try Task.checkCancellation()
        guard generations == names.map({ resourceGeneration[$0, default: 0] }) else { return image }
        let bytes = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
        while thumbnailBytes + bytes > 16_000_000, !thumbnailOrder.isEmpty {
            let oldest = thumbnailOrder.removeFirst()
            if let removed = thumbnails.removeValue(forKey: oldest) { thumbnailBytes -= (removed.cgImage?.bytesPerRow ?? 0) * (removed.cgImage?.height ?? 0) }
        }
        if let cached = thumbnails[key] { return cached }
        if bytes <= 16_000_000 { thumbnails[key] = image; thumbnailOrder.append(key); thumbnailBytes += bytes }
        return image
    }
    func clearThumbnails() { thumbnails.removeAll(); thumbnailOrder.removeAll(); thumbnailBytes = 0 }
    func load() throws -> NoteLibrarySnapshot {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("library.json")
        if !FileManager.default.fileExists(atPath: url.path) {
            return NoteLibrarySnapshot(folders: [NotebookFolder(name: "My notebooks")])
        }
        // Never replace a corrupt library with an empty one.
        let library = try JSONDecoder().decode(NoteLibrarySnapshot.self, from: Data(contentsOf: url))
        try validate(library); return library
    }
    func validate(_ library: NoteLibrarySnapshot) throws {
        guard library.schemaVersion == 1, !library.folders.isEmpty,
              Set(library.notes.map(\.id)).count == library.notes.count,
              Set(library.pages.map(\.id)).count == library.pages.count,
              !library.containsFolderCycle(),
              library.notes.allSatisfy({ note in
                  !note.pageIDs.isEmpty && note.pageIDs == library.pages(in: note.id).map(\.id) &&
                  Set(note.pageIDs).count == note.pageIDs.count && library.folder(id: note.folderID) != nil
              }),
              library.pages.allSatisfy({ NotebookArchive.validText($0.pdfText) && NotebookArchive.validText($0.ocrText) && NotebookArchive.safeResource($0.drawingResourceID) && ($0.backgroundID == nil || NotebookArchive.safeResource($0.backgroundID!)) }) else { throw CocoaError(.fileReadCorruptFile) }
    }
    func save(_ library: NoteLibrarySnapshot) throws {
        try validate(library)
        let url = root.appendingPathComponent("library.json")
        if let old = try? Data(contentsOf: url) {
            _ = try JSONDecoder().decode(NoteLibrarySnapshot.self, from: old)
            try old.write(to: root.appendingPathComponent("library.backup.json"), options: .atomic)
        }
        try JSONEncoder().encode(library).write(to: url, options: .atomic)
    }
    func restoreBackup() throws -> NoteLibrarySnapshot {
        let data = try Data(contentsOf: root.appendingPathComponent("library.backup.json"))
        let library = try JSONDecoder().decode(NoteLibrarySnapshot.self, from: data)
        try validate(library)
        try data.write(to: root.appendingPathComponent("library.json"), options: .atomic)
        return library
    }
    func read(_ name: String) throws -> Data? {
        guard NotebookArchive.safeResource(name) else { throw CocoaError(.fileReadInvalidFileName) }
        let url = root.appendingPathComponent("resources").appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
    func write(_ data: Data, name: String) throws {
        guard NotebookArchive.safeResource(name) else { throw CocoaError(.fileWriteInvalidFileName) }
        let folder = root.appendingPathComponent("resources")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        resourceGeneration[name, default: 0] += 1
    }
    func archive(note: NoteDocument, pages: [NotePage]) throws -> NotebookArchive {
        var resources: [String: Data] = [:]
        for page in pages {
            guard let drawing = try read(page.drawingResourceID) else { throw CocoaError(.fileNoSuchFile) }
            resources[page.drawingResourceID] = drawing
            for element in page.elements ?? [] {
                if let name = element.resource, resources[name] == nil {
                    guard let data = try read(name) else { throw CocoaError(.fileNoSuchFile) }
                    resources[name] = data
                }
            }
            if let name = page.backgroundID, resources[name] == nil {
                guard let data = try read(name) else { throw CocoaError(.fileNoSuchFile) }
                resources[name] = data
            }
        }
        let archive = NotebookArchive(note: note, pages: pages, resources: resources)
        try archive.validate()
        return archive
    }
}
