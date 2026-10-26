import SwiftUI

struct StickyNoteSheet: View {
    @ObservedObject var session: EditorSession
    @State var note: PageElement
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    var body: some View {
        NavigationStack {
            Form {
                TextEditor(text: $note.text).frame(minHeight: 180).accessibilityLabel("Sticky note text")
                Toggle("Collapse sticky note", isOn: Binding(get: { note.collapsed == true }, set: { note.collapsed = $0 }))
                if let page = session.page {
                    Section("Size") {
                        LabeledContent("Width", value: "\(Int(note.width)) pt")
                        Slider(value: $note.width, in: 1...max(1, (page.width ?? 794) - note.x), step: 1).accessibilityLabel("Sticky note width")
                        LabeledContent("Height", value: "\(Int(note.height)) pt")
                        Slider(value: $note.height, in: 1...max(1, (page.height ?? 1123) - note.y), step: 1).accessibilityLabel("Sticky note height")
                    }
                }
                Button("Delete sticky note", role: .destructive) {
                    guard let page = session.page else { return }
                    saving = true
                    Task { let saved = await session.apply(.init(pageID: page.id, kind: .removeElement, elementID: note.id)); saving = false; if saved { dismiss() } }
                }
            }.disabled(saving).navigationTitle("Sticky note")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        guard let page = session.page else { return }
                        saving = true
                        Task { let saved = await session.apply(.init(pageID: page.id, kind: .upsertElement, element: note)); saving = false; if saved { dismiss() } }
                    }.disabled(saving || note.text.count > 100_000) }
                }
        }.interactiveDismissDisabled(saving)
    }
}
