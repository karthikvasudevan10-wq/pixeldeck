import UIKit

/// The footer free exports carry when shared: "MADE WITH PIXEL DECK" and "Available on the App
/// Store" on a band below the art (never over it). Pro exports don't get it. Images narrower than
/// `minWidth` are centred on a wider canvas so the text stays readable.
enum Watermark {
    static let minWidth = 360

    static func apply(to image: CGImage) -> CGImage? {
        let w = max(image.width, minWidth)
        let footer = max(48, Int((Double(w) * 0.12).rounded()))
        let size = CGSize(width: w, height: image.height + footer)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.interpolationQuality = .none
            UIImage(cgImage: image).draw(in: CGRect(x: (w - image.width) / 2, y: 0, width: image.width, height: image.height))

            drawBand(CGRect(x: 0, y: CGFloat(image.height), width: CGFloat(w), height: CGFloat(footer)))
        }
        return rendered.cgImage
    }

    /// Just the band, for videos: `width × height`, text on ink.
    static func band(width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { _ in
            drawBand(CGRect(x: 0, y: 0, width: width, height: height))
        }.cgImage
    }

    /// The card a shared video ends on: a pixel heart, "PIXEL DECK" and "Available on the App Store".
    static func endCard(width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let pink = UIColor(red: 1, green: 0x5C / 255, blue: 0x8A / 255, alpha: 1)
        let cream = UIColor(red: 1, green: 0xF6 / 255, blue: 0xE0 / 255, alpha: 1)
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { _ in
            UIColor(red: 0x12 / 255, green: 0x0E / 255, blue: 0x1F / 255, alpha: 1).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: width, height: height))
            let w = CGFloat(width), h = CGFloat(height)
            let unit = (w * 0.028).rounded()                     // one "pixel" of the heart
            let heart = ["0110110", "1111111", "1111111", "0111110", "0011100", "0001000"]
            let hw = unit * 7, hh = unit * 6
            let titleFont = UIFont(name: AppFont.silkscreen, size: (w * 0.1).rounded()) ?? .boldSystemFont(ofSize: w * 0.1)
            let subFont = UIFont(name: "SpaceGrotesk-Medium", size: w * 0.042) ?? .systemFont(ofSize: w * 0.042, weight: .medium)
            let title = NSAttributedString(string: "PIXEL DECK", attributes: [.font: titleFont, .foregroundColor: cream])
            let sub = NSAttributedString(string: String(localized: "Available on the App Store", comment: "Watermark on free exports, under 'Made with Pixel Deck'"),
                                         attributes: [.font: subFont, .foregroundColor: cream.withAlphaComponent(0.8)])
            let ts = title.size(), ss = sub.size()
            let gap = unit * 2
            var y = (h - hh - gap - ts.height - gap / 2 - ss.height) / 2
            pink.setFill()
            for (row, line) in heart.enumerated() {
                for (col, ch) in line.enumerated() where ch == "1" {
                    UIRectFill(CGRect(x: (w - hw) / 2 + CGFloat(col) * unit, y: y + CGFloat(row) * unit, width: unit, height: unit))
                }
            }
            y += hh + gap
            title.draw(at: CGPoint(x: (w - ts.width) / 2, y: y))
            y += ts.height + gap / 2
            sub.draw(at: CGPoint(x: (w - ss.width) / 2, y: y))
        }.cgImage
    }

    /// Fills `band` with ink and centres the two lines of text in it.
    private static func drawBand(_ band: CGRect) {
        let w = Int(band.width), footer = Int(band.height)
        do {
            UIColor(red: 0x12 / 255, green: 0x0E / 255, blue: 0x1F / 255, alpha: 1).setFill()
            UIRectFill(band)

            let title = String(localized: "Made with Pixel Deck", comment: "Watermark on free exports").uppercased()
            let subtitle = String(localized: "Available on the App Store", comment: "Watermark on free exports, under 'Made with Pixel Deck'")
            var big = CGFloat(footer) * 0.30
            var small = CGFloat(footer) * 0.21
            func attributed(_ s: String, _ font: UIFont, _ color: UIColor) -> NSAttributedString {
                NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
            }
            func fonts() -> (UIFont, UIFont) {
                (UIFont(name: AppFont.silkscreen, size: big.rounded()) ?? .boldSystemFont(ofSize: big),
                 UIFont(name: "SpaceGrotesk-Medium", size: small) ?? .systemFont(ofSize: small, weight: .medium))
            }
            var (f1, f2) = fonts()
            var line1 = attributed(title, f1, UIColor(red: 1, green: 0x5C / 255, blue: 0x8A / 255, alpha: 1))
            // Keep the title inside the band's width.
            let maxText = CGFloat(w) * 0.9
            if line1.size().width > maxText {
                let k = maxText / line1.size().width
                big *= k; small *= k
                (f1, f2) = fonts()
                line1 = attributed(title, f1, UIColor(red: 1, green: 0x5C / 255, blue: 0x8A / 255, alpha: 1))
            }
            let line2 = attributed(subtitle, f2, UIColor(red: 1, green: 0xF6 / 255, blue: 0xE0 / 255, alpha: 0.8))
            let s1 = line1.size(), s2 = line2.size()
            let gap = CGFloat(footer) * 0.05
            let top = band.minY + (band.height - s1.height - s2.height - gap) / 2
            line1.draw(at: CGPoint(x: band.minX + (CGFloat(w) - s1.width) / 2, y: top))
            line2.draw(at: CGPoint(x: band.minX + (CGFloat(w) - s2.width) / 2, y: top + s1.height + gap))
        }
    }
}
