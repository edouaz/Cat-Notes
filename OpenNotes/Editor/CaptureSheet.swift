import SwiftUI

struct CaptureSheet: View {
    let image: UIImage
    let insert: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var share: ShareFile?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("Capture preview")
                    ViewThatFits(in: .horizontal) {
                        if !typeSize.isAccessibilitySize {
                            HStack(spacing: 12) { captureActions }.fixedSize(horizontal: true, vertical: false)
                        }
                        VStack(spacing: 12) { captureActions }
                    }
                    .buttonStyle(.bordered).buttonBorderShape(.roundedRectangle)
                }.padding().frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.navigationTitle("Capture").navigationBarTitleDisplayMode(.inline).toolbar { Button("Close") { dismiss() } }
                .sheet(item: $share) { ActivitySheet(url: $0.url) }
                .alert("Capture", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        }
    }
    @ViewBuilder private var captureActions: some View {
        Button { UIPasteboard.general.image = image; dismiss() } label: {
            Text("Copy").frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
        }.accessibilityIdentifier("capture.copy")
        Button { insert(); dismiss() } label: {
            Text("Insert on page").frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
        }.accessibilityIdentifier("capture.insert")
        Button {
            do {
                guard let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("Capture.png")
                try data.write(to: url, options: .atomic); share = ShareFile(url: url)
            } catch { self.error = error.localizedDescription }
        } label: {
            Text("Share").frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
        }.accessibilityIdentifier("capture.share")
    }
}
