import SwiftUI

struct FolderPickerSheet: View {
    @ObservedObject var store: LibraryStore
    var movingFolderID: UUID?
    let choose: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(store.library.folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { folder in
                Button {
                    choose(folder.id); dismiss()
                } label: { Label(store.library.folderPath(to: folder.id).map(\.name).joined(separator: " / "), systemImage: "folder") }
                .disabled(movingFolderID == folder.id || movingFolderID.map { store.library.folderPathContains(folderID: folder.id, candidateID: $0) } == true)
            }.navigationTitle("Move to…").toolbar { Button("Cancel") { dismiss() } }
        }
    }
}
