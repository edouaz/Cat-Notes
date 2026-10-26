import SwiftUI
import PDFKit

struct PaperSheet: View {
    @ObservedObject var session: EditorSession
    @ObservedObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = "My paper"
    @State private var importer = false
    @State private var pendingPaper: NotePage?
    init(session: EditorSession) { self.session = session; self.store = session.store }
    var body: some View {
        NavigationStack {
            List {
                Section("Page paper") {
                    ForEach(PageTemplate.allCases) { template in
                        Button {
                            guard var page = session.page else { return }
                            page.template = template; page.backgroundID = nil; page.pdfIndex = nil
                            requestPaper(page)
                        } label: {
                            HStack {
                                Text(template.title)
                                Spacer()
                                if session.page?.template == template && session.page?.backgroundID == nil {
                                    Image(systemName: "checkmark").accessibilityHidden(true)
                                }
                            }
                        }.accessibilityAddTraits(session.page?.template == template && session.page?.backgroundID == nil ? .isSelected : [])
                    }
                }
                Section("Create template") {
                    TextField("Template name", text: $name)
                    Button("Save current page background") {
                        guard let page = session.page else { return }
                        store.library.customPapers.append(CustomPaper(name: name, template: page.template, resource: page.backgroundID, pdfIndex: page.pdfIndex, width: page.width, height: page.height))
                        session.store.persist()
                    }
                    Button("Import an image or the first page of a PDF") { importer = true }
                }
                Section("My templates") {
                    ForEach(store.library.customPapers) { paper in
                        Button(paper.name) {
                            guard var page = session.page else { return }
                            page.template = paper.template; page.backgroundID = paper.resource
                            page.pdfIndex = paper.pdfIndex; page.width = paper.width; page.height = paper.height
                            requestPaper(page)
                        }
                    }
                    .onDelete { offsets in store.library.customPapers.remove(atOffsets: offsets); session.store.persist() }
                }
                Text("Applying a background does not transform existing strokes. Import the template before writing if its dimensions differ.").font(.caption)
            }.navigationTitle("Paper templates").toolbar { Button("Close") { dismiss() } }
                .confirmationDialog("Replace this page’s background?", isPresented: Binding(get: { pendingPaper != nil }, set: { if !$0 { pendingPaper = nil } }), titleVisibility: .visible) {
                    Button("Replace background", role: .destructive) {
                        if let pendingPaper { applyPaper(pendingPaper) }
                        pendingPaper = nil
                    }
                    Button("Cancel", role: .cancel) { pendingPaper = nil }
                } message: {
                    Text("The current background or dimensions will be replaced. Strokes and annotations will keep their current positions and sizes.")
                }
                .fileImporter(isPresented: $importer, allowedContentTypes: [.pdf, .image]) { result in Task {
                    do {
                        let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let data = try Data(contentsOf: url, options: .mappedIfSafe)
                        guard data.count < 150_000_000 else { throw CocoaError(.fileReadTooLarge) }
                        let pdf = PDFDocument(data: data)
                        let image = pdf == nil ? UIImage(data: data) : nil
                        guard (pdf?.isLocked == false && pdf?.page(at: 0) != nil) || image != nil else { throw CocoaError(.fileReadCorruptFile) }
                        var size = pdf?.page(at: 0)?.bounds(for: .cropBox).size ?? image!.size
                        if let rotation = pdf?.page(at: 0)?.rotation, abs(rotation) % 180 == 90 { size = CGSize(width: size.height, height: size.width) }
                        let resource = UUID().uuidString + (pdf != nil ? ".pdf" : ".image")
                        try await session.store.disk.write(data, name: resource)
                        store.library.customPapers.append(CustomPaper(name: url.deletingPathExtension().lastPathComponent, template: .blank, resource: resource, pdfIndex: pdf != nil ? 0 : nil, width: size.width, height: size.height))
                        session.store.persist()
                    } catch { session.error = error.localizedDescription }
                } }
        }
    }
    static func requiresConfirmation(from current: NotePage, to updated: NotePage) -> Bool {
        (current.backgroundID != nil && (current.backgroundID != updated.backgroundID || current.pdfIndex != updated.pdfIndex))
            || PageRenderer.size(current) != PageRenderer.size(updated)
    }
    private func requestPaper(_ updated: NotePage) {
        guard let current = session.page else { return }
        if Self.requiresConfirmation(from: current, to: updated) { pendingPaper = updated }
        else { applyPaper(updated) }
    }
    private func applyPaper(_ updated: NotePage) {
        Task {
            await session.refresh(updated)
            if await store.flush(), session.error == nil { dismiss() }
        }
    }
}
