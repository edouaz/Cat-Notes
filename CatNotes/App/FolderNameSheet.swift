import SwiftUI

struct FolderNameSheet: View {
    @State var name: String
    let title: String
    let save: (String) -> Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form { TextField("Nom du dossier", text: $name).submitLabel(.done) }
                .navigationTitle(title).toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { if save(name) { dismiss() } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 200) }
                }
        }.presentationDetents([.medium])
    }
}
