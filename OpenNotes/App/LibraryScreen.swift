import SwiftUI
import UniformTypeIdentifiers

struct LibraryScreen: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("librarySidebarShown") private var sidebarShown = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var workspace: NotebookWorkspace?
    @Environment(\.scenePhase) private var scenePhase
    @State private var consumingInbox = false
    @State private var failedSharedImport: URL?
    @State private var lastOpening: Task<Void, Never>?
    @State private var path: [UUID] = []
    @State private var query = ""
    @State private var filter = 0
    private var trash: Bool { filter == 2 }
    private var favorites: Bool { filter == 1 }
    @State private var importer = false
    @State private var settings = false
    @State private var diagnosticsShown = false
    @State private var selectedFolderID: UUID?
    @State private var folderEditorShown = false
    @State private var renamedFolder: NotebookFolder?
    @State private var moveShown = false
    @State private var movingFolder: UUID?
    @State private var movingDocuments: [UUID] = []
    @State private var selectingDocuments = false
    @State private var selectedDocuments: Set<UUID> = []
    @AppStorage("librarySort") private var sort = "date"
    private var currentFolderID: UUID? { selectedFolderID ?? store.library.folders.first?.id }
    private var folders: [NotebookFolder] {
        guard filter == 0, query.isEmpty else { return [] }
        return store.library.childFolders(of: currentFolderID)
    }
    @State private var rename: NoteDocument?
    @State private var title = ""
    @State private var deletion: NoteDocument?
    var notes: [NoteDocument] {
        let found = store.matchingNotes(query, trash: trash, favorites: favorites).filter {
            filter != 0 || !query.isEmpty || $0.folderID == currentFolderID
        }
        if sort == "name" { return found.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
        return found
    }
    var body: some View {
        NavigationStack(path: $path) {
            presentedLibrary
        }
    }
    private var navigationContent: some View {
        HStack(spacing: 0) {
            if sidebarShown && sizeClass == .regular && !dynamicTypeSize.isAccessibilitySize {
                librarySidebar
            }
            libraryContent
        }
        .navigationTitle(trash ? "Trash" : favorites ? "Favorites" : selectedFolderID.flatMap { id in store.library.folders.first(where: { $0.id == id })?.name } ?? "Documents")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Document titles and text")
        .onChange(of: filter) { value in if value != 0 { selectedFolderID = nil }; resetSelection() }
        .onChange(of: selectedFolderID) { _ in resetSelection() }
        .onChange(of: query) { _ in resetSelection() }
        .onChange(of: notes.map(\.id)) { visible in selectedDocuments.formIntersection(visible) }
        .task(id: query) {
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
            for note in store.library.notes where note.deletedAt == nil {
                guard !Task.isCancelled else { return }
                await store.indexPDFText(in: note.id)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { Button { diagnosticsShown = true } label: { Label("Diagnostic", systemImage: "ladybug") } }
            if sizeClass == .regular && !dynamicTypeSize.isAccessibilitySize { ToolbarItem(placement: .navigationBarLeading) { Button { sidebarShown.toggle() } label: { Label("Sidebar", systemImage: "sidebar.left") } } } }
        .navigationDestination(for: UUID.self) { id in
            if let workspace { NotebookWorkspaceView(workspace: workspace) }
        }
    }
    private var activeLibrary: some View {
        navigationContent
            .task {
                if !store.ready { await store.load() }
                guard store.ready else { return }
                if workspace == nil {
                    let model = NotebookWorkspace(store: store)
                    workspace = model
                    await model.restore()
                    if let id = model.active { path = [id] }
                }
                await consumeInbox()
            }
            .onChange(of: scenePhase) { phase in if phase == .active { Task { await consumeInbox() } } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in Task { await store.disk.clearThumbnails() } }
            .onOpenURL { url in Task { if let id = await store.importFile(url, folderID: currentFolderID) { openNotebook(id) } } }
            .fileImporter(isPresented: $importer, allowedContentTypes: [.pdf, .image, UTType(filenameExtension: "catnote") ?? .data]) { result in
                Task {
                    do { if let id = await store.importFile(try result.get(), folderID: currentFolderID) { openNotebook(id) } }
                    catch { store.error = error.localizedDescription }
                }
            }
    }
    private var presentedLibrary: some View {
        activeLibrary
            .alert("Rename notebook", isPresented: Binding(get: { rename != nil }, set: { if !$0 { rename = nil } })) {
                TextField("Title", text: $title)
                Button("Save") {
                    if let note = rename { store.update(note.id) { $0.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : title } }; rename = nil
                }
                Button("Cancel", role: .cancel) { rename = nil }
            }
            .confirmationDialog("Move this notebook to Trash?", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
                Button("Move to Trash", role: .destructive) { if let note = deletion { store.update(note.id) { $0.deletedAt = Date() } }; deletion = nil }
            } message: { Text("You can restore it from the library.") }
            .alert("OpenNotes", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("OK") { store.error = nil }
                if let failedSharedImport {
                    Button("Retry import") { Task { await consumeInbox() } }
                    Button("Remove this import", role: .destructive) {
                        do { try ShareInbox.remove(failedSharedImport); self.failedSharedImport = nil; Task { await consumeInbox() } }
                        catch { store.error = error.localizedDescription }
                    }
                }
                if !store.ready { Button("Restore backup copy") { Task { await store.restore() } } }
            } message: { Text(store.error ?? "") }
            .sheet(isPresented: $folderEditorShown) {
                FolderNameSheet(name: renamedFolder?.name ?? "", title: renamedFolder == nil ? "New folder" : "Rename folder") { name in
                    let action = LibraryAction(kind: renamedFolder == nil ? .createFolder : .renameFolder, folderID: renamedFolder?.id, parentID: currentFolderID, name: name)
                    return store.apply(action) != nil
                }
            }
            .sheet(isPresented: $moveShown) {
                FolderPickerSheet(store: store, movingFolderID: movingFolder) { destination in
                    if let movingFolder { store.apply(.init(kind: .moveFolder, folderID: movingFolder, parentID: destination)) }
                    else { store.apply(.init(kind: .moveDocuments, folderID: destination, documentIDs: movingDocuments)) }
                    selectedDocuments = []; selectingDocuments = false
                }
            }
            .sheet(isPresented: $diagnosticsShown) { DiagnosticsScreen() }
            .sheet(isPresented: $settings) { CloudScreen(store: store) }
    }
    private var libraryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ViewThatFits(in: .horizontal) {
                    HStack { newNoteButton; importButton; folderButton }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 12) { newNoteButton; importButton; folderButton }
                }.disabled(!store.ready)
                if filter == 0 && query.isEmpty { folderBreadcrumbs }
                adaptiveLibraryControls
                if sizeClass != .regular || dynamicTypeSize.isAccessibilitySize {
                    Picker("Documents", selection: $filter) {
                        Text("Documents").tag(0); Text("Favorites").tag(1); Text("Trash").tag(2)
                    }.pickerStyle(.menu).frame(minHeight: 44).accessibilityIdentifier("library.filter")
                }
                if !store.ready { ProgressView("Opening library…") }
                else if notes.isEmpty && folders.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: !query.isEmpty ? "magnifyingglass" : trash ? "trash" : "book.closed").font(.largeTitle).foregroundStyle(OpenNotesStyle.accent).accessibilityHidden(true)
                        Text(!query.isEmpty ? "No results" : trash ? "Trash is empty" : favorites ? "Your favorite notebooks" : "A page for your ideas").font(.title2.weight(.semibold))
                        Text(!query.isEmpty ? "No notebooks match “\(query)”." : trash ? "Deleted notebooks appear here." : favorites ? "Star a notebook to find it here." : "Create your first notebook or import a document to start writing.").foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if !query.isEmpty { Button("Clear search") { query = "" }.frame(minHeight: 44) }
                    }.frame(maxWidth: .infinity).padding(.vertical, 56)
                }
                LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 190), spacing: 24)], alignment: .leading, spacing: 24) {
                    ForEach(folders) { folder in folderCard(folder) }
                    ForEach(notes) { note in noteCard(note) }
                }
            }.padding(dynamicTypeSize.isAccessibilitySize || sizeClass != .regular ? 16 : 28)
        }.frame(maxWidth: .infinity).background(Color(uiColor: .systemGroupedBackground))
    }
    private var librarySidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("OpenNotes").font(.title.bold()).padding(20).accessibilityAddTraits(.isHeader)
            List {
                Section {
                    sidebarItem("Documents", "folder", 0)
                    sidebarItem("Favorites", "star", 1)
                    sidebarItem("Trash", "trash", 2)
                }
                let rootFolders = store.library.childFolders(of: store.library.folders.first?.id)
                if !rootFolders.isEmpty {
                    Section("Folders") {
                        ForEach(rootFolders) { folder in
                            let selected = filter == 0 && currentFolderID == folder.id
                            Button {
                                filter = 0
                                selectedFolderID = folder.id
                                query = ""
                                resetSelection()
                            } label: {
                                HStack {
                                    Label(folder.name, systemImage: "folder")
                                        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                    if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
                                }.frame(minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .foregroundStyle(selected ? OpenNotesStyle.accent : Color.primary)
                                .accessibilityAddTraits(selected ? .isSelected : [])
                                .accessibilityIdentifier("library.sidebar.folder.\(folder.id.uuidString)")
                                .contextMenu { folderActions(folder) }
                        }
                    }
                }
            }.listStyle(.sidebar)
            Label("On this device", systemImage: "internaldrive")
                .font(.caption).foregroundStyle(.secondary).padding(20)
        }.frame(width: 250).frame(maxHeight: .infinity)
            .background(Color(uiColor: .secondarySystemBackground))
    }
    private func cardTitle(_ title: String) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize { Text(title) }
            else { Text(title).lineLimit(2, reservesSpace: true) }
        }.font(.headline).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func folderCard(_ folder: NotebookFolder) -> some View {
        let noteCount = store.library.notes.filter { $0.folderID == folder.id && $0.deletedAt == nil }.count
        return VStack(alignment: .leading, spacing: 8) {
            Button { selectedFolderID = folder.id } label: {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "folder.fill").resizable().scaledToFit()
                        .foregroundStyle(OpenNotesStyle.accent).padding(.horizontal, 8).padding(.vertical, 28)
                        .frame(maxWidth: .infinity).frame(height: 192)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityHidden(true)
                    cardTitle(folder.name)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(folder.name)
                .accessibilityHint("Open folder")
                .accessibilityIdentifier("library.folder.\(folder.id.uuidString)")
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(noteCount) notebook\(noteCount == 1 ? "" : "s")")
                    Text("\(folder.childFolderIDs.count) folder\(folder.childFolderIDs.count == 1 ? "" : "s")")
                }.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Menu { folderActions(folder) } label: {
                    Label("Actions for \(folder.name)", systemImage: "ellipsis").labelStyle(.iconOnly)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
            }
        }.padding(12).background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color(uiColor: .separator).opacity(0.3)) }
            .contextMenu { folderActions(folder) }
    }
    @ViewBuilder private func folderActions(_ folder: NotebookFolder) -> some View {
        Button("Rename", systemImage: "pencil") { renamedFolder = folder; folderEditorShown = true }
        Button("Move", systemImage: "folder") { movingFolder = folder.id; movingDocuments = []; moveShown = true }
    }
    private func noteCard(_ note: NoteDocument) -> some View {
        let selected = selectedDocuments.contains(note.id)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                if selectingDocuments {
                    if selected { selectedDocuments.remove(note.id) } else { selectedDocuments.insert(note.id) }
                } else if !trash { openNotebook(note.id) }
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    Group {
                        if let page = store.library.firstPage(in: note.id) { PageThumbnail(page: page, disk: store.disk) }
                        else { Image(systemName: "doc").resizable().scaledToFit().foregroundStyle(.tertiary) }
                    }.padding(12).frame(maxWidth: .infinity).frame(height: 192)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .topTrailing) {
                            if selectingDocuments {
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .font(.title2).foregroundStyle(OpenNotesStyle.accent).padding(6).background(Color(uiColor: .systemBackground), in: Circle()).padding(6)
                            }
                        }.accessibilityHidden(true)
                    cardTitle(note.title)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(trash)
                .accessibilityLabel(note.title)
                .accessibilityValue(trash ? "In Trash" : selectingDocuments ? (selected ? "Selected" : "Not selected") : "")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("library.note.\(note.id.uuidString)")
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(note.pageIDs.count) page\(note.pageIDs.count == 1 ? "" : "s")")
                    Text(note.updatedAt, style: .date)
                }.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if note.favorite == true { Image(systemName: "star.fill").foregroundStyle(.orange).accessibilityLabel("Favorite") }
                Menu { noteActions(note) } label: {
                    Label("Actions for \(note.title)", systemImage: "ellipsis").labelStyle(.iconOnly)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
            }
            if trash { Text("In Trash · Restore from the menu").font(.caption).foregroundStyle(.secondary) }
        }.padding(12).background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? OpenNotesStyle.accent : Color(uiColor: .separator).opacity(0.3), lineWidth: selected ? 2 : 1) }
            .contextMenu { noteActions(note) }
    }
    private var adaptiveLibraryControls: some View {
        ViewThatFits(in: .horizontal) {
            if !dynamicTypeSize.isAccessibilitySize {
                libraryControls.fixedSize(horizontal: true, vertical: false)
            }
            compactLibraryControls
        }
    }
    private var compactLibraryControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Sort", selection: $sort) {
                Text("Date").tag("date")
                Text("Name").tag("name")
            }.pickerStyle(.menu)
            selectionControls
        }
    }
    private var libraryControls: some View {
        HStack(spacing: 16) {
            Picker("Sort", selection: $sort) { Text("Date").tag("date"); Text("Name").tag("name") }.pickerStyle(.segmented).frame(width: 200)
            selectionControls
        }
    }
    private var selectionControls: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            if !trash {
            if selectingDocuments && !selectedDocuments.isEmpty {
                Button { movingFolder = nil; movingDocuments = Array(selectedDocuments); moveShown = true } label: {
                    Text("Move (\(selectedDocuments.count))").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }.accessibilityIdentifier("library.move")
            }
            Button { selectingDocuments.toggle(); selectedDocuments = [] } label: {
                Text(selectingDocuments ? "Done" : "Select").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }.accessibilityIdentifier("library.select")
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
    private var folderButton: some View {
        Button { renamedFolder = nil; folderEditorShown = true } label: { Label("Folder", systemImage: "folder.badge.plus") }.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle).controlSize(.large)
    }
    private var folderBreadcrumbs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                Button { selectedFolderID = nil } label: { Text("Documents").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                if let currentFolderID {
                    ForEach(store.library.folderPath(to: currentFolderID).filter { $0.id != store.library.folders.first?.id }) { folder in
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        Button { selectedFolderID = folder.id } label: { Text(folder.name).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                    }
                }
            }.font(.subheadline)
        }
    }
    private func sidebarItem(_ title: String, _ symbol: String, _ value: Int) -> some View {
        let selected = filter == value && (value != 0 || selectedFolderID == nil)
        return Button { filter = value; selectedFolderID = nil; resetSelection() } label: {
            HStack {
                Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading)
                if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(selected ? OpenNotesStyle.accent : Color.primary)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func resetSelection() {
        selectedDocuments = []; selectingDocuments = false
    }
    private func openNotebook(_ id: UUID) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        if workspace == nil { workspace = NotebookWorkspace(store: store) }
        let previous = lastOpening
        lastOpening = Task {
            await previous?.value
            await workspace?.select(id)
            if workspace?.active == id { path = [id] }
        }
    }
    private func consumeInbox() async {
        guard store.ready, !consumingInbox else { return }
        consumingInbox = true; defer { consumingInbox = false }
        do {
            for url in try ShareInbox.pending() {
                let receipt = url.deletingLastPathComponent().lastPathComponent
                let id: UUID
                if let existing = store.library.sharedImports[receipt] { id = existing }
                else {
                    guard let imported = await store.importFile(url, folderID: currentFolderID) else { failedSharedImport = url; break }
                    id = imported
                    store.library.sharedImports[receipt] = id
                    store.persist()
                }
                guard await store.flush() else { failedSharedImport = url; break }
                try ShareInbox.remove(url)
                failedSharedImport = nil
                store.library.sharedImports[receipt] = nil; store.persist()
                openNotebook(id)
            }
        } catch {
            // Unsigned/local-only builds may not have an App Group container.
            if (error as NSError).code != CocoaError.fileReadNoPermission.rawValue { store.error = "Shared import: \(error.localizedDescription)" }
        }
    }
    private var newNoteButton: some View {
        Button { createNote() } label: { Label("New notebook", systemImage: "plus").fixedSize(horizontal: false, vertical: true).foregroundStyle(Color(uiColor: .systemBackground)) }
            .labelStyle(.titleAndIcon).buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle).controlSize(.large)
            .accessibilityIdentifier("library.create")
            .keyboardShortcut("n", modifiers: .command)
    }
    private var importButton: some View {
        Button { importer = true } label: { Label("Import", systemImage: "square.and.arrow.down").fixedSize(horizontal: false, vertical: true) }
            .labelStyle(.titleAndIcon).buttonStyle(.bordered).buttonBorderShape(.roundedRectangle).controlSize(.large)
    }
    private func createNote() {
        Task { if let id = await store.create(folderID: currentFolderID) { openNotebook(id) } }
    }
    @ViewBuilder private func noteActions(_ note: NoteDocument) -> some View {
        if trash {
            Button("Restore notebook", systemImage: "arrow.uturn.backward") { store.update(note.id) { $0.deletedAt = nil } }
        } else {
            Button("Move to…", systemImage: "folder") { movingFolder = nil; movingDocuments = [note.id]; moveShown = true }
            Button("Rename", systemImage: "pencil") { title = note.title; rename = note }
            Button(note.favorite == true ? "Remove from favorites" : "Add to favorites", systemImage: "star") { store.update(note.id) { $0.favorite = !($0.favorite ?? false) } }
            Button("Move to Trash", systemImage: "trash", role: .destructive) { deletion = note }
        }
    }

}

struct CloudStatusLine: View {
    @ObservedObject var cloud: CloudSync
    var body: some View { Label(cloud.signedIn ? cloud.status : "No account · Available offline", systemImage: cloud.signedIn ? "cloud" : "internaldrive").font(.caption).foregroundStyle(.secondary) }
}
