import AppKit

final class SparklineView: NSView {
    var values: [Double] = [] { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 30) }

    override func draw(_ dirty: NSRect) {
        let pad: CGFloat = 2
        let r = bounds.insetBy(dx: pad, dy: pad)
        guard values.count >= 2 else {
            // flat hint line
            Theme.stroke.setStroke()
            let p = NSBezierPath()
            p.move(to: NSPoint(x: r.minX, y: r.midY))
            p.line(to: NSPoint(x: r.maxX, y: r.midY))
            p.lineWidth = 1; p.stroke()
            return
        }
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let span = max(1, hi - lo)
        func pt(_ i: Int) -> NSPoint {
            let x = r.minX + r.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = r.minY + r.height * CGFloat((values[i] - lo) / span)
            return NSPoint(x: x, y: y)
        }
        // faint area — metallic falloff
        let area = NSBezierPath()
        area.move(to: NSPoint(x: r.minX, y: r.minY))
        for i in 0..<values.count { area.line(to: pt(i)) }
        area.line(to: NSPoint(x: r.maxX, y: r.minY)); area.close()
        let areaGrad = NSGradient(colors: [Theme.chrome.withAlphaComponent(0.22),
                                           Theme.chrome.withAlphaComponent(0.0)])!
        areaGrad.draw(in: area, angle: -90)
        // line
        let line = NSBezierPath(); line.lineWidth = 1.5
        line.lineJoinStyle = .round; line.lineCapStyle = .round
        line.move(to: pt(0)); for i in 1..<values.count { line.line(to: pt(i)) }
        Theme.chromeHi.setStroke(); line.stroke()
        // end dot
        let e = pt(values.count - 1)
        let dot = NSBezierPath(ovalIn: NSRect(x: e.x - 2.2, y: e.y - 2.2, width: 4.4, height: 4.4))
        Theme.text.setFill(); dot.fill()
    }
}

final class BarView: NSView {
    var progress: Double = 0 { didSet { needsDisplay = true } }   // 0...1

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 5) }

    override func draw(_ dirty: NSRect) {
        let h = bounds.height, radius = h / 2
        let track = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        Theme.track.setFill(); track.fill()
        let p = max(0, min(1, progress))
        guard p > 0 else { return }
        let w = max(h, bounds.width * CGFloat(p))
        let fill = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: h),
                                xRadius: radius, yRadius: radius)
        Theme.sheen.draw(in: fill, angle: -90)
    }
}

// 24-bar histogram (hourly typing rhythm)
final class BarsView: NSView {
    var values: [Int] = [] { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 46) }
    override func draw(_ dirty: NSRect) {
        guard !values.isEmpty else { return }
        let n = values.count
        let gap: CGFloat = 2
        let bw = max(1, (bounds.width - CGFloat(n - 1) * gap) / CGFloat(n))
        let hi = CGFloat(max(1, values.max() ?? 1))
        for i in 0..<n {
            let v = CGFloat(values[i])
            let x = bounds.minX + CGFloat(i) * (bw + gap)
            let h = v <= 0 ? 1.5 : max(2, (bounds.height - 1) * (v / hi))
            let rect = NSRect(x: x, y: bounds.minY, width: bw, height: h)
            let rad = min(2, bw / 2)
            let p = NSBezierPath(roundedRect: rect, xRadius: rad, yRadius: rad)
            if v <= 0 { Theme.track.setFill(); p.fill() }
            else { Theme.sheen.draw(in: p, angle: -90) }
        }
    }
}

// GitHub-style activity grid: 7 rows (weekdays) × N week columns, chrome intensity = volume
final class HeatmapView: NSView {
    var days: [Double] = [] { didSet { needsDisplay = true } }   // oldest → newest
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 92) }
    override func draw(_ dirty: NSRect) {
        guard !days.isEmpty else { return }
        let rows = 7
        let cols = Int(ceil(Double(days.count) / 7.0))
        let gap: CGFloat = 3
        let cell = min((bounds.width - CGFloat(cols - 1) * gap) / CGFloat(cols),
                       (bounds.height - CGFloat(rows - 1) * gap) / CGFloat(rows))
        let gridW = CGFloat(cols) * cell + CGFloat(cols - 1) * gap
        let gridH = CGFloat(rows) * cell + CGFloat(rows - 1) * gap
        let x0 = bounds.minX + (bounds.width - gridW) / 2
        let yTop = bounds.minY + (bounds.height - gridH) / 2 + gridH - cell
        let hi = max(1.0, days.max() ?? 1)
        for idx in 0..<days.count {
            let col = idx / 7, row = idx % 7
            let x = x0 + CGFloat(col) * (cell + gap)
            let y = yTop - CGFloat(row) * (cell + gap)
            let v = days[idx]
            let rect = NSRect(x: x, y: y, width: cell, height: cell)
            let p = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            if v <= 0 { Theme.track.setFill() }
            else { Theme.chrome.withAlphaComponent(0.28 + 0.72 * min(1.0, v / hi)).setFill() }
            p.fill()
        }
    }
}
