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
            EditorInstrumentOptions(session: session) { optionsShown = false }
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
