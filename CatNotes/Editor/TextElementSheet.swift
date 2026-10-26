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
                Section("Texte") {
                    TextEditor(text: $element.text)
                        .frame(minHeight: 180)
                        .accessibilityLabel("Contenu de la zone de texte")
                        .accessibilityIdentifier("editor.text.content")
                    Text("Le texte est enregistré dans la page et inclus dans les exports. Déplacez et dimensionnez sa zone ci-dessous.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Style") {
                    ColorPicker("Couleur du texte", selection: Binding(get: {
                        Color(element.textColorHex.flatMap(UIColor.init(presetHex:)) ?? .black)
                    }, set: { element.textColorHex = UIColor($0).presetHex }), supportsOpacity: false)
                    Text("Taille · \(Int(element.textFontSize ?? 20)) pt")
                    Slider(value: Binding(get: { element.textFontSize ?? 20 }, set: { element.textFontSize = $0 }), in: 8...96, step: 1)
                        .accessibilityLabel("Taille du texte")
                }
                if let page {
                    Section("Position et taille · points de la page") {
                        Text("X · \(Int(element.x))")
                        Slider(value: $element.x, in: 0...max(0, (page.width ?? 794) - element.width), step: 1)
                            .accessibilityLabel("Position horizontale du texte")
                        Text("Y · \(Int(element.y))")
                        Slider(value: $element.y, in: 0...max(0, (page.height ?? 1123) - element.height), step: 1)
                            .accessibilityLabel("Position verticale du texte")
                        Text("Largeur · \(Int(element.width))")
                        Slider(value: $element.width, in: 1...max(1, (page.width ?? 794) - element.x), step: 1)
                            .accessibilityLabel("Largeur de la zone de texte")
                        Text("Hauteur · \(Int(element.height))")
                        Slider(value: $element.height, in: 1...max(1, (page.height ?? 1123) - element.y), step: 1)
                            .accessibilityLabel("Hauteur de la zone de texte")
                    }
                }
                if exists {
                    Button("Supprimer le texte", role: .destructive) { save(removing: true) }
                }
                if saving { ProgressView("Enregistrement…") }
            }
            .disabled(saving || page == nil)
            .navigationTitle(exists ? "Modifier le texte" : "Ajouter du texte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
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
