import SwiftUI

struct StickyNoteSheet: View {
    @ObservedObject var session: EditorSession
    @State var note: PageElement
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @StateObject private var formatting = RichTextFormatting()
    @State private var fontSize = 16.0
    @State private var textColor = Color.black
    @State private var backgroundColor = Color.yellow
    @State private var family = "Helvetica"
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    StickyRichTextEditor(item: $note, formatting: formatting)
                        .frame(minHeight: 220)
                        .listRowBackground(Color(UIColor(presetHex: note.fillColorHex ?? "#FFEB80") ?? .systemYellow))
                    HStack {
                        Button("Bold") { formatting.trait(.traitBold) }.fontWeight(.bold)
                        Button("Italic") { formatting.trait(.traitItalic) }.italic()
                        Button("Underline") { formatting.toggle(.underlineStyle) }.underline()
                        Button("Strike") { formatting.toggle(.strikethroughStyle) }.strikethrough()
                    }.buttonStyle(.borderless)
                    Picker("Font", selection: $family) {
                        ForEach(["Helvetica", "Georgia", "Courier"], id: \.self) { Text($0) }
                    }.onChange(of: family) { formatting.font($0) }
                    Stepper("Font size: \(Int(fontSize))", value: $fontSize, in: 8...96)
                        .onChange(of: fontSize) { formatting.font(size: $0) }
                    ColorPicker("Text color", selection: $textColor, supportsOpacity: false)
                        .onChange(of: textColor) { formatting.color(UIColor($0)) }
                    HStack {
                        Button { formatting.align(.left) } label: { Image(systemName: "text.alignleft") }.accessibilityLabel("Align left")
                        Button { formatting.align(.center) } label: { Image(systemName: "text.aligncenter") }.accessibilityLabel("Align center")
                        Button { formatting.align(.right) } label: { Image(systemName: "text.alignright") }.accessibilityLabel("Align right")
                        Button("Bullets") { formatting.list(numbered: false) }
                        Button("Numbered") { formatting.list(numbered: true) }
                    }.buttonStyle(.borderless)
                } header: { Text("Text formatting applies to the selected range") }
                    .disabled(note.isLocked == true)
                ColorPicker("Note background", selection: $backgroundColor, supportsOpacity: false)
                    .onChange(of: backgroundColor) { note.fillColorHex = UIColor($0).presetHex }
                    .disabled(note.isLocked == true)
                Toggle("Lock sticky note", isOn: Binding(get: { note.isLocked == true }, set: { note.isLocked = $0 }))
                LabeledContent("Rotation", value: "\(Int((note.rotation ?? 0) * 180 / .pi))°")
                Slider(value: Binding(get: { (note.rotation ?? 0) * 180 / .pi }, set: { note.rotation = $0 * .pi / 180 }), in: -180...180)
                    .accessibilityLabel("Sticky note rotation").disabled(note.isLocked == true)
                Toggle("Collapse sticky note", isOn: Binding(get: { note.collapsed == true }, set: { note.collapsed = $0 })).disabled(note.isLocked == true)
                if let page = session.page {
                    Section("Size") {
                        LabeledContent("Width", value: "\(Int(note.width)) pt")
                        Slider(value: $note.width, in: 1...max(1, (page.width ?? 794) - note.x), step: 1).accessibilityLabel("Sticky note width")
                        LabeledContent("Height", value: "\(Int(note.height)) pt")
                        Slider(value: $note.height, in: 1...max(1, (page.height ?? 1123) - note.y), step: 1).accessibilityLabel("Sticky note height")
                    }.disabled(note.isLocked == true)
                }
                Button("Delete sticky note", role: .destructive) {
                    guard let page = session.page else { return }
                    saving = true
                    Task { let saved = await session.apply(.init(pageID: page.id, kind: .removeElement, elementID: note.id)); saving = false; if saved { dismiss() } }
                }
                .disabled(note.isLocked == true)
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
            .onAppear {
                backgroundColor = Color(UIColor(presetHex: note.fillColorHex ?? "#FFEB80") ?? .systemYellow)
                fontSize = note.textFontSize ?? 16
                textColor = Color(note.textColorHex.flatMap(UIColor.init(presetHex:)) ?? .black)
            }
    }
}
