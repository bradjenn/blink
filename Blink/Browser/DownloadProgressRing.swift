import SwiftUI

struct DownloadProgressRing: View {
    let progress: CGFloat?
    let indeterminateAmount: CGFloat
    let color: Color

    private let lineWidth: CGFloat = 2.2

    var body: some View {
        if let progress {
            Circle()
                .trim(from: 0, to: max(progress, 0.05))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: progress)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let angle = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.0) * 360

                Circle()
                    .trim(from: 0, to: indeterminateAmount)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(angle - 90))
            }
        }
    }
}
