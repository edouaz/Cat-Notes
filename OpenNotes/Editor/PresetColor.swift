import UIKit

extension UIColor {
    convenience init?(presetHex: String) {
        let value = presetHex.hasPrefix("#") ? String(presetHex.dropFirst()) : presetHex
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        self.init(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
    var presetHex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let resolved = resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let converted = resolved.cgColor.converted(to: space, intent: .relativeColorimetric, options: nil)
        UIColor(cgColor: converted ?? resolved.cgColor).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int((min(1, max(0, r)) * 255).rounded()), Int((min(1, max(0, g)) * 255).rounded()), Int((min(1, max(0, b)) * 255).rounded()))
    }
}
