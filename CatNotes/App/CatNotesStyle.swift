import SwiftUI

enum CatNotesStyle {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.49, green: 0.78, blue: 0.73, alpha: 1)
            : UIColor(red: 0.12, green: 0.4, blue: 0.37, alpha: 1)
    })

    static func notebookTabWidth(availableWidth: CGFloat, count: Int) -> CGFloat {
        guard count > 0, availableWidth > 0 else { return 0 }
        if count == 1 { return availableWidth / 2 }
        return max(180, (availableWidth - CGFloat(count - 1) * 4) / CGFloat(count))
    }
}
