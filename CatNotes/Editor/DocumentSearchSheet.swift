import SwiftUI

struct DocumentSearchSheet: View {
    @ObservedObject var session: EditorSession
    @ObservedObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var indexing = false
    var results: [NotePage] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return store.library.pages(in: session.noteID).filter { $0.searchableText.localizedStandardContains(query) }
    }
    var body: some View {
        NavigationStack {
            List {
                if indexing { ProgressView("Lecture du texte PDF…") }
                ForEach(results) { page in
                    Button {
                        Task {
                            await session.open(page.id)
                            guard session.page?.id == page.id else { return }
                            session.searchHighlights = (page.pdfText?.blocks ?? []).filter { $0.text.localizedStandardContains(query) }.map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
                            dismiss()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Page \(page.index + 1)").font(.headline)
                            Text((page.pdfText?.blocks.first { $0.text.localizedStandardContains(query) }?.text) ?? String(page.searchableText.prefix(180))).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                }
                if results.isEmpty && !query.isEmpty && !indexing { Text("Aucun résultat") }
                Text("La recherche utilise le texte intégré aux PDF et les notes saisies. Les scans et l’écriture manuscrite nécessiteront l’OCR.").font(.footnote).foregroundStyle(.secondary)
            }.searchable(text: $query, prompt: "Texte du document")
                .navigationTitle("Rechercher").toolbar { Button("Fermer") { dismiss() } }
                .task { indexing = true; await store.indexPDFText(in: session.noteID); indexing = false }
        }
    }
}
