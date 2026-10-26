// Derived from Signotes, copyright (c) 2026 Diego Signorastri. MIT; see docs/Signotes-LICENSE.
import UIKit

final class PaperTemplateUIView: UIView {
    var template: PageTemplate = .blank {
        didSet {
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        isOpaque = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .white
        isOpaque = true
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        UIColor.white.setFill()
        context.fill(rect)

        Self.draw(template, in: context, rect: rect)
    }

    static func draw(_ template: PageTemplate, in context: CGContext, rect: CGRect) {
        switch template {
        case .blank:
            break
        case .ruled:
            drawRuled(in: context, rect: rect)
        case .grid:
            drawGrid(in: context, rect: rect)
        case .dotted:
            drawDotted(in: context, rect: rect)
        }
    }

    private static func drawRuled(in context: CGContext, rect: CGRect) {
        context.setStrokeColor(CGColor(srgbRed: 0.12, green: 0.4, blue: 0.65, alpha: 0.28))
        context.setLineWidth(1 / max(1, abs(context.ctm.a), abs(context.ctm.d)))

        let spacing: CGFloat = 32
        var y = spacing
        while y < rect.height {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: rect.width, y: y))
            y += spacing
        }

        context.strokePath()
    }

    private static func drawGrid(in context: CGContext, rect: CGRect) {
        context.setStrokeColor(CGColor(srgbRed: 0.12, green: 0.4, blue: 0.65, alpha: 0.24))
        context.setLineWidth(1 / max(1, abs(context.ctm.a), abs(context.ctm.d)))

        let spacing: CGFloat = 24
        var position = spacing
        while position < rect.width {
            context.move(to: CGPoint(x: position, y: 0))
            context.addLine(to: CGPoint(x: position, y: rect.height))
            position += spacing
        }

        position = spacing
        while position < rect.height {
            context.move(to: CGPoint(x: 0, y: position))
            context.addLine(to: CGPoint(x: rect.width, y: position))
            position += spacing
        }

        context.strokePath()
    }

    private static func drawDotted(in context: CGContext, rect: CGRect) {
        context.setFillColor(CGColor(srgbRed: 0.12, green: 0.4, blue: 0.65, alpha: 0.28))

        let spacing: CGFloat = 24
        let radius: CGFloat = 1.2
        var x = spacing

        while x < rect.width {
            var y = spacing

            while y < rect.height {
                context.fillEllipse(
                    in: CGRect(
                        x: x - radius,
                        y: y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
                y += spacing
            }

            x += spacing
        }
    }
}
