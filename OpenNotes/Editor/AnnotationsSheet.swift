import SwiftUI

struct AnnotationsSheet: View {
    @ObservedObject var session: EditorSession
    let editNote: (PageElement) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(session.page?.elements ?? []) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(title(item.kind)).font(.headline)
                            if item.kind == .stickyNote || item.kind == .text { Text(item.text).lineLimit(3).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if item.kind == .stickyNote {
                            Button("Edit") { dismiss(); editNote(item) }
                        }
                        Button(role: .destructive) {
                            guard let page = session.page else { return }
                            Task { await session.apply(.init(pageID: page.id, kind: .removeElement, elementID: item.id)) }
                        } label: { Image(systemName: "trash").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Delete this annotation")
                    }.buttonStyle(.borderless)
                }
                if session.page?.elements?.isEmpty != false { Text("No annotations on this page") }
            }.navigationTitle("Annotations").toolbar { Button("Close") { dismiss() } }
        }
    }
    private func title(_ kind: PageElement.Kind) -> String {
        switch kind {
        case .stickyNote: return "Sticky note"
        case .highlight: return "Highlight"
        case .rectangle: return "Frame"
        case .image: return "Image"
        case .text: return "Text"
        default: return "Shape"
        }
    }
}
