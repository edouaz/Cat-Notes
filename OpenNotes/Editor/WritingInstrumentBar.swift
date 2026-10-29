import SwiftUI

struct WritingInstrumentBar: View {
    @ObservedObject var session: EditorSession
    var insert: () -> Void = {}
    var sticky: () -> Void = {}
    @State private var optionsShown = false
    @State private var customizationShown = false
    @AppStorage("undoPlacement") private var undoPlacement = "left"
    @AppStorage("toolPaletteDock") private var dock = "top"
    @AppStorage("toolPaletteVisible") private var paletteVisible = true
    private var writingTools: [EditorToolSettings.ToolbarItem] {
        session.toolSettings.toolbarOrder.filter { [.pen, .pencil, .marker, .eraser].contains($0) }
    }
    private var instruments: [EditorToolSettings.ToolbarItem] {
        [.lasso] + writingTools.filter { !session.toolSettings.hiddenTools.contains($0) }
    }
    var body: some View {
        HStack(spacing: 0) {
            if undoPlacement == "left" { HStack(spacing: 0) { historyButtons }.buttonStyle(.plain); Divider().frame(height: 24) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(instruments) { item in
                        if let tool = item.drawingTool {
                            let selected = session.selectedTool == tool
                            Button {
                                session.stickyInsertionColor = nil
                                if selected { optionsShown = true }
                                else { session.selectedTool = tool; paletteVisible = true }
                            } label: {
                                InstrumentLabel(title: item.title, symbol: item.symbol)
                                    .foregroundStyle(selected ? OpenNotesStyle.accent : Color.primary)
                                    .background(selected ? OpenNotesStyle.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 12))
                            }.accessibilityAddTraits(selected ? .isSelected : [])
                                .accessibilityHint(selected ? "Tap again for options" : "Select tool")
                                .accessibilityIdentifier("editor.tool.\(item.rawValue)")
                        }
                    }
                    Divider().frame(height: 24)
                    Button(action: insert) { InstrumentLabel(title: "Insert", symbol: "plus.square") }.accessibilityIdentifier("editor.insert")
                    Button(action: sticky) { InstrumentLabel(title: "Sticky note", symbol: "note.text") }.accessibilityIdentifier("editor.tool.stickyNote")
                    Button { paletteVisible.toggle() } label: { InstrumentLabel(title: paletteVisible ? "Hide writing tools" : "Show writing tools", symbol: "rectangle.bottomhalf.inset.filled") }
                    Button { optionsShown = true } label: { InstrumentLabel(title: "Tool options", symbol: "slider.horizontal.3") }.accessibilityIdentifier("editor.toolOptions")
                    Menu {
                        Button("Customize toolbar", systemImage: "slider.horizontal.3") { customizationShown = true }
                        Picker("Undo and Redo", selection: $undoPlacement) { Text("Left").tag("left"); Text("Right").tag("right") }
                        Picker("Tool palette edge", selection: $dock) {
                            ForEach(["top", "bottom", "left", "right"], id: \.self) { Text($0.capitalized).tag($0) }
                        }
                    } label: { InstrumentLabel(title: "Toolbar layout", symbol: "ellipsis") }.accessibilityIdentifier("editor.toolbarLayout")
                }.padding(.horizontal, 12).padding(.vertical, 6)
            }.frame(height: 58).buttonStyle(.plain)
            if undoPlacement == "right" { Divider().frame(height: 24); HStack(spacing: 0) { historyButtons }.buttonStyle(.plain) }
        }
        .background(OpenNotesStyle.chrome).overlay(alignment: .bottom) { Divider() }
        .popover(isPresented: $optionsShown) { EditorInstrumentOptions(session: session) { optionsShown = false } }
        .sheet(isPresented: $customizationShown) {
            NavigationStack {
                List {
                    Section { Label("Lasso stays first", systemImage: "lasso") }
                    Section("Writing tools · drag to reorder") {
                        ForEach(writingTools) { item in
                            Toggle(item.title, isOn: Binding(get: { !session.toolSettings.hiddenTools.contains(item) }, set: { visible in
                                if visible { session.toolSettings.hiddenTools.remove(item) }
                                else { session.toolSettings.hiddenTools.insert(item) }
                            }))
                        }.onMove { source, destination in
                            var values = writingTools
                            values.move(fromOffsets: source, toOffset: destination)
                            session.toolSettings.toolbarOrder = values + session.toolSettings.toolbarOrder.filter { !values.contains($0) }
                        }
                    }
                    Button("Reset toolbar") { session.toolSettings.toolbarOrder = EditorToolSettings.ToolbarItem.allCases; session.toolSettings.hiddenTools = [.pencil]; dock = "top"; undoPlacement = "left"; paletteVisible = true }
                }.environment(\.editMode, .constant(.active))
                    .navigationTitle("Customize toolbar")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { customizationShown = false } } }
            }
        }
    }
    private var historyButtons: some View {
        Group {
            Button { session.canvas.undoManager?.undo() } label: { InstrumentLabel(title: "Undo", symbol: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: .command).disabled(!session.canUndo)
            Button { session.canvas.undoManager?.redo() } label: { InstrumentLabel(title: "Redo", symbol: "arrow.uturn.forward") }
                .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!session.canRedo)
        }
    }
}

