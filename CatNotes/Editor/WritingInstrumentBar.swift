import SwiftUI
import PencilKit

struct WritingInstrumentBar: View {
    @ObservedObject var session: EditorSession
    var insertImage: () -> Void = {}
    var addStickyNote: () -> Void = {}
    @AppStorage("showUndo") private var showUndo = true
    @AppStorage("showInkColor") private var showColor = true
    @AppStorage("showInkWidth") private var showWidth = true
    @State private var settingsFor: DrawingToolKind?
    @State private var globalSettings = false
    @State private var colorEditor: Int?
    @State private var editedColor = Color.black
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: [String] { session.toolSettings.colors(for: session.selectedTool) }
    private var widths: [Double] { session.selectedTool == .marker ? [1, 2, 4] : [1, 3, 6] }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 2) {
                history
                instruments
                if showsContext { separator; contextControls }
                settingsButton
            }.fixedSize(horizontal: true, vertical: false)
            VStack(spacing: 0) {
                HStack(spacing: 2) {
                    history
                    ScrollView(.horizontal, showsIndicators: false) { instruments }
                    settingsButton
                }
                if showsContext {
                    HStack(spacing: 0) { Spacer(minLength: 0); contextControls; Spacer(minLength: 0) }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .bottom) { Divider() }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: session.selectedTool)
        .onChange(of: session.selectedTool) { _ in settingsFor = nil; colorEditor = nil }
    }

    private var showsContext: Bool { !session.selectedTool.isWritingTool || showColor || showWidth }
    private var separator: some View { Divider().frame(height: 24).padding(.horizontal, 4) }
    @ViewBuilder private var history: some View {
        if showUndo {
            HStack(spacing: 0) {
                Button { session.canvas.undoManager?.undo() } label: { toolLabel("Annuler", "arrow.uturn.backward") }
                    .keyboardShortcut("z", modifiers: .command).disabled(!session.canUndo)
                Button { session.canvas.undoManager?.redo() } label: { toolLabel("Rétablir", "arrow.uturn.forward") }
                    .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!session.canRedo)
            }
            separator
        }
    }
    private var instruments: some View {
        HStack(spacing: 0) {
            ForEach(session.toolSettings.toolbarOrder.filter { !session.toolSettings.hiddenTools.contains($0) }) { item in
                if let tool = item.drawingTool { instrument(tool, item: item) }
                else {
                    Button { item == .image ? insertImage() : addStickyNote() } label: { toolLabel(item.title, item.symbol) }
                        .accessibilityIdentifier(item == .image ? "editor.image" : "editor.sticky")
                }
            }
        }
    }
    private var settingsButton: some View {
        Button { globalSettings = true } label: { toolLabel("Réglages de l’instrument", "slider.horizontal.3") }
            .popover(isPresented: $globalSettings, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                EditorInstrumentOptions(session: session) { globalSettings = false }
            }
    }
    @ViewBuilder private var contextControls: some View {
        if session.selectedTool.isWritingTool {
            HStack(spacing: 0) {
                if showColor {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(Array(colors.enumerated()), id: \.offset) { index, hex in colorButton(index, hex: hex) }
                        }
                    }.frame(width: 88, height: 44)
                    Button {
                        editedColor = session.inkColor; colorEditor = colors.count
                    } label: { toolLabel("Ajouter une couleur favorite", "plus.circle") }
                        .disabled(colors.count >= 64)
                        .popover(isPresented: colorBinding(colors.count), attachmentAnchor: .rect(.bounds), arrowEdge: .top) { colorOptions(adding: true) }
                }
                if showWidth {
                    ForEach(widths, id: \.self) { width in widthButton(width) }
                }
            }
        } else if session.selectedTool == .eraser {
            HStack(spacing: 8) {
                Picker("Mode de gomme", selection: $session.toolSettings.eraserMode) {
                    Text("Trait entier").tag(EditorToolSettings.EraserMode.stroke)
                    Text("Pixel").tag(EditorToolSettings.EraserMode.pixel)
                    Text("Intelligent").tag(EditorToolSettings.EraserMode.intelligent)
                }.pickerStyle(.menu).labelsHidden().frame(minHeight: 44)
                    .accessibilityIdentifier("instrument.eraser.quickMode")
                Slider(value: $session.toolSettings.eraserWidth, in: 4...100, step: 1)
                    .frame(width: 84).accessibilityLabel("Taille de la gomme rapide")
                Text("\(Int(session.toolSettings.eraserWidth)) pt").font(.caption).monospacedDigit()
            }
        } else {
            HStack(spacing: 8) {
                Picker("Forme du lasso", selection: $session.toolSettings.lassoShape) {
                    Label("Libre", systemImage: "lasso").tag(EditorToolSettings.LassoShape.freeform)
                    Label("Rectangle", systemImage: "rectangle.dashed").tag(EditorToolSettings.LassoShape.rectangle)
                }.pickerStyle(.menu).labelsHidden().frame(minHeight: 44)
                    .accessibilityIdentifier("instrument.lasso.quickShape")
                Menu {
                    Toggle("Écriture manuscrite", isOn: $session.toolSettings.includeHandwriting)
                    Toggle("Texte", isOn: Binding(get: { session.toolSettings.includeText != false }, set: { session.toolSettings.includeText = $0 }))
                    Toggle("Images", isOn: $session.toolSettings.includeImages)
                    Toggle("Post-it", isOn: $session.toolSettings.includeStickyNotes)
                } label: {
                    Label("Inclure", systemImage: "line.3.horizontal.decrease.circle").frame(minHeight: 44)
                }.accessibilityIdentifier("instrument.lasso.quickFilter")
            }
        }
    }
    private func widthButton(_ width: Double) -> some View {
        let active = abs(session.inkWidth - width) < 0.01
        let ink = session.tool as? PKInkingTool
        let documentWidth = Double(PKInkingTool(ink?.inkType ?? .pen, color: session.paperInkColor,
            width: width * (session.selectedTool == .marker ? 4 : 1)).width)
        return Button { session.inkWidth = width } label: {
            VStack(spacing: 2) {
                Circle().fill(Color.primary).frame(width: min(14, max(3, documentWidth)), height: min(14, max(3, documentWidth)))
                    .frame(height: 14)
                Text(documentWidth.formatted()).font(.caption2).monospacedDigit()
            }.frame(width: 44, height: 44)
                .background(active ? CatNotesStyle.accent.opacity(0.12) : .clear, in: Circle())
                .overlay { Circle().strokeBorder(active ? CatNotesStyle.accent : Color.clear, lineWidth: 1.5).padding(2) }
                .contentShape(Rectangle())
        }.accessibilityLabel("Épaisseur \(documentWidth.formatted()) points")
            .accessibilityValue("\(documentWidth.formatted()) points du document à 100 %")
            .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func toolLabel(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol).labelStyle(.iconOnly).font(.title3)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge).frame(width: 44, height: 44).contentShape(Rectangle())
    }
    private func instrument(_ tool: DrawingToolKind, item: EditorToolSettings.ToolbarItem) -> some View {
        let active = session.selectedTool == tool || (tool == .pen && session.selectedTool == .fountainPen)
        return Button {
            if active { settingsFor = tool } else { session.selectedTool = tool }
        } label: {
            toolLabel(item.title, item.symbol)
                .foregroundStyle(active ? CatNotesStyle.accent : Color.primary)
                .background(active ? CatNotesStyle.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottom) { if active { Capsule().fill(Color.primary).frame(width: 16, height: 2).padding(.bottom, 3) } }
        }.accessibilityHint(active ? "Ouvrir les réglages de cet instrument" : "Activer cet instrument")
            .accessibilityAddTraits(active ? .isSelected : [])
            .animation(reduceMotion ? nil : .interactiveSpring(response: 0.22, dampingFraction: 0.9), value: active)
            .contextMenu {
                Button("Réglages de \(item.title)", systemImage: "slider.horizontal.3") {
                    session.selectedTool = tool
                    globalSettings = true
                }
            }
            .popover(isPresented: Binding(get: { settingsFor == tool }, set: { if !$0 { settingsFor = nil } }), attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                EditorInstrumentOptions(session: session) { settingsFor = nil }
            }
    }
    private func colorBinding(_ index: Int) -> Binding<Bool> {
        Binding(get: { colorEditor == index }, set: { if !$0 { colorEditor = nil } })
    }
    private func colorButton(_ index: Int, hex: String) -> some View {
        let selected = UIColor(session.inkColor).presetHex == hex
        return Button {
            if selected { editedColor = session.inkColor; colorEditor = index }
            else { session.setInkColor(Color(UIColor(presetHex: hex) ?? .black)) }
        } label: {
            Circle().fill(Color(UIColor(presetHex: hex) ?? .black)).frame(width: 24, height: 24)
                .overlay { Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1) }
                .overlay { if selected { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white).shadow(color: .black, radius: 1) } }
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.accessibilityLabel("Couleur favorite \(index + 1)").accessibilityValue(hex)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .popover(isPresented: colorBinding(index), attachmentAnchor: .rect(.bounds), arrowEdge: .top) { colorOptions(adding: false) }
    }
    private func colorOptions(adding: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(adding ? "Nouvelle favorite" : "Modifier la favorite").font(.headline)
            ColorPicker("Couleur", selection: $editedColor, supportsOpacity: false).frame(minHeight: 44)
            Button(adding ? "Ajouter" : "Enregistrer") {
                var updated = colors
                if let index = colorEditor, updated.indices.contains(index) { updated[index] = UIColor(editedColor).presetHex }
                else { updated.append(UIColor(editedColor).presetHex) }
                session.setFavoriteColors(updated); session.setInkColor(editedColor); colorEditor = nil
            }.buttonStyle(.borderedProminent).frame(minHeight: 44)
            Button("Annuler") { colorEditor = nil }.frame(minHeight: 44)
        }.padding(20).frame(idealWidth: 300)
    }
}
