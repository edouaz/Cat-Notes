import SwiftUI

struct EditorInstrumentOptions: View {
    @ObservedObject var session: EditorSession
    var done: () -> Void
    private var colors: [String] { session.toolSettings.colors(for: session.selectedTool) }
    private var isPen: Bool { session.selectedTool == .pen || session.selectedTool == .fountainPen }
    private var documentWidth: Double { session.documentInkWidth }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if session.selectedTool.isWritingTool || session.selectedTool == .eraser {
                    InkPreview(session: session)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Color(uiColor: .systemBackground))
                    Divider()
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if session.selectedTool.isWritingTool {
                            writingOptions
                        } else if session.selectedTool == .eraser {
                            eraserOptions
                        } else {
                            lassoOptions
                        }
                    }.padding(16)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .accessibilityIdentifier("instrument.options.scroll")
            }
            .navigationTitle("Instrument").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Terminé", action: done) }
            }
        }
        .frame(idealWidth: 380, idealHeight: 620)
        .presentationDetents([.large])
    }

    @ViewBuilder private var writingOptions: some View {
        if isPen {
            optionSection("Pointe") {
                Picker("Type de stylo", selection: $session.toolSettings.penStyle) {
                    Text("Bille").tag(EditorToolSettings.PenStyle.ballpoint)
                    Text("Plume").tag(EditorToolSettings.PenStyle.fountain)
                    Text("Pinceau").tag(EditorToolSettings.PenStyle.brush)
                }.pickerStyle(.menu).frame(minHeight: 44)
                if session.toolSettings.penStyle != .ballpoint || session.selectedTool == .fountainPen {
                    Picker("Sensibilité à la pression", selection: Binding(get: {
                        session.toolSettings.pressureSensitivity ?? 0.5
                    }, set: { session.toolSettings.pressureSensitivity = $0 })) {
                        Text("Minimale").tag(0.0)
                        Text("25 %").tag(0.25)
                        Text("50 %").tag(0.5)
                        Text("75 %").tag(0.75)
                        Text("Maximale").tag(1.0)
                    }.pickerStyle(.menu).frame(minHeight: 44).accessibilityIdentifier("instrument.pressure")
                }
            }
        }
        optionSection("Trait") {
            ColorPicker("Couleur", selection: Binding(get: { session.inkColor }, set: { session.setInkColor($0) }), supportsOpacity: false)
                .frame(minHeight: 44)
            HStack {
                Text("Épaisseur")
                Spacer()
                Text("\(documentWidth.formatted(.number.precision(.fractionLength(1)))) pt document")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { session.documentInkWidth }, set: { session.setDocumentInkWidth($0) }), in: session.documentInkWidthRange, step: 0.5)
                .accessibilityLabel("Épaisseur du trait")
            if session.selectedTool != .pencil {
                Divider()
                HStack {
                    Text("Stabilisation")
                    Spacer()
                    Text("\(Int(session.toolSettings.stabilization(for: session.selectedTool))) %")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: {
                    session.toolSettings.stabilization(for: session.selectedTool)
                }, set: { session.toolSettings.setStabilization($0, for: session.selectedTool) }), in: 0...100, step: 1)
                    .accessibilityLabel("Stabilisation")
                Text("Réglage mémorisé pour cet instrument. Lissage appliqué au lever ; 0 % conserve le geste original.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        if session.selectedTool != .pencil {
            optionSection("Dessiner et maintenir") {
                Toggle("Formes par maintien du Pencil", isOn: $session.toolSettings.shapeRecognitionEnabled).frame(minHeight: 44)
                Toggle("Aligner les lignes à 45°", isOn: Binding(get: { session.toolSettings.shapeAngleSnap == true }, set: { session.toolSettings.shapeAngleSnap = $0 }))
                    .frame(minHeight: 44).disabled(!session.toolSettings.shapeRecognitionEnabled)
                Text("Dessinez, puis maintenez la pointe immobile. L’aperçu devient une forme ; levez le Pencil pour la conserver ou reprenez le tracé pour l’annuler.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        optionSection("Couleurs favorites") {
            ForEach(Array(colors.enumerated()), id: \.offset) { index, _ in
                HStack(spacing: 8) {
                    ColorPicker("Favorite \(index + 1)", selection: Binding(get: {
                        let current = colors
                        return Color(current.indices.contains(index) ? UIColor(presetHex: current[index]) ?? .black : .black)
                    }, set: { color in
                        var updated = colors
                        guard updated.indices.contains(index) else { return }
                        updated[index] = UIColor(color).presetHex
                        session.setFavoriteColors(updated)
                    }), supportsOpacity: false).frame(minHeight: 44)
                    Menu {
                        Button("Monter", systemImage: "arrow.up") { moveFavorite(index, by: -1) }.disabled(index == 0)
                        Button("Descendre", systemImage: "arrow.down") { moveFavorite(index, by: 1) }.disabled(index == colors.count - 1)
                        Button("Supprimer", systemImage: "trash", role: .destructive) {
                            var updated = colors
                            guard updated.indices.contains(index) else { return }
                            updated.remove(at: index); session.setFavoriteColors(updated)
                        }
                    } label: {
                        Label("Options de la favorite \(index + 1)", systemImage: "ellipsis")
                            .labelStyle(.iconOnly).frame(width: 44, height: 44).contentShape(Rectangle())
                    }.accessibilityIdentifier("instrument.favorite.options.\(index)")
                }
            }
            if colors.count < 64 {
                Button("Ajouter la couleur actuelle", systemImage: "plus.circle") {
                    session.setFavoriteColors(colors + [session.paperInkColor.presetHex])
                }.frame(minHeight: 44)
            }
        }
    }

    private var eraserOptions: some View {
        optionSection("Effacement") {
            Picker("Mode", selection: $session.toolSettings.eraserMode) {
                Text("Trait entier").tag(EditorToolSettings.EraserMode.stroke)
                Text("Pixel").tag(EditorToolSettings.EraserMode.pixel)
                Text("Intelligent").tag(EditorToolSettings.EraserMode.intelligent)
            }.pickerStyle(.menu).frame(minHeight: 44).accessibilityIdentifier("instrument.eraser.mode")
            HStack {
                Text("Taille")
                Spacer()
                Text("\(Int(session.toolSettings.eraserWidth)) pt document").monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $session.toolSettings.eraserWidth, in: 4...100, step: 1).accessibilityLabel("Taille de la gomme")
            Text("Intelligent : supprime un petit trait contenu dans la gomme ; coupe la partie touchée d’un grand trait. Les images et post-it restent intacts.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var lassoOptions: some View {
        optionSection("Contour") {
            Picker("Forme de sélection", selection: $session.toolSettings.lassoShape) {
                Text("Libre").tag(EditorToolSettings.LassoShape.freeform)
                Text("Rectangle").tag(EditorToolSettings.LassoShape.rectangle)
            }.pickerStyle(.segmented)
        }
        optionSection("Inclure dans la sélection") {
            Toggle("Écriture manuscrite", isOn: $session.toolSettings.includeHandwriting)
            Toggle("Texte", isOn: Binding(get: { session.toolSettings.includeText != false }, set: { session.toolSettings.includeText = $0 }))
            Toggle("Images", isOn: $session.toolSettings.includeImages)
            Toggle("Post-it", isOn: $session.toolSettings.includeStickyNotes)
            Text("Tracez un contour, puis déplacez la sélection. Un appui long propose aussi la capture de la zone visible.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func optionSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
            content()
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
    private func moveFavorite(_ index: Int, by distance: Int) {
        var updated = colors
        let target = index + distance
        guard updated.indices.contains(index), updated.indices.contains(target) else { return }
        updated.swapAt(index, target)
        session.setFavoriteColors(updated)
    }
}
