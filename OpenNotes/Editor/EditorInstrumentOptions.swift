import SwiftUI

struct EditorInstrumentOptions: View {
    @ObservedObject var session: EditorSession
    var done: () -> Void
    @State private var hex = ""
    @State private var clearShown = false
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
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done", action: done) }
            }
        }
        .frame(idealWidth: 380, idealHeight: 620)
        .presentationDetents([.large])
        .confirmationDialog("Clear editable content on this page?", isPresented: $clearShown, titleVisibility: .visible) {
            Button("Clear page", role: .destructive) { Task { _ = await session.clearPage() } }
        } message: { Text("The paper and original PDF stay intact. You can undo this action.") }
    }

    @ViewBuilder private var writingOptions: some View {
        if isPen {
            optionSection("Tip") {
                Picker("Pen style", selection: Binding(get: { session.toolSettings.penStyle }, set: { session.toolSettings.applyPenPreset($0) })) {
                    Text("Ballpoint").tag(EditorToolSettings.PenStyle.ballpoint)
                    Text("Fountain").tag(EditorToolSettings.PenStyle.fountain)
                    Text("Brush").tag(EditorToolSettings.PenStyle.brush)
                }.pickerStyle(.menu).frame(minHeight: 44).accessibilityIdentifier("instrument.penStyle")
                if session.toolSettings.penStyle != .ballpoint || session.selectedTool == .fountainPen {
                    Picker("Pressure sensitivity", selection: Binding(get: {
                        session.toolSettings.pressureSensitivity ?? 0.5
                    }, set: { session.toolSettings.pressureSensitivity = $0 })) {
                        Text("Minimum").tag(0.0)
                        Text("25 %").tag(0.25)
                        Text("50 %").tag(0.5)
                        Text("75 %").tag(0.75)
                        Text("Maximum").tag(1.0)
                    }.pickerStyle(.menu).frame(minHeight: 44).accessibilityIdentifier("instrument.pressure")
                }
            }
        }
        if session.selectedTool != .marker && !(isPen && session.toolSettings.penStyle == .ballpoint) {
            optionSection("Apple Pencil") {
                Toggle("Pressure", isOn: Binding(get: { session.toolSettings.pressureEnabled ?? (!isPen || session.toolSettings.penStyle != .ballpoint) }, set: { session.toolSettings.pressureEnabled = $0 }))
                    .accessibilityIdentifier("instrument.pressureEnabled")
                Toggle("Tilt", isOn: Binding(get: { session.toolSettings.tiltEnabled ?? (session.selectedTool == .pencil) }, set: { session.toolSettings.tiltEnabled = $0 }))
                    .accessibilityIdentifier("instrument.tiltEnabled")
                Text("Uses pressure and tilt when supplied by your Pencil. Finger input has a constant pressure and an upright tip.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        optionSection("Stroke") {
            ColorPicker("Color", selection: Binding(get: { session.inkColor }, set: { session.setInkColor($0) }), supportsOpacity: false)
                .frame(minHeight: 44)
            HStack {
                Text("Width")
                Spacer()
                Text("\(documentWidth.formatted(.number.precision(.fractionLength(1)))) pt document")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { session.documentInkWidth }, set: { session.setDocumentInkWidth($0) }), in: session.documentInkWidthRange, step: 0.5)
                .accessibilityLabel("Stroke width")
            if session.selectedTool != .pencil {
                Divider()
                HStack {
                    Text("Stabilization")
                    Spacer()
                    Text("\(Int(session.toolSettings.stabilization(for: session.selectedTool))) %")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: {
                    session.toolSettings.stabilization(for: session.selectedTool)
                }, set: { session.toolSettings.setStabilization($0, for: session.selectedTool) }), in: 0...100, step: 1)
                    .accessibilityLabel("Stabilization")
                if isPen {
                    Picker("Pattern", selection: Binding(get: { session.toolSettings.inkPattern ?? .solid }, set: { session.toolSettings.inkPattern = $0 })) {
                        Text("Solid").tag(InkPattern.solid)
                        Text("Dashed").tag(InkPattern.dashed)
                        Text("Dotted").tag(InkPattern.dotted)
                    }.accessibilityIdentifier("instrument.pattern")
                    if session.toolSettings.penStyle != .ballpoint {
                        HStack { Text("Tip sharpness"); Spacer(); Text("\(Int((session.toolSettings.tipSharpness ?? 0) * 100)) %").monospacedDigit() }
                        Slider(value: Binding(get: { session.toolSettings.tipSharpness ?? 0 }, set: { session.toolSettings.tipSharpness = $0 }), in: 0...1)
                            .accessibilityLabel("Tip sharpness")
                    }
                }
                Text("Saved for this instrument. Higher values steady the stroke with more lag; 0% follows the tip directly.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        if session.selectedTool != .pencil {
            optionSection("Draw and hold") {
                Toggle("Pencil hold shapes", isOn: $session.toolSettings.shapeRecognitionEnabled).frame(minHeight: 44)
                Toggle("Snap lines to 45°", isOn: Binding(get: { session.toolSettings.shapeAngleSnap == true }, set: { session.toolSettings.shapeAngleSnap = $0 }))
                    .frame(minHeight: 44).disabled(!session.toolSettings.shapeRecognitionEnabled)
                Text("Draw, then hold the tip still. Once the shape appears, move the tip to adjust it and lift to keep it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        optionSection("Favorite colors") {
            HStack {
                TextField("#RRGGBB", text: $hex).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .accessibilityLabel("HEX color").accessibilityIdentifier("instrument.hex")
                Button("Apply") {
                    if let color = UIColor(presetHex: hex) { session.setInkColor(Color(color)) }
                }.disabled(UIColor(presetHex: hex) == nil).frame(minHeight: 44)
            }
            if !hex.isEmpty && UIColor(presetHex: hex) == nil { Text("Enter a valid color, such as #315BB1.").font(.caption).foregroundStyle(.red) }
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
                        Button("Move up", systemImage: "arrow.up") { moveFavorite(index, by: -1) }.disabled(index == 0)
                        Button("Move down", systemImage: "arrow.down") { moveFavorite(index, by: 1) }.disabled(index == colors.count - 1)
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            var updated = colors
                            guard updated.indices.contains(index) else { return }
                            updated.remove(at: index); session.setFavoriteColors(updated)
                        }.disabled(colors.count <= 1)
                    } label: {
                        Label("Options for favorite \(index + 1)", systemImage: "ellipsis")
                            .labelStyle(.iconOnly).frame(width: 44, height: 44).contentShape(Rectangle())
                    }.accessibilityIdentifier("instrument.favorite.options.\(index)")
                }
            }
            if colors.count < 12 {
                Button("Add current color", systemImage: "plus.circle") {
                    session.setFavoriteColors(colors + [session.paperInkColor.presetHex])
                }.frame(minHeight: 44)
            }
            Button("Reset this palette") {
                let key = session.selectedTool == .fountainPen ? "pen" : session.selectedTool.rawValue
                session.toolSettings.favoriteColors[key] = nil
            }.frame(minHeight: 44)
        }
    }

    private var eraserOptions: some View {
        optionSection("Erasing") {
            Picker("Mode", selection: Binding(get: {
                let mode = session.toolSettings.eraserMode
                return mode == .pixel || mode == .intelligent ? .standard : mode
            }, set: { session.toolSettings.eraserMode = $0 })) {
                Text("Precision").tag(EditorToolSettings.EraserMode.precision)
                Text("Standard").tag(EditorToolSettings.EraserMode.standard)
                Text("Stroke").tag(EditorToolSettings.EraserMode.stroke)
            }.pickerStyle(.menu).frame(minHeight: 44).accessibilityIdentifier("instrument.eraser.mode")
            HStack {
                Text("Size")
                Spacer()
                Text("\(Int(session.toolSettings.eraserWidth)) pt document").monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $session.toolSettings.eraserWidth, in: 4...100, step: 1).accessibilityLabel("Eraser size")
            Toggle("Erase pen and pencil", isOn: Binding(get: { session.toolSettings.erasePen != false }, set: { session.toolSettings.erasePen = $0 }))
            Toggle("Erase highlighter", isOn: Binding(get: { session.toolSettings.eraseHighlighter != false }, set: { session.toolSettings.eraseHighlighter = $0 }))
            Toggle("Return to previous tool", isOn: Binding(get: { session.toolSettings.eraserAutoDeselect == true }, set: { session.toolSettings.eraserAutoDeselect = $0 }))
            Text("Precision removes only the touched ink. Standard cuts a short section. Stroke removes a complete stroke. Size stays constant in page units.")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Clear page", role: .destructive) { clearShown = true }.frame(minHeight: 44)
        }
    }
    @ViewBuilder private var lassoOptions: some View {
        optionSection("Outline") {
            Picker("Selection shape", selection: $session.toolSettings.lassoShape) {
                Text("Freeform").tag(EditorToolSettings.LassoShape.freeform)
                Text("Rectangle").tag(EditorToolSettings.LassoShape.rectangle)
            }.pickerStyle(.segmented)
        }
        optionSection("Include in selection") {
            Toggle("Handwriting", isOn: $session.toolSettings.includeHandwriting)
            Toggle("Text", isOn: Binding(get: { session.toolSettings.includeText != false }, set: { session.toolSettings.includeText = $0 }))
            Toggle("Images", isOn: $session.toolSettings.includeImages)
            Toggle("Sticky note", isOn: $session.toolSettings.includeStickyNotes)
            Text("Outline an area, then move the selection. Long press to capture the visible area.")
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
