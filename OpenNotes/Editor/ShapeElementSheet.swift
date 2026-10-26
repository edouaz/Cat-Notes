import SwiftUI

struct ShapeElementSheet: View {
    @ObservedObject var session: EditorSession
    let pageID: UUID
    @State var element: PageElement
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false

    static let kinds: [PageElement.Kind] = [.rectangle, .ellipse, .line, .arrow]
    static func title(_ kind: PageElement.Kind) -> String {
        switch kind {
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .line: return "Line"
        case .arrow: return "Arrow"
        default: return "Shape"
        }
    }
    private var page: NotePage? { session.page.flatMap { $0.id == pageID ? $0 : nil } }
    private var exists: Bool { page?.elements?.contains { $0.id == element.id } == true }

    var body: some View {
        NavigationStack {
            Form {
                Section("Shape") {
                    Picker("Type", selection: $element.kind) {
                        ForEach(Self.kinds, id: \.self) { kind in Text(Self.title(kind)).tag(kind) }
                    }
                    .accessibilityIdentifier("editor.shape.kind")
                }
                Section("Outline") {
                    ColorPicker("Outline color", selection: Binding(get: {
                        Color(element.strokeColorHex.flatMap(UIColor.init(presetHex:)) ?? .black)
                    }, set: { element.strokeColorHex = UIColor($0).presetHex }), supportsOpacity: false)
                    Text("Width · \((element.strokeWidth ?? 2).formatted(.number.precision(.fractionLength(1)))) pt")
                    Slider(value: Binding(get: { element.strokeWidth ?? 2 }, set: { element.strokeWidth = $0 }), in: 0.5...32, step: 0.5)
                        .accessibilityLabel("Outline width")
                }
                if element.kind == .rectangle || element.kind == .ellipse {
                    Section("Fill") {
                        Toggle("Fill shape", isOn: Binding(get: { element.fillColorHex != nil }, set: {
                            element.fillColorHex = $0 ? "#FFF1A8" : nil
                        }))
                        if element.fillColorHex != nil {
                            ColorPicker("Fill color", selection: Binding(get: {
                                Color(element.fillColorHex.flatMap(UIColor.init(presetHex:)) ?? .yellow)
                            }, set: { element.fillColorHex = UIColor($0).presetHex }), supportsOpacity: false)
                        }
                    }
                }
                if let page {
                    Section("Position and size · page points") {
                        Text("X · \(Int(element.x))")
                        Slider(value: $element.x, in: 0...max(0, (page.width ?? 794) - element.width), step: 1)
                            .accessibilityLabel("Shape horizontal position")
                        Text("Y · \(Int(element.y))")
                        Slider(value: $element.y, in: 0...max(0, (page.height ?? 1123) - element.height), step: 1)
                            .accessibilityLabel("Shape vertical position")
                        Text("Width · \(Int(element.width))")
                        Slider(value: $element.width, in: 1...max(1, (page.width ?? 794) - element.x), step: 1)
                            .accessibilityLabel("Shape width")
                        Text("Height · \(Int(element.height))")
                        Slider(value: $element.height, in: 1...max(1, (page.height ?? 1123) - element.y), step: 1)
                            .accessibilityLabel("Shape height")
                    }
                }
                if exists { Button("Delete shape", role: .destructive) { save(removing: true) } }
                if saving { ProgressView("Saving…") }
            }
            .disabled(saving || page == nil)
            .navigationTitle(exists ? "Edit shape" : "Add shape")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(saving || page == nil)
                        .accessibilityIdentifier("editor.shape.save")
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
