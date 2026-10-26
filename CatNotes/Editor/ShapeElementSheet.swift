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
        case .line: return "Ligne"
        case .arrow: return "Flèche"
        default: return "Forme"
        }
    }
    private var page: NotePage? { session.page.flatMap { $0.id == pageID ? $0 : nil } }
    private var exists: Bool { page?.elements?.contains { $0.id == element.id } == true }

    var body: some View {
        NavigationStack {
            Form {
                Section("Forme") {
                    Picker("Type", selection: $element.kind) {
                        ForEach(Self.kinds, id: \.self) { kind in Text(Self.title(kind)).tag(kind) }
                    }
                    .accessibilityIdentifier("editor.shape.kind")
                }
                Section("Contour") {
                    ColorPicker("Couleur du contour", selection: Binding(get: {
                        Color(element.strokeColorHex.flatMap(UIColor.init(presetHex:)) ?? .black)
                    }, set: { element.strokeColorHex = UIColor($0).presetHex }), supportsOpacity: false)
                    Text("Épaisseur · \((element.strokeWidth ?? 2).formatted(.number.precision(.fractionLength(1)))) pt")
                    Slider(value: Binding(get: { element.strokeWidth ?? 2 }, set: { element.strokeWidth = $0 }), in: 0.5...32, step: 0.5)
                        .accessibilityLabel("Épaisseur du contour")
                }
                if element.kind == .rectangle || element.kind == .ellipse {
                    Section("Remplissage") {
                        Toggle("Remplir la forme", isOn: Binding(get: { element.fillColorHex != nil }, set: {
                            element.fillColorHex = $0 ? "#FFF1A8" : nil
                        }))
                        if element.fillColorHex != nil {
                            ColorPicker("Couleur du remplissage", selection: Binding(get: {
                                Color(element.fillColorHex.flatMap(UIColor.init(presetHex:)) ?? .yellow)
                            }, set: { element.fillColorHex = UIColor($0).presetHex }), supportsOpacity: false)
                        }
                    }
                }
                if let page {
                    Section("Position et taille · points de la page") {
                        Text("X · \(Int(element.x))")
                        Slider(value: $element.x, in: 0...max(0, (page.width ?? 794) - element.width), step: 1)
                            .accessibilityLabel("Position horizontale de la forme")
                        Text("Y · \(Int(element.y))")
                        Slider(value: $element.y, in: 0...max(0, (page.height ?? 1123) - element.height), step: 1)
                            .accessibilityLabel("Position verticale de la forme")
                        Text("Largeur · \(Int(element.width))")
                        Slider(value: $element.width, in: 1...max(1, (page.width ?? 794) - element.x), step: 1)
                            .accessibilityLabel("Largeur de la forme")
                        Text("Hauteur · \(Int(element.height))")
                        Slider(value: $element.height, in: 1...max(1, (page.height ?? 1123) - element.y), step: 1)
                            .accessibilityLabel("Hauteur de la forme")
                    }
                }
                if exists { Button("Supprimer la forme", role: .destructive) { save(removing: true) } }
                if saving { ProgressView("Enregistrement…") }
            }
            .disabled(saving || page == nil)
            .navigationTitle(exists ? "Modifier la forme" : "Ajouter une forme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
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
