import SwiftUI

enum OpenNotesStyle {
    // Calibration defaults; these are OpenNotes tokens, not measured Goodnotes values.
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.43, green: 0.69, blue: 1, alpha: 1)
            : UIColor(red: 0.12, green: 0.36, blue: 0.76, alpha: 1)
    })
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let chrome = Color(uiColor: .secondarySystemGroupedBackground)
    static let rail = Color(uiColor: .secondarySystemBackground)
    static let controlSize: CGFloat = 44
    static let cornerRadius: CGFloat = 14

    static func notebookTabWidth(availableWidth: CGFloat, count: Int) -> CGFloat {
        guard count > 0, availableWidth > 0 else { return 0 }
        return min(240, availableWidth)
    }
}
