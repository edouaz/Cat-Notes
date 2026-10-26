import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import PencilKit
import PhotosUI

struct EditorScreen: View {
    @StateObject private var session: EditorSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("fingerDrawing") private var finger = false
    @AppStorage("verticalPaging") private var verticalPaging = false
    @AppStorage("showInkColor") private var showInkColor = true
    @AppStorage("showInkWidth") private var showInkWidth = true
    @State private var diagnosticsShown = false
    @State private var annotationsShown = false
    @State private var searchShown = false
    @State private var stickyNote: PageElement?
    @State private var textElement: PageElement?
    @State private var shapeElement: PageElement?
    @State private var selectionKind: PageElement.Kind?
    @State private var selecting = false
    @State private var capture: UIImage?
    @State private var captureShown = false
    @State private var previousPreview: UIImage?
    @State private var nextPreview: UIImage?
    @State private var photosShown = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageImporter = false
    @State private var insertingImage = false
    @State private var pageDirection = 1
    @State private var settingsShown = false
    @State private var addShown = false
    @State private var addingTemplate = PageTemplate.blank
    @State private var exporting = false
    @State private var editingImages = false
    @State private var pagesShown = false
    @State private var pagePanelEditing = false
    @State private var exportShown = false
    @AppStorage("showUndo") private var showUndo = true
    @State private var paperShown = false
    @State private var elementsShown = false
    @State private var share: ShareFile?
    @State private var sourcePDF: ShareFile?
    @State private var deleteShown = false
    @State private var deletePageID: UUID?
    @State private var first = 1
    @State private var last = 1
    @ObservedObject var store: LibraryStore
    let noteID: UUID
    init(store: LibraryStore, noteID: UUID, session: EditorSession? = nil) {
        self.store = store; self.noteID = noteID
        _session = StateObject(wrappedValue: session ?? EditorSession(store: store, noteID: noteID))
    }
    var pages: [NotePage] { store.library.pages(in: noteID) }
    private var neighboringPages: [NotePage] {
        [currentIndex - 1, currentIndex + 1].compactMap { pages.indices.contains($0) ? pages[$0] : nil }
    }
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                quickActions
                WritingInstrumentBar(session: session, insertImage: { photosShown = true }, addStickyNote: addStickyNote)
                if selecting || editingImages { modeBanner }
                HStack(spacing: 0) {
                    if pagesShown && geometry.size.width >= 700 {
                        pagePanel(closeOnSelection: false)
                            .frame(width: min(280, geometry.size.width * 0.3))
                        Divider()
                    }
                    canvasWorkspace
                }
            }
            .sheet(isPresented: Binding(get: { pagesShown && geometry.size.width < 700 }, set: { pagesShown = $0 })) { pageList }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: pagesShown)
        }
        .overlay(alignment: .topTrailing) { if session.busy { ProgressView().padding(12).allowsHitTesting(false) } }
        .clipped()
        .background(Color(uiColor: .systemBackground))
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .task {
            let id = UserDefaults.standard.string(forKey: "lastPage-\(noteID)").flatMap(UUID.init(uuidString:))
            await session.open(id)
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                let taskID = UIApplication.shared.beginBackgroundTask(withName: "Save notes")
                Task { await session.flush(); UIApplication.shared.endBackgroundTask(taskID) }
            }
        }
        .onDisappear { finishMode(); session.cancelPreparation(); session.cancelOCR(); Task { await session.flush() } }
        .onChange(of: session.page?.id) { _ in finishMode() }
        .task(id: neighboringPages) {
            previousPreview = nil; nextPreview = nil
            let index = currentIndex; let ordered = pages
            do {
                if ordered.indices.contains(index - 1) { let image = try await store.disk.thumbnail(ordered[index - 1], pixels: 1400); try Task.checkCancellation(); previousPreview = image }
                try Task.checkCancellation()
                if ordered.indices.contains(index + 1) { let image = try await store.disk.thumbnail(ordered[index + 1], pixels: 1400); try Task.checkCancellation(); nextPreview = image }
            } catch { }
        }
        .sheet(isPresented: $diagnosticsShown) { DiagnosticsScreen() }
        .sheet(isPresented: $annotationsShown) { AnnotationsSheet(session: session) { item in
            Task { try? await Task.sleep(nanoseconds: 300_000_000); stickyNote = item }
        } }
        .sheet(isPresented: $searchShown) { DocumentSearchSheet(session: session, store: store) }
        .sheet(item: $stickyNote) { StickyNoteSheet(session: session, note: $0) }
        .sheet(item: $textElement) { item in
            if let page = session.page { TextElementSheet(session: session, pageID: page.id, element: item) }
        }
        .sheet(item: $shapeElement) { item in
            if let page = session.page { ShapeElementSheet(session: session, pageID: page.id, element: item) }
        }
        .sheet(isPresented: $captureShown) { [capture] in if let capture { CaptureSheet(image: capture) { Task { await session.insertImage(capture); beginImagePlacement() } } } }
        .photosPicker(isPresented: $photosShown, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { photo in
            Task {
                do { if let data = try await photo?.loadTransferable(type: Data.self) { await insertImageData(data) } }
                catch { session.error = error.localizedDescription }
                selectedPhoto = nil
            }
        }
        .fileImporter(isPresented: $imageImporter, allowedContentTypes: [.image]) { result in
            Task {
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try await Task.detached { () throws -> Data in
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size > 0, size <= 150_000_000 else { throw CocoaError(.fileReadTooLarge) }
                        return try Data(contentsOf: url)
                    }.value
                    await insertImageData(data)
                } catch { session.error = error.localizedDescription }
            }
        }
        
        .sheet(isPresented: $addShown) { addPageForm }
        .sheet(isPresented: $paperShown) { PaperSheet(session: session) }
        .sheet(isPresented: $elementsShown, onDismiss: { finishMode(); editingImages = session.page?.elements?.contains(where: { $0.kind == .image }) == true }) { ElementSheet(session: session) }
        .sheet(isPresented: $exportShown) { exportForm }
        .sheet(item: $share) { ActivitySheet(url: $0.url) }
        .sheet(item: $sourcePDF) { PDFReaderScreen(url: $0.url) }
        .alert("OpenNotes", isPresented: Binding(get: { session.error != nil || store.error != nil }, set: { if !$0 { session.error = nil; store.error = nil } })) {
            Button("Retry saving") { store.persist(); Task { await session.flush() } }
            Button("Close", role: .cancel) { session.error = nil; store.error = nil }
        } message: { Text(session.error ?? store.error ?? "") }
    }
    private var canvasWorkspace: some View {
        Group {
            if session.page != nil {
                WritingCanvas(session: session, finger: finger, reading: false, verticalPaging: verticalPaging, editingImages: editingImages, pageDirection: pageDirection,
                    previousPreview: previousPreview, nextPreview: nextPreview,
                    hasPrevious: currentIndex > 0, hasNext: currentIndex + 1 < pages.count,
                    selectionMode: selecting, immediateSelection: selectionKind != nil, selectedRect: selectRegion, pasted: { finishMode() }, editNote: { stickyNote = $0 },
                    imageEditingEnded: { finishMode() }, selectionMoved: { path, delta in
                        Task { await session.moveSelection(inside: path, by: delta) }
                    }, prepare: { delta in
                        if delta == 0 { session.cancelPreparation(); return }
                        let index = currentIndex + delta
                        session.preparePage(pages.indices.contains(index) ? pages[index].id : nil)
                    }, addPage: { await quickAddPage(before: $0 < 0) }, navigate: navigate)
            } else {
                VStack { Spacer(); ProgressView("Loading page…"); Spacer() }.frame(maxWidth: .infinity)
            }
        }
    }
    private var rulerActive: Bool {
        session.toolSettings.rulerEnabled == true && session.selectedTool.isWritingTool && !selecting && !editingImages
    }
    private func toggleRuler() {
        let enabled = !rulerActive
        if enabled {
            finishMode()
            if !session.selectedTool.isWritingTool { session.selectedTool = .pen }
        }
        session.toolSettings.rulerEnabled = enabled
    }
    private var quickActions: some View {
        HStack(spacing: 0) {
            Button { pagesShown.toggle(); Task { await session.flush() } } label: {
                HStack(spacing: 6) { Image(systemName: "sidebar.left"); Text("\(currentIndex + 1)/\(pages.count)").font(.caption).monospacedDigit() }
            }
            .accessibilityLabel("Pages and bookmarks, page \(currentIndex + 1) of \(pages.count)")
            .accessibilityIdentifier("editor.pages")
            .accessibilityValue("Page \(currentIndex + 1) of \(pages.count)")
            .accessibilityAddTraits(pagesShown ? .isSelected : [])
            Button { searchShown = true } label: { Label("Search notebook", systemImage: "magnifyingglass") }
                .accessibilityIdentifier("editor.search")
            insertionMenu
            Button(action: toggleRuler) { Label("Ruler", systemImage: "ruler") }
                .accessibilityAddTraits(rulerActive ? .isSelected : [])
                .accessibilityIdentifier("editor.ruler")
            Button { toggleBookmark() } label: { Label("Bookmark", systemImage: session.page?.bookmark == true ? "bookmark.fill" : "bookmark") }
                .accessibilityAddTraits(session.page?.bookmark == true ? .isSelected : [])
            Spacer(minLength: 0)
            Button { first = 1; last = pages.count; exportShown = true } label: { Label("Share notebook", systemImage: "square.and.arrow.up") }
                .accessibilityIdentifier("editor.share")
            actionsMenu
        }.labelStyle(.iconOnly).dynamicTypeSize(...DynamicTypeSize.xxxLarge).buttonStyle(ToolButtonStyle()).padding(.horizontal, 8)
            .background(Color(uiColor: .systemBackground))
            .overlay(alignment: .bottom) { Divider() }
    }
    private var modeBanner: some View {
        ViewThatFits(in: .horizontal) {
            if !typeSize.isAccessibilitySize {
                HStack(spacing: 12) {
                    modeDescription.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 12)
                    modeDone
                }
            }
            VStack(alignment: .leading, spacing: 8) { modeDescription; modeDone }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(uiColor: .tertiarySystemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }
    private var modeDescription: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(modeTitle, systemImage: selecting ? "viewfinder" : "arrow.up.left.and.arrow.down.right").font(.subheadline.bold())
            Text(selecting ? "Outline an area on the page." : "Move or resize the image.").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var modeTitle: String {
        guard selecting else { return "Image placement" }
        switch selectionKind {
        case .highlight: return "Highlight an area"
        case .rectangle: return "Outline an area"
        default: return "Capture an area"
        }
    }
    private var modeDone: some View {
        Button { finishMode() } label: { Text(selecting ? "Cancel" : "Finish").frame(minWidth: 44, minHeight: 44) }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("editor.mode.done")
    }
    private func beginSelection(_ kind: PageElement.Kind? = nil) {
        editingImages = false; selectionKind = kind; selecting = true
    }
    private func finishMode() {
        selecting = false; selectionKind = nil; editingImages = false
    }
    private func beginImagePlacement() {
        finishMode()
        if session.selectedTool == .lasso { session.selectedTool = .pen }
        editingImages = true
    }
    private var insertionMenu: some View {
        Menu {
            Button("Add page", systemImage: "doc.badge.plus") { Task { await quickAddPage() } }.disabled(session.busy).accessibilityIdentifier("editor.addPage")
            Button("Add with different paper", systemImage: "doc") { addShown = true }
            Section("Image") {
                Button("Photos", systemImage: "photo") { photosShown = true }
                Button("Files", systemImage: "folder") { imageImporter = true }
                Button("Paste", systemImage: "doc.on.clipboard") { Task { if let page = session.page { await session.paste(at: CGPoint(x: (page.width ?? 794) / 2, y: (page.height ?? 1123) / 2)) } } }
                Button("Crop / manage images") { elementsShown = true }
                if session.page?.elements?.contains(where: { $0.kind == .image }) == true { Button(editingImages ? "Finish placement" : "Move images with Pencil") {
                    let placing = !editingImages; finishMode(); editingImages = placing
                } }
            }
            Button("Add sticky note", systemImage: "note.text") { addStickyNote() }.accessibilityIdentifier("editor.sticky.add")
            Menu {
                Button("Add text", systemImage: "text.badge.plus") { addText() }
                    .accessibilityIdentifier("editor.text.add")
                ForEach((session.page?.elements ?? []).filter { $0.kind == .text }) { item in
                    Button(String(item.text.prefix(60))) { textElement = item }
                }
            } label: { Label("Text", systemImage: "textformat") }
            Menu {
                Section("Add") {
                    ForEach(ShapeElementSheet.kinds, id: \.self) { kind in
                        Button(ShapeElementSheet.title(kind)) { addShape(kind) }
                            .accessibilityIdentifier("editor.shape.add.\(kind.rawValue)")
                    }
                }
                if let shapes = session.page?.elements?.filter({ ShapeElementSheet.kinds.contains($0.kind) }), !shapes.isEmpty {
                    Section("Edit") {
                        ForEach(Array(shapes.enumerated()), id: \.element.id) { index, item in
                            Button("\(ShapeElementSheet.title(item.kind)) \(index + 1)") { shapeElement = item }
                        }
                    }
                }
            } label: { Label("Shapes", systemImage: "square.on.circle") }
            Section("Zone") {
                Button("Capture an area", systemImage: "camera.viewfinder") { beginSelection() }
                Button("Capture entire page", systemImage: "doc.viewfinder") {
                    guard let page = session.page else { return }
                    finishMode()
                    let rect = CGRect(origin: .zero, size: PageRenderer.size(page))
                    selectRegion(rect, UIBezierPath(rect: rect), .preview)
                }
                Button("Highlight an area", systemImage: "highlighter") { beginSelection(.highlight) }
                Button("Outline an area", systemImage: "rectangle") { beginSelection(.rectangle) }
            }
        } label: { Label("Add page and insert", systemImage: "doc.badge.plus") }.disabled(insertingImage).accessibilityIdentifier("editor.insert")
    }
    private var actionsMenu: some View {
        Menu {
            Section("Document") {
                Button("Search notebook", systemImage: "magnifyingglass") { searchShown = true }
                if !session.searchHighlights.isEmpty { Button("Clear results") { session.searchHighlights = [] } }
                if sizeClass != .regular && showUndo { Button("Redo", systemImage: "arrow.uturn.forward") { session.canvas.undoManager?.redo() }.disabled(!session.canRedo) }
                Button("Page annotations", systemImage: "list.bullet.rectangle") { annotationsShown = true }
                Button("Exporting…", systemImage: "square.and.arrow.up") { first = 1; last = pages.count; exportShown = true }
            }
            Section("Framing") {
                Button("Fit width", systemImage: "arrow.left.and.right") { (session.canvas.superview as? PageScrollView)?.fitAxis(horizontal: true) }
                Button("Fit height", systemImage: "arrow.up.and.down") { (session.canvas.superview as? PageScrollView)?.fitAxis(horizontal: false) }
            }
            Section("Appearance") {
                Button("Change paper", systemImage: "doc") { paperShown = true }
                Button("Customize tools", systemImage: "slider.horizontal.3") { settingsShown = true }
            }
            Section("Assistance") {
                Button("Diagnostic mode / export logs", systemImage: "ladybug") { diagnosticsShown = true }
            }
        } label: { Label("Notebook actions", systemImage: "ellipsis").labelStyle(.iconOnly) }
            .accessibilityIdentifier("editor.actions")
            .popover(isPresented: $settingsShown) { settingsForm.frame(idealWidth: 380, idealHeight: 540) }
    }
    @discardableResult private func quickAddPage(before: Bool = false) async -> Bool {
        guard !session.busy, await session.flush(), let current = session.page,
              let id = await store.addPage(noteID: noteID, after: current.id) else { return false }
        if var page = store.library.page(id: id) {
            page.width = current.width; page.height = current.height; page.template = current.template
            store.updatePage(page)
        }
        if before { store.movePage(id, index: currentIndex) }
        pageDirection = before ? -1 : 1; await session.open(id)
        return session.page?.id == id
    }
    private func addStickyNote() {
        guard let page = session.page else { return }
        var note = PageElement(kind: .stickyNote)
        note.text = ""; note.width = min(240, (page.width ?? 794) * 0.6); note.height = min(160, (page.height ?? 1123) * 0.4)
        note.x = ((page.width ?? 794) - note.width) / 2; note.y = ((page.height ?? 1123) - note.height) / 2
        stickyNote = note
    }
    private func addText() {
        guard let page = session.page else { return }
        finishMode()
        var item = PageElement(kind: .text)
        item.text = ""
        item.width = min(320, (page.width ?? 794) * 0.8)
        item.height = min(160, (page.height ?? 1123) * 0.5)
        item.x = ((page.width ?? 794) - item.width) / 2
        item.y = ((page.height ?? 1123) - item.height) / 2
        textElement = item
    }
    private func addShape(_ kind: PageElement.Kind) {
        guard let page = session.page else { return }
        finishMode()
        var item = PageElement(kind: kind)
        item.width = min(240, (page.width ?? 794) * 0.6)
        item.height = min(160, (page.height ?? 1123) * 0.4)
        item.x = ((page.width ?? 794) - item.width) / 2
        item.y = ((page.height ?? 1123) - item.height) / 2
        shapeElement = item
    }
    private func insertImageData(_ data: Data) async {
        guard !insertingImage else { return }
        insertingImage = true; defer { insertingImage = false }
        do {
            let image = try await Task.detached(priority: .userInitiated) { try ImportedImage.decode(data) }.value
            await session.insertImage(image); beginImagePlacement()
        } catch { session.error = error.localizedDescription }
    }
    private func selectRegion(_ rect: CGRect, _ path: UIBezierPath, _ action: PageSelectionAction) {
        guard let page = session.page else { return }
        if action == .enlarge || action == .shrink || action == .deleteContent {
            Task {
                if await session.transformSelection(inside: path, scale: action == .enlarge ? 1.1 : 0.9, deleting: action == .deleteContent) { finishMode() }
            }
            return
        }
        if action == .copyInk {
            guard session.toolSettings.includeHandwriting else { session.error = "Enable handwriting in the lasso filters to copy strokes."; return }
            do { try DocumentClipboard.copyInk(DocumentClipboard.selectedInk(session.drawing, inside: path)); finishMode() }
            catch { session.error = "No strokes to copy in this area, or the selection is too large." }
            return
        }
        if let selectionKind {
            finishMode()
            var item = PageElement(kind: selectionKind)
            item.x = rect.minX; item.y = rect.minY; item.width = rect.width; item.height = rect.height
            Task { await session.apply(.init(pageID: page.id, kind: .upsertElement, element: item)) }
        } else {
            let drawing = session.drawing; let data = session.backgroundData; let resources = session.resources
            Task {
                do {
                    let image = try await Task.detached(priority: .userInitiated) { try PageRenderer.capture(page, data: data, drawing: drawing, resources: resources, rect: rect, path: path) }.value
                    finishMode()
                    if action == .copyPhoto { UIPasteboard.general.image = image }
                    else { capture = image; captureShown = true }
                } catch { session.error = error.localizedDescription }
            }
        }
    }
    private var settingsForm: some View {
        NavigationStack {
            Form {
                Section("Palette") {
                    Toggle("Write with your finger", isOn: $finger)
                    Toggle("Show undo and redo", isOn: $showUndo)
                }
                Section("Visible tools — drag to reorder") {
                    ForEach(session.toolSettings.toolbarOrder) { item in
                        Toggle(isOn: Binding(get: { !session.toolSettings.hiddenTools.contains(item) }, set: { visible in
                            if visible { session.toolSettings.hiddenTools.remove(item) }
                            else { session.toolSettings.hiddenTools.insert(item) }
                        })) { Label(item.title, systemImage: item.symbol) }
                    }.onMove { source, destination in
                        session.toolSettings.toolbarOrder.move(fromOffsets: source, toOffset: destination)
                    }
                    Text("Order and visibility are preserved across launches. Instrument settings remain available at the right of the toolbar.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Quick settings") {
                    Toggle("Favorite colors on iPad", isOn: $showInkColor)
                    Toggle("Favorite widths on iPad", isOn: $showInkWidth)
                    Text("Tap a tool to select it, then tap it again to open its options.").font(.footnote)
                }
                Section("Turn pages") {
                    Picker("Direction", selection: $verticalPaging) { Text("Horizontal").tag(false); Text("Vertical").tag(true) }.pickerStyle(.segmented)
                    Text("Swipe when the page fits the screen. When zoomed in, the gesture pans the page.").font(.footnote)
                }
                Section("Gestures") { Text("Double-tap the page with a finger to fit it to the screen.") }
            }.navigationTitle("Writing").toolbar { ToolbarItem(placement: .navigationBarLeading) { EditButton() }; ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { settingsShown = false } } }
        }.presentationDetents([.medium, .large])
    }
    private var addPageForm: some View {
        NavigationStack {
            Form {
                Picker("Paper", selection: $addingTemplate) { ForEach(PageTemplate.allCases) { Text($0.title).tag($0) } }.pickerStyle(.inline)
                Button("Add page") {
                    Task {
                        guard await session.flush(), let id = await store.addPage(noteID: noteID, after: session.page?.id) else { return }
                        if var page = store.library.page(id: id) { page.template = addingTemplate; store.updatePage(page) }
                        await session.open(id); addShown = false
                    }
                }
            }.navigationTitle("New page").toolbar { Button("Cancel") { addShown = false } }
        }.presentationDetents([.medium, .large])
    }
    private func toggleBookmark() {
        guard var page = session.page else { return }
        page.bookmark = !(page.bookmark ?? false)
        Task { await session.apply(.init(pageID: page.id, kind: .setBookmark, bookmark: page.bookmark)) }
    }
    var currentIndex: Int { pages.firstIndex(where: { $0.id == session.page?.id }) ?? 0 }
    func navigate(_ delta: Int) async -> Bool {
        let index = currentIndex + delta
        guard pages.indices.contains(index), !session.busy else { return false }
        pageDirection = delta
        let id = pages[index].id
        await session.open(id)
        return session.page?.id == id
    }
    var pageList: some View { pagePanel(closeOnSelection: true) }
    private func pagePanel(closeOnSelection: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("Pages and bookmarks").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                Button { pagePanelEditing.toggle() } label: {
                    Label("Reorder pages", systemImage: "arrow.up.arrow.down").labelStyle(.iconOnly).frame(width: 44, height: 44)
                }.accessibilityAddTraits(pagePanelEditing ? .isSelected : [])
                Button { pagesShown = false } label: {
                    Label("Close previews", systemImage: "xmark").labelStyle(.iconOnly).frame(width: 44, height: 44)
                }.accessibilityIdentifier("editor.pages.close")
            }.padding(.horizontal, 8).padding(.vertical, 4).background(Color(uiColor: .secondarySystemBackground))
            Divider()
            List {
                ForEach(pages) { page in
                    HStack(spacing: 12) {
                        Button { Task { await session.open(page.id); if closeOnSelection && session.page?.id == page.id { pagesShown = false } } } label: {
                            HStack(spacing: 14) {
                                PageThumbnail(page: page, disk: store.disk).frame(width: 48, height: 64)
                                    .accessibilityHidden(true)
                                Text("Page \(page.index + 1)").foregroundStyle(.primary)
                                if page.bookmark == true { Image(systemName: "bookmark.fill").accessibilityLabel("Bookmark") }
                                Spacer()
                                if page.id == session.page?.id { Image(systemName: "checkmark.circle.fill").accessibilityLabel("Current page") }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Menu { pageActions(page) } label: {
                            Label("Page actions", systemImage: "ellipsis").labelStyle(.iconOnly).frame(width: 44, height: 44)
                        }.accessibilityLabel("Actions for page \(page.index + 1)")
                    }.padding(.vertical, 4).contextMenu { pageActions(page) }
                }
                .onMove { offsets, destination in
                    guard let source = offsets.first else { return }
                    store.movePage(pages[source].id, index: destination > source ? destination - 1 : destination)
                }
            }.listStyle(.plain)
                .environment(\.editMode, .constant(pagePanelEditing ? .active : .inactive))
                .confirmationDialog("Delete this page?", isPresented: $deleteShown, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { Task { if await session.flush(), let target = deletePageID, let id = store.removePage(target) { await session.open(id) } } }
                }
        }
    }
    @ViewBuilder private func pageActions(_ page: NotePage) -> some View {
        Button("Duplicate page", systemImage: "plus.square.on.square") {
            Task { if await session.flush(), let id = await store.addPage(noteID: noteID, after: page.id, duplicate: true) { await session.open(id) } }
        }
        Button("Delete page", systemImage: "trash", role: .destructive) { deletePageID = page.id; deleteShown = true }
            .disabled(pages.count < 2)
    }
    var exportForm: some View {
        NavigationStack {
            Form {
                if exporting { ProgressView("Export in progress…") }
                Stepper("From page \(first)", value: $first, in: 1...max(1, pages.count))
                Stepper("To page \(last)", value: $last, in: first...max(first, pages.count))
                Button("Export annotated PDF") { Task { await export(native: false) } }.disabled(exporting)
                Button("Back up native notebook (.catnote)") { Task { await export(native: true) } }.disabled(exporting)
                Button("Export readable context (.json)") { Task { await exportContext() } }.disabled(exporting)
                Text("Sharing lets you save to Files and its configured providers.").font(.caption)
            }.navigationTitle("Export").toolbar { Button("Cancel") { exportShown = false } }
        }
    }
    func export(native: Bool) async {
        Diagnostics.shared.record("document.export.begin", ["native": String(native)])
        guard await session.flush() else { return }
        guard !exporting else { return }
        exporting = true; defer { exporting = false }
        do {
            let selectedRange = (first - 1)...(max(first, last) - 1)
            let archive = try await store.archive(noteID, indices: native ? nil : selectedRange)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + (native ? ".catnote" : ".pdf"))
            let range = 0...(archive.pages.count - 1)
            try await Task.detached(priority: .userInitiated) {
                if native { try JSONEncoder().encode(archive).write(to: url, options: .atomic) }
                else { try PageRenderer.export(archive, indices: range, output: url) }
            }.value
            exportShown = false
            try await Task.sleep(nanoseconds: 300_000_000)
            share = ShareFile(url: url)
        } catch { session.error = error.localizedDescription }
    }
    func exportContext() async {
        guard !exporting, await session.flush() else { return }
        exporting = true; defer { exporting = false }
        await store.indexPDFText(in: noteID)
        do {
            let archive = try await store.archive(noteID)
            let folders = store.library.folderPath(to: archive.note.folderID)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
            try await Task.detached(priority: .utility) {
                let context = try DocumentContext(archive: archive, folderPath: folders)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(context).write(to: url, options: .atomic)
            }.value
            exportShown = false
            try await Task.sleep(nanoseconds: 300_000_000); share = ShareFile(url: url)
        } catch { session.error = error.localizedDescription }
    }
    func openSource() async {
        do {
            guard let name = session.page?.backgroundID, let data = try await store.disk.read(name) else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
            try data.write(to: url, options: .atomic); sourcePDF = ShareFile(url: url)
        } catch { session.error = error.localizedDescription }
    }
}

struct ShareFile: Identifiable { let id = UUID(); let url: URL }
struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
struct PageThumbnail: View {
    let page: NotePage
    let disk: DiskStore
    @State private var image: UIImage?
    var body: some View {
        Group { if let image { Image(uiImage: image).resizable().scaledToFit() } else { Rectangle().fill(.quaternary) } }
            .aspectRatio(PageRenderer.size(page), contentMode: .fit)
            .background(.white).clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
            .task(id: try? JSONEncoder().encode(page)) {
                do { image = try await disk.thumbnail(page, pixels: 640) }
                catch { image = nil }
            }
    }
}

private struct ToolButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            .background(configuration.isPressed ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.35)
    }
}
