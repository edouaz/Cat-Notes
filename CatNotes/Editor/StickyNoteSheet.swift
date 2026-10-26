import SwiftUI

struct StickyNoteSheet: View {
    @ObservedObject var session: EditorSession
    @State var note: PageElement
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    var body: some View {
        NavigationStack {
            Form {
                TextEditor(text: $note.text).frame(minHeight: 180).accessibilityLabel("Texte du post-it")
                Toggle("Replier le post-it", isOn: Binding(get: { note.collapsed == true }, set: { note.collapsed = $0 }))
                if let page = session.page {
                    Section("Taille") {
                        LabeledContent("Largeur", value: "\(Int(note.width)) pt")
                        Slider(value: $note.width, in: 1...max(1, (page.width ?? 794) - note.x), step: 1).accessibilityLabel("Largeur du post-it")
                        LabeledContent("Hauteur", value: "\(Int(note.height)) pt")
                        Slider(value: $note.height, in: 1...max(1, (page.height ?? 1123) - note.y), step: 1).accessibilityLabel("Hauteur du post-it")
                    }
                }
                Button("Supprimer le post-it", role: .destructive) {
                    guard let page = session.page else { return }
                    saving = true
                    Task { let saved = await session.apply(.init(pageID: page.id, kind: .removeElement, elementID: note.id)); saving = false; if saved { dismiss() } }
                }
            }.disabled(saving).navigationTitle("Post-it")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") {
                        guard let page = session.page else { return }
                        saving = true
                        Task { let saved = await session.apply(.init(pageID: page.id, kind: .upsertElement, element: note)); saving = false; if saved { dismiss() } }
                    }.disabled(saving || note.text.count > 100_000) }
                }
        }.interactiveDismissDisabled(saving)
    }
}