struct ActiveWritingPalette: View {
    @ObservedObject var session: EditorSession
    @AppStorage("toolPaletteDock") private var dock = "top"
    private var vertical: Bool { dock == "left" || dock == "right" }
    private var eraserMode: EditorToolSettings.EraserMode {
        let mode = session.toolSettings.eraserMode
        return mode == .pixel || mode == .intelligent ? .standard : mode
    }
    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            Image(systemName: "ellipsis").rotationEffect(.degrees(vertical ? 0 : 90)).foregroundStyle(.secondary).frame(width: 28, height: 28).accessibilityLabel("Drag tool palette to an edge")
            if session.stickyInsertionColor != nil {
                ForEach(["#FFE66D", "#A8E6CF", "#FFAFCC", "#A9D6FF", "#D9B8FF"], id: \.self) { hex in
                    Button { session.stickyInsertionColor = hex } label: {
                        Circle().fill(Color(UIColor(presetHex: hex) ?? .yellow)).frame(width: 26, height: 26).padding(8)
                            .overlay { Circle().strokeBorder(session.stickyInsertionColor == hex ? OpenNotesStyle.accent : .clear, lineWidth: 2) }
                    }.accessibilityLabel("Sticky background \(hex)")
                }
            } else if session.selectedTool.isWritingTool {
                ForEach(Array(session.toolSettings.colors(for: session.selectedTool).enumerated()), id: \.offset) { _, hex in
                    Button { session.setInkColor(Color(UIColor(presetHex: hex) ?? .black)) } label: {
                        Circle().fill(Color(UIColor(presetHex: hex) ?? .black)).frame(width: 22, height: 22)
                            .overlay { Circle().strokeBorder(Color.primary.opacity(0.25)) }
                            .padding(8).background(session.paperInkColor.presetHex == hex ? OpenNotesStyle.accent.opacity(0.14) : .clear, in: Circle())
                    }.accessibilityLabel("Ink color \(hex)")
                }
                ForEach([1.0, 3.0, 6.0], id: \.self) { width in
                    Button { session.setDocumentInkWidth(width * (session.selectedTool == .marker ? 4 : 1)) } label: {
                        Circle().fill(Color.primary).frame(width: width + 3, height: width + 3).frame(width: 36, height: 36)
                    }.accessibilityLabel("Width \(Int(width))")
                }
            } else if session.selectedTool == .eraser {
                ForEach([EditorToolSettings.EraserMode.precision, .standard, .stroke], id: \.self) { mode in
                    Button(mode == .precision ? "Precision" : mode == .standard ? "Standard" : "Stroke") { session.toolSettings.eraserMode = mode }
                        .font(.caption.weight(.medium)).frame(minWidth: 44, minHeight: 36)
                        .foregroundStyle(eraserMode == mode ? OpenNotesStyle.accent : .primary)
                }
            } else {
                Button("Freehand") { session.toolSettings.lassoShape = .freeform }.frame(minWidth: 44, minHeight: 36)
                Button("Rectangle") { session.toolSettings.lassoShape = .rectangle }.frame(minWidth: 44, minHeight: 36)
            }
        }.buttonStyle(.plain).padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.08)) }
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
            .accessibilityIdentifier("editor.activePalette")
    }
}

private struct InstrumentLabel: View {
    let title: String
    let symbol: String
    var body: some View {
        Label(title, systemImage: symbol).labelStyle(.iconOnly).font(.title3)
            .frame(width: 44, height: 44).contentShape(Rectangle())
    }
}
