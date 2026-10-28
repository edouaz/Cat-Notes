import SwiftUI

struct WritingInstrumentBar: View {
    @ObservedObject var session: EditorSession
    @State private var optionsShown = false
    private let instruments: [EditorToolSettings.ToolbarItem] = [.pen, .marker, .eraser, .lasso]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                Button { session.canvas.undoManager?.undo() } label: {
                    InstrumentLabel(title: "Undo", symbol: "arrow.uturn.backward")
                }.keyboardShortcut("z", modifiers: .command).disabled(!session.canUndo)
                Button { session.canvas.undoManager?.redo() } label: {
                    InstrumentLabel(title: "Redo", symbol: "arrow.uturn.forward")
                }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!session.canRedo)
                Divider().frame(height: 24).padding(.horizontal, 4)
                ForEach(instruments) { item in
                    if let tool = item.drawingTool {
                        let selected = session.selectedTool == tool
                        Button {
                            if selected { optionsShown = true }
                            else { session.selectedTool = tool }
                        } label: {
                            InstrumentLabel(title: item.title, symbol: item.symbol)
                                .foregroundStyle(selected ? OpenNotesStyle.accent : Color.primary)
                                .background(selected ? OpenNotesStyle.accent.opacity(0.12) : .clear,
                                            in: RoundedRectangle(cornerRadius: 10))
                        }
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityHint(selected ? "Tap again for options" : "Select tool")
                        .accessibilityIdentifier("editor.tool.\(item.rawValue)")
                    }
                }
                Button { optionsShown = true } label: {
                    InstrumentLabel(title: "Tool options", symbol: "slider.horizontal.3")
                }.accessibilityIdentifier("editor.toolOptions")
            }.padding(.horizontal, 8).padding(.vertical, 4)
        }
        .frame(height: 52)
        .buttonStyle(.plain)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .bottom) { Divider() }
        .popover(isPresented: $optionsShown) {
            WritingToolOptions(session: session)
        }
        .onAppear {
            // Map legacy instruments to a visible tool without changing saved ink.
            if session.selectedTool == .pencil || session.selectedTool == .fountainPen {
                session.selectedTool = .pen
            }
        }
    }
}

private struct InstrumentLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .labelStyle(.iconOnly)
            .font(.title3)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

private struct WritingToolOptions: View {
    @ObservedObject var session: EditorSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if session.selectedTool.isWritingTool {
                    if #available(iOS 17.0, *) {
                        if session.selectedTool == .marker {
                            Section("Highlighter tip") {
                                Toggle("Use Pencil tilt", isOn: Binding(
                                    get: { session.toolSettings.markerTiltEnabled != false },
                                    set: { session.toolSettings.markerTiltEnabled = $0 }
                                )).accessibilityIdentifier("instrument.markerTilt")
                                Text(session.toolSettings.markerTiltEnabled == false
                                     ? "Round tip, constant width. Pressure and tilt do not change the stroke."
                                     : "Chisel tip that follows your Pencil’s tilt.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        } else {
                            Section("Pen preset") {
                                Picker("Style", selection: Binding(
                                    get: { session.toolSettings.penStyle },
                                    set: { session.toolSettings.applyPenPreset($0) }
                                )) {
                                    Text("Ballpoint").tag(EditorToolSettings.PenStyle.ballpoint)
                                    Text("Fountain").tag(EditorToolSettings.PenStyle.fountain)
                                    Text("Brush").tag(EditorToolSettings.PenStyle.brush)
                                }.accessibilityIdentifier("instrument.penStyle")
                                Toggle("Vary with pressure", isOn: Binding(
                                    get: { session.toolSettings.penPressureEnabled },
                                    set: { session.toolSettings.pressureEnabled = $0 }
                                )).accessibilityIdentifier("instrument.pressureEnabled")
                                Text(session.toolSettings.penPressureEnabled
                                     ? "Expressive native ink that follows your pressure."
                                     : "Uniform round tip. Turn pressure on to use the preset’s expressive tip.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Additional pen tips and the round highlighter require iPadOS 17 or later.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ColorPicker("Ink color", selection: Binding(
                        get: { session.inkColor }, set: { session.setInkColor($0) }
                    ), supportsOpacity: false)
                    VStack(alignment: .leading) {
                        Text("Width: \(session.documentInkWidth.formatted(.number.precision(.fractionLength(1)))) pt")
                        Slider(value: Binding(
                            get: { session.documentInkWidth },
                            set: { session.setDocumentInkWidth($0) }
                        ), in: session.documentInkWidthRange)
                        .accessibilityLabel("Stroke width")
                    }
                } else if session.selectedTool == .eraser {
                    Picker("Erase", selection: $session.toolSettings.eraserMode) {
                        Text("Whole stroke").tag(EditorToolSettings.EraserMode.stroke)
                        Text("Part of a stroke").tag(EditorToolSettings.EraserMode.pixel)
                        if session.toolSettings.eraserMode == .intelligent {
                            Text("Intelligent").tag(EditorToolSettings.EraserMode.intelligent)
                        }
                    }
                    Slider(value: $session.toolSettings.eraserWidth, in: 4...100)
                        .accessibilityLabel("Eraser size")
                } else {
                    Picker("Selection", selection: $session.toolSettings.lassoShape) {
                        Text("Freehand").tag(EditorToolSettings.LassoShape.freeform)
                        Text("Rectangle").tag(EditorToolSettings.LassoShape.rectangle)
                    }
                    Toggle("Include handwriting", isOn: $session.toolSettings.includeHandwriting)
                    Toggle("Include images", isOn: $session.toolSettings.includeImages)
                    Toggle("Include text", isOn: Binding(
                        get: { session.toolSettings.includeText != false },
                        set: { session.toolSettings.includeText = $0 }
                    ))
                    Toggle("Include sticky notes", isOn: $session.toolSettings.includeStickyNotes)
                }
            }
            .navigationTitle("Tool options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .frame(idealWidth: 340, idealHeight: 520)
        .presentationDetents([.medium, .large])
    }
}
