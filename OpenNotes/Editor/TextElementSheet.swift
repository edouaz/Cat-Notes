import SwiftUI

struct TextElementSheet: View {
    @ObservedObject var session: EditorSession
    let pageID: UUID
    @State var element: PageElement
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false

    private var page: NotePage? { session.page.flatMap { $0.id == pageID ? $0 : nil } }
    private var exists: Bool { page?.elements?.contains { $0.id == element.id } == true }

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    TextEditor(text: $element.text)
                        .frame(minHeight: 180)
                        .accessibilityLabel("Text box content")
                        .accessibilityIdentifier("editor.text.content")
                    Text("Text is saved in the page and included in exports. Move and resize its box below.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Style") {
                    ColorPicker("Text color", selection: Binding(get: {
                        Color(element.textColorHex.flatMap(UIColor.init(presetHex:)) ?? .black)
                    }, set: { element.textColorHex = UIColor($0).presetHex }), supportsOpacity: false)
                    Text("Size · \(Int(element.textFontSize ?? 20)) pt")
                    Slider(value: Binding(get: { element.textFontSize ?? 20 }, set: { element.textFontSize = $0 }), in: 8...96, step: 1)
                        .accessibilityLabel("Text size")
                }
                if let page {
                    Section("Position and size · page points") {
                        Text("X · \(Int(element.x))")
                        Slider(value: $element.x, in: 0...max(0, (page.width ?? 794) - element.width), step: 1)
                            .accessibilityLabel("Text horizontal position")
                        Text("Y · \(Int(element.y))")
                        Slider(value: $element.y, in: 0...max(0, (page.height ?? 1123) - element.height), step: 1)
                            .accessibilityLabel("Text vertical position")
                        Text("Width · \(Int(element.width))")
                        Slider(value: $element.width, in: 1...max(1, (page.width ?? 794) - element.x), step: 1)
                            .accessibilityLabel("Text box width")
                        Text("Height · \(Int(element.height))")
                        Slider(value: $element.height, in: 1...max(1, (page.height ?? 1123) - element.y), step: 1)
                            .accessibilityLabel("Text box height")
                    }
                }
                if exists {
                    Button("Delete text", role: .destructive) { save(removing: true) }
                }
                if saving { ProgressView("Saving…") }
            }
            .disabled(saving || page == nil)
            .navigationTitle(exists ? "Edit text" : "Add text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(saving || page == nil || element.text.isEmpty || element.text.count > 100_000)
                        .accessibilityIdentifier("editor.text.save")
                }
            }
        }
        .interactiveDismissDisabled(saving)
    }

    private func save(removing: Bool = false) {
        guard !saving, page != nil else { return }
        saving = true
        Task {
            let saved = await session.apply(.init(pageID: pageID, kind: removing ? .removeElement : .upsertElement,
                                                  element: removing ? nil : element, elementID: removing ? element.id : nil))
            saving = false
            if saved { dismiss() }
        }
    }
}
