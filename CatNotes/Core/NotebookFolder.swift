// Derived from Signotes, copyright (c) 2026 Diego Signorastri. MIT; see docs/Signotes-LICENSE.
import Foundation

struct NotebookFolder: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var colorHex: String?
    var noteIDs: [UUID]
    var childFolderIDs: [UUID]

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String? = nil,
        noteIDs: [UUID] = [],
        childFolderIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.noteIDs = noteIDs
        self.childFolderIDs = childFolderIDs
    }
}
