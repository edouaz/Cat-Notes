import SwiftUI
import PhotosUI

struct ElementSheet: View {
    @ObservedObject var session: EditorSession
    @Environment(\.dismiss) private var dismiss
    @State private var element = PageElement(kind: .image)
    @State private var photo: PhotosPickerItem?
    @State private var importer = false
    @State private var image: UIImage?
    @State private var saving = false
    @State private var crop = false
    @State private var cropLeft = 0.0
    @State private var cropTop = 0.0
    @State private var cropRight = 1.0
    @State private var cropBottom = 1.0
    private var editingExistingImage: Bool { session.page?.elements?.contains { $0.id == element.id } == true }
    var body: some View {
        NavigationStack {
            Form {
                Section("Élément") {

                    if element.kind == .image {
                        PhotosPicker("Depuis Photos", selection: $photo, matching: .images)
                        Button("Depuis Fichiers") { importer = true }
                        Button("Coller une image") {
                            guard let pasted = UIPasteboard.general.image else { session.error = "Le presse-papiers ne contient pas d’image."; return }
                            image = pasted
                        }
                        if let image { Image(uiImage: image).resizable().scaledToFit().frame(height: 160) }
                        Toggle("Recadrer", isOn: $crop)
                        if crop {
                            VStack(alignment: .leading) { Text("Gauche"); Slider(value: $cropLeft, in: 0...0.45) { Text("Gauche") } }
                            VStack(alignment: .leading) { Text("Haut"); Slider(value: $cropTop, in: 0...0.45) { Text("Haut") } }
                            VStack(alignment: .leading) { Text("Droite"); Slider(value: $cropRight, in: 0.55...1) { Text("Droite") } }
                            VStack(alignment: .leading) { Text("Bas"); Slider(value: $cropBottom, in: 0.55...1) { Text("Bas") } }
                        }
                    }
                }
                Text("Après insertion, déplacez l’image sur la page et utilisez ses poignées ou un pincement pour la redimensionner.").font(.footnote).foregroundStyle(.secondary)
                if let page = session.page {
                    Section("Éléments de la page") {
                        ForEach(Array((page.elements ?? []).filter { $0.kind == .image }.enumerated()), id: \.element.id) { index, item in
                            Button("Modifier l’image \(index + 1)") {
                                element = item
                                if let resource = item.resource { Task {
                                    do {
                                        guard let data = try await session.store.disk.read(resource) else { throw CocoaError(.fileNoSuchFile) }
                                        image = try await Task.detached(priority: .userInitiated) { try ImportedImage.decode(data) }.value
                                    } catch { session.error = error.localizedDescription }
                                } }
                            }.swipeActions {
                                Button("Supprimer", role: .destructive) { var updated = page; updated.elements?.removeAll { $0.id == item.id }; Task { await session.refresh(updated) } }
                            }
                        }
                    }
                }
                if saving { ProgressView("Préparation de l’image…") }
            }.navigationTitle(editingExistingImage ? "Modifier l’image" : "Insérer une image").interactiveDismissDisabled(saving)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) { Button(editingExistingImage ? "Enregistrer" : "Ajouter") { Task { await save() } }.disabled(saving || image == nil) }
                }
                .onChange(of: photo) { item in Task {
                    do {
                        guard let data = try await item?.loadTransferable(type: Data.self) else { return }
                        image = try await Task.detached(priority: .userInitiated) { try ImportedImage.decode(data) }.value
                    } catch { session.error = error.localizedDescription }
                } }
                .fileImporter(isPresented: $importer, allowedContentTypes: [.image]) { result in
                    Task { do {
                        let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size > 0, size <= 150_000_000 else { throw CocoaError(.fileReadTooLarge) }
                        let data = try await Task.detached { try Data(contentsOf: url) }.value
                        image = try await Task.detached(priority: .userInitiated) { try ImportedImage.decode(data) }.value
                    } catch { session.error = error.localizedDescription } }
                }
        }
    }
    func save() async {
        guard !saving, let image else { return }
        saving = true; defer { saving = false }
        guard await session.flush(), var page = session.page else { return }
        do {
            let cropRect = CGRect(x: cropLeft, y: cropTop, width: cropRight - cropLeft, height: cropBottom - cropTop)
            let shouldCrop = crop
            let (data, size) = try await Task.detached(priority: .userInitiated) {
                try ImportedImage.encode(image, crop: shouldCrop ? cropRect : nil)
            }.value
            let maxWidth = max(44, (page.width ?? 794) - element.x)
            let maxHeight = max(44, (page.height ?? 1123) - element.y)
            element.width = min(element.width, maxWidth)
            element.height = element.width * size.height / max(1, size.width)
            if element.height > maxHeight { element.width *= maxHeight / element.height; element.height = maxHeight }
            let name = UUID().uuidString + ".png"
            try await session.store.disk.write(data, name: name); element.resource = name
            var elements = page.elements ?? []
            if let index = elements.firstIndex(where: { $0.id == element.id }) { elements[index] = element } else { elements.append(element) }
            page.elements = elements
            session.store.updatePage(page)
            guard await session.store.flush() else { return }
            await session.open(page.id)
            dismiss()
        } catch { session.error = error.localizedDescription }
    }
}
