import SwiftUI
import PDFKit

struct PDFReaderScreen: View {
    let url: URL
    @State private var selectedPage = 0
    @State private var outlineShown = false
    var body: some View {
        NavigationStack {
            NavigablePDF(url: url, selectedPage: selectedPage)
                .navigationTitle("PDF source")
                .toolbar { Button("Sommaire") { outlineShown = true } }
                .sheet(isPresented: $outlineShown) {
                    NavigationStack {
                        List(outline, id: \.index) { item in
                            Button(item.title) { selectedPage = item.page; outlineShown = false }
                        }.navigationTitle("Sommaire PDF").overlay {
                            if outline.isEmpty { Text("Ce PDF ne contient pas de sommaire.").foregroundStyle(.secondary) }
                        }.toolbar { Button("Fermer") { outlineShown = false } }
                    }
                }
        }
    }
    var outline: [(index: Int, title: String, page: Int)] {
        guard let document = PDFDocument(url: url), let root = document.outlineRoot else { return [] }
        var result: [(Int, String, Int)] = []
        func walk(_ node: PDFOutline, depth: Int) {
            guard depth < 30 else { return }
            if let page = node.destination?.page ?? (node.action as? PDFActionGoTo)?.destination.page {
                result.append((result.count, String(repeating: "  ", count: depth) + (node.label ?? "Page"), document.index(for: page)))
            }
            for i in 0..<node.numberOfChildren { if let child = node.child(at: i) { walk(child, depth: depth + 1) } }
        }
        walk(root, depth: 0); return result
    }
}
struct NavigablePDF: UIViewRepresentable {
    let url: URL
    let selectedPage: Int
    func makeUIView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.document = PDFDocument(url: url); return view }
    func updateUIView(_ view: PDFView, context: Context) { if let page = view.document?.page(at: selectedPage), view.currentPage != page { view.go(to: page) } }
}
