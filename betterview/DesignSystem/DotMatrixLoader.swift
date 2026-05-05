import SwiftUI

/// Animated 5×3 dot grid wave — used as a "thinking" indicator.
struct DotMatrixLoader: View {
    var color: Color = .bvAccent
    var dotSize: CGFloat = 3
    var spacing: CGFloat = 5
    var cols: Int = 5
    var rows: Int = 3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let step = dotSize + spacing
            let totalW = CGFloat(cols) * step - spacing
            let totalH = CGFloat(rows) * step - spacing
            Canvas { context, _ in
                drawDots(into: context, time: timeline.date.timeIntervalSinceReferenceDate)
            }
            .frame(width: totalW, height: totalH)
        }
    }

    private func drawDots(into context: GraphicsContext, time: TimeInterval) {
        let step = dotSize + spacing
        for col in 0..<cols {
            for row in 0..<rows {
                let phase = sin(time * 5 - Double(col) * 0.55 + Double(row) * 0.25)
                let normalized = (phase + 1) / 2
                let opacity: Double = max(0.15, normalized)
                let cx = CGFloat(col) * step
                let cy = CGFloat(row) * step
                let rect = CGRect(x: cx, y: cy, width: dotSize, height: dotSize)
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(opacity)))
            }
        }
    }
}
