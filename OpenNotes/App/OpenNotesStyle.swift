import SwiftUI

enum OpenNotesStyle {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.39, green: 0.66, blue: 1, alpha: 1)
            : UIColor(red: 0.08, green: 0.34, blue: 0.78, alpha: 1)
    })

    static func notebookTabWidth(availableWidth: CGFloat, count: Int) -> CGFloat {
        guard count > 0, availableWidth > 0 else { return 0 }
        if count == 1 { return availableWidth / 2 }
        return max(180, (availableWidth - CGFloat(count - 1) * 4) / CGFloat(count))
    }
}
