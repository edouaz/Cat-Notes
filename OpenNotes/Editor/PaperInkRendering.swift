import UIKit

extension InkDrawing {
    // The document paper stays white even when the surrounding interface is dark.
    func paperImage(from rect: CGRect, scale: CGFloat) -> UIImage {
        var rendered: UIImage!
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            rendered = image(from: rect, scale: scale)
        }
        return rendered
    }
}
