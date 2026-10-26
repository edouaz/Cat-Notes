import Foundation

struct LibraryAction: Codable, Sendable {
    enum Kind: String, Codable { case createFolder, renameFolder, moveFolder, moveDocuments }
    var kind: Kind
    var folderID: UUID?
    var parentID: UUID?
    var name: String?
    var documentIDs: [UUID]?

    @discardableResult func apply(to library: inout NoteLibrarySnapshot) throws -> UUID? {
        // Mutate a copy so a failed multi-document move never partially applies.
        var updated = library
        var result: UUID?
        switch kind {
        case .createFolder:
            guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 200 else { throw CocoaError(.fileReadCorruptFile) }
            result = try updated.addFolder(name: name, parentID: parentID ?? updated.folders.first?.id).id
        case .renameFolder:
            guard let folderID, let folder = updated.folder(id: folderID), let name,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 200 else { throw CocoaError(.fileReadCorruptFile) }
            try updated.updateFolder(id: folderID, name: name, colorHex: folder.colorHex); result = folderID
        case .moveFolder:
            guard let folderID, folderID != updated.folders.first?.id,
                  let destination = parentID ?? updated.folders.first?.id else { throw CocoaError(.fileReadCorruptFile) }
            try updated.moveFolder(id: folderID, toFolderID: destination)
            result = folderID
        case .moveDocuments:
            guard let folderID, let documentIDs, !documentIDs.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            for id in Set(documentIDs) { try updated.moveNote(id: id, toFolderID: folderID) }
            result = folderID
        }
        library = updated
        return result
    }
}
