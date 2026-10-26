import SwiftUI

@MainActor
final class NotebookWorkspace: ObservableObject {
    @Published var tabs: [UUID] = []
    @Published var active: UUID?
    @Published var error: String?
    private var sessions: [UUID: EditorSession] = [:]
    private var switching = false
    let store: LibraryStore
    init(store: LibraryStore) { self.store = store }
    func session(_ id: UUID) -> EditorSession {
        if let session = sessions[id] { return session }
        let session = EditorSession(store: store, noteID: id)
        sessions[id] = session
        return session
    }
    func select(_ id: UUID) async {
        guard !switching, let note = store.library.note(id: id), note.deletedAt == nil, active != id else { return }
        Diagnostics.shared.record("workspace.change", ["active": active?.uuidString ?? "none"])
        switching = true; defer { switching = false }
        if let active, let old = sessions[active] {
            guard await old.flush() else { error = old.error; return }
            old.cancelOCR()
            old.backgroundData = nil; old.resources = [:]; old.artwork = nil
        }
        if !tabs.contains(id) { tabs.append(id) }
        active = id
        save()
    }
    func close(_ id: UUID) async {
        guard !switching else { return }
        Diagnostics.shared.record("workspace.change", ["active": active?.uuidString ?? "none"])
        switching = true; defer { switching = false }
        if let session = sessions[id], !(await session.flush()) { error = session.error; return }
        tabs.removeAll { $0 == id }; sessions[id] = nil
        if active == id { active = tabs.last }
        save()
    }
    func restore() async {
        tabs = (UserDefaults.standard.stringArray(forKey: "openNotebooks") ?? []).compactMap(UUID.init(uuidString:)).filter { store.library.note(id: $0)?.deletedAt == nil && store.library.note(id: $0) != nil }
        let selected = UserDefaults.standard.string(forKey: "activeNotebook").flatMap(UUID.init(uuidString:))
        active = selected.flatMap { tabs.contains($0) ? $0 : nil } ?? tabs.last
    }
    func save() {
        UserDefaults.standard.set(tabs.map(\.uuidString), forKey: "openNotebooks")
        UserDefaults.standard.set(active?.uuidString, forKey: "activeNotebook")
    }
    func returnToLibrary() async {
        guard !switching else { return }
        Diagnostics.shared.record("workspace.change", ["active": active?.uuidString ?? "none"])
        switching = true; defer { switching = false }
        if let active, let session = sessions[active], !(await session.flush()) { error = session.error; return }
        active = nil; save()
    }
}

struct NotebookWorkspaceView: View {
    @ObservedObject var workspace: NotebookWorkspace
    @ObservedObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var renamedNotebook: UUID?
    @State private var notebookTitle = ""
    init(workspace: NotebookWorkspace) {
        self.workspace = workspace
        store = workspace.store
    }
    private func close(_ id: UUID) {
        Task { await workspace.close(id); if workspace.active == nil { dismiss() } }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button { Task { await workspace.returnToLibrary(); if workspace.active == nil { dismiss() } } } label: { Image(systemName: "books.vertical").font(.title3).dynamicTypeSize(...DynamicTypeSize.xxxLarge).frame(width: 44, height: 44) }.accessibilityLabel("Bibliothèque").accessibilityIdentifier("workspace.library")
                if sizeClass == .regular && !typeSize.isAccessibilitySize {
                    GeometryReader { geometry in
                    ScrollViewReader { reader in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(workspace.tabs, id: \.self) { id in
                                HStack(spacing: 0) {
                                    Button { Task { await workspace.select(id) } } label: {
                                        Text(title(id)).font(.subheadline.weight(.semibold)).lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12).frame(minHeight: 44).contentShape(Rectangle())
                                    }.buttonStyle(.plain).accessibilityAddTraits(workspace.active == id ? .isSelected : [])
                                    Menu { notebookActions(id) } label: {
                                        Label("Options pour \(title(id))", systemImage: "chevron.down").labelStyle(.iconOnly)
                                            .font(.caption).frame(width: 44, height: 44).contentShape(Rectangle())
                                    }.accessibilityIdentifier("workspace.options.\(id.uuidString)")
                                    closeButton(id)
                                }.frame(width: CatNotesStyle.notebookTabWidth(availableWidth: max(0, geometry.size.width - 8), count: workspace.tabs.count)).id(id)
                                .background(workspace.active == id ? Color(uiColor: .systemBackground) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .bottom) { if workspace.active == id { Rectangle().fill(CatNotesStyle.accent).frame(height: 2).padding(.horizontal, 12) } }
                            }
                        }.padding(.horizontal, 4).padding(.vertical, 2)
                    }
                    .task(id: "\(workspace.active?.uuidString ?? "")-\(workspace.tabs.count)-\(geometry.size.width)") {
                        guard let active = workspace.active else { return }
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        reader.scrollTo(active, anchor: .center)
                    }
                    }
                    }.frame(height: 48)
                } else {
                    Menu {
                        ForEach(workspace.tabs, id: \.self) { id in
                            Button { Task { await workspace.select(id) } } label: {
                                Label(title(id), systemImage: workspace.active == id ? "checkmark" : "book.closed")
                            }
                        }
                        if let id = workspace.active { Divider(); notebookActions(id) }
                    } label: {
                        HStack { Text(workspace.active.map(title) ?? "Carnet").font(.headline).lineLimit(1); Image(systemName: "chevron.down").font(.caption) }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }.accessibilityLabel("Carnets ouverts et options")
                    if let id = workspace.active { closeButton(id) }
                }
            }.frame(minHeight: 48).background(Color(uiColor: .secondarySystemBackground))
            if let id = workspace.active {
                EditorScreen(store: workspace.store, noteID: id, session: workspace.session(id)).id(id)
            }
        }.navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
            .alert("Sauvegarde impossible", isPresented: Binding(get: { workspace.error != nil }, set: { if !$0 { workspace.error = nil } })) { Button("OK") { workspace.error = nil } } message: { Text(workspace.error ?? "") }
            .alert("Renommer le carnet", isPresented: Binding(get: { renamedNotebook != nil }, set: { if !$0 { renamedNotebook = nil } })) {
                TextField("Titre", text: $notebookTitle)
                Button("Enregistrer") {
                    if let id = renamedNotebook {
                        store.update(id) { $0.title = notebookTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Sans titre" : notebookTitle }
                    }
                    renamedNotebook = nil
                }
                Button("Annuler", role: .cancel) { renamedNotebook = nil }
            }
    }
    private func title(_ id: UUID) -> String { store.library.note(id: id)?.title ?? "Carnet" }
    private func closeButton(_ id: UUID) -> some View {
        Button { close(id) } label: {
            Label("Fermer \(title(id))", systemImage: "xmark").labelStyle(.iconOnly)
                .font(.body).dynamicTypeSize(...DynamicTypeSize.xxxLarge).frame(width: 44, height: 44).contentShape(Rectangle())
        }.accessibilityHint("Ferme l’onglet et conserve le carnet")
    }
    @ViewBuilder private func notebookActions(_ id: UUID) -> some View {
        Button("Renommer", systemImage: "pencil") { notebookTitle = title(id); renamedNotebook = id }
        Button(store.library.note(id: id)?.favorite == true ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: "star") {
            store.update(id) { $0.favorite = !($0.favorite ?? false) }
        }
    }
}
