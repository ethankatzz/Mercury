import AppKit

// Minimal monochrome / chrome palette.
enum Theme {
    static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
        NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
    }
    static let bg      = rgb(15, 16, 19)     // panel backdrop
    static let card    = rgb(23, 25, 29)     // inner surfaces
    static let stroke  = rgb(44, 47, 54)     // hairlines / borders
    static let text    = rgb(233, 234, 237)  // primary
    static let muted   = rgb(124, 128, 137)  // secondary
    static let faint   = rgb(78, 82, 90)      // untyped / tertiary
    static let chrome  = rgb(208, 213, 221)   // silver accent
    static let chromeDim = rgb(150, 156, 167)
    static let good    = rgb(228, 230, 234)   // correct char
    static let bad     = rgb(206, 92, 96)     // incorrect char
    static let track   = rgb(34, 37, 44)      // progress track
    static let chromeHi = rgb(236, 239, 244)  // metallic highlight
    static let chromeLo = rgb(126, 132, 143)  // metallic shade
    static let sheen   = NSGradient(starting: chromeHi, ending: chromeLo)!
}

// Wide-tracked, uppercase micro-type — the spec-sheet / luxury-label detail.
enum TypeStyle {
    static func micro(_ s: String, _ color: NSColor = Theme.muted,
                      size: CGFloat = 8.5, kern: CGFloat = 1.5,
                      align: NSTextAlignment = .left) -> NSAttributedString {
        let para = NSMutableParagraphStyle(); para.alignment = align
        return NSAttributedString(string: s.uppercased(), attributes: [
            .font: F.sans(size, .semibold), .foregroundColor: color,
            .kern: kern, .paragraphStyle: para])
    }
}

enum F {
    static func mono(_ size: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: w)
    }
    static func sans(_ size: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: w)
    }
}

enum Fmt {
    static let nf: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f
    }()
    static func int(_ n: Int) -> String { nf.string(from: NSNumber(value: n)) ?? "\(n)" }
    static func wpm(_ v: Double) -> String { String(Int((v.isFinite ? max(0, v) : 0).rounded())) }
    static func pct(_ v: Double) -> String { "\(Int((v.isFinite ? v : 0).rounded()))%" }
    static func dur(_ s: Double) -> String {
        let t = max(0, Int(s.rounded())); let h = t/3600, m = (t%3600)/60, sec = t%60
        return h > 0 ? String(format: "%dh %dm", h, m) : String(format: "%d:%02d", m, sec)
    }
    static func compact(_ n: Int) -> String {
        let a = Double(abs(n))
        if a >= 1_000_000 { return trim(Double(n)/1_000_000) + "M" }
        if a >= 1_000 { return trim(Double(n)/1_000) + "k" }
        return "\(n)"
    }
    private static func trim(_ v: Double) -> String {
        let s = String(format: "%.1f", v)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
}

enum Asset {
    static func image(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}
