import SwiftUI
import ScreenSaver

@objc(PolarClockView)
class PolarClockScreenSaverView: ScreenSaverView {
    private var hostingView: NSHostingView<PolarClockContentView>?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)

        let contentView = PolarClockContentView()
        hostingView = NSHostingView(rootView: contentView)
        hostingView?.frame = bounds
        hostingView?.autoresizingMask = [.width, .height]

        if let hostingView = hostingView {
            addSubview(hostingView)
        }

        animationTimeInterval = 1.0 / 60.0
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func startAnimation() {
        super.startAnimation()
    }

    override func stopAnimation() {
        super.stopAnimation()
    }

    override func animateOneFrame() {
        // Animation handled by SwiftUI
    }

    override var hasConfigureSheet: Bool {
        return false
    }
}

// MARK: - Ring Data

struct RingData {
    let progress: Double
    let label: String
    let color: Color
}

// MARK: - Time Calculations

struct TimeCalculator {
    static let ringColors: [Color] = [.cyan, .green, .yellow, .orange, .red, .purple]

    static let monthNames = ["january", "february", "march", "april", "may", "june",
                             "july", "august", "september", "october", "november", "december"]
    static let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    static func ordinalSuffix(for day: Int) -> String {
        switch day {
        case 1, 21, 31: return "st"
        case 2, 22: return "nd"
        case 3, 23: return "rd"
        default: return "th"
        }
    }

    static func calculateRings(for date: Date) -> [RingData] {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute, .second, .nanosecond], from: date)

        let year = components.year ?? 2024
        let month = components.month ?? 1
        let day = components.day ?? 1
        let weekday = components.weekday ?? 1
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = components.second ?? 0
        let nanosecond = components.nanosecond ?? 0

        let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 30

        let nanosecondFraction = Double(nanosecond) / 1_000_000_000.0
        let secondProgress = (Double(second) + nanosecondFraction) / 60.0
        let minuteProgress = (Double(minute) + secondProgress) / 60.0
        let hourProgress = (Double(hour) + minuteProgress) / 24.0
        let dayProgress = (Double(day - 1) + hourProgress) / Double(daysInMonth)
        let monthProgress = (Double(month - 1) + dayProgress) / 12.0
        let weekdayProgress = (Double(weekday - 1) + hourProgress) / 7.0

        return [
            RingData(progress: monthProgress, label: monthNames[month - 1], color: ringColors[0]),
            RingData(progress: dayProgress, label: "\(day)\(ordinalSuffix(for: day))", color: ringColors[1]),
            RingData(progress: weekdayProgress, label: weekdayNames[weekday - 1], color: ringColors[2]),
            RingData(progress: hourProgress, label: "\(hour) hours", color: ringColors[3]),
            RingData(progress: minuteProgress, label: "\(minute) minutes", color: ringColors[4]),
            RingData(progress: secondProgress, label: "\(second) seconds", color: ringColors[5])
        ]
    }
}

// MARK: - Clock Animation State

class ClockAnimationState: ObservableObject {
    struct RingState {
        var previousProgress: Double = 0
        var isSnappingBack: Bool = false
        var snapBackStartTime: Date?
        var snapBackStartProgress: Double = 0  // The real progress when snap-back started
    }

    private var ringStates: [RingState] = Array(repeating: RingState(), count: 6)

    private let snapBackDuration: Double = 0.5  // seconds

    func getDisplayProgress(ringIndex: Int, realProgress: Double, currentTime: Date) -> Double {
        guard ringIndex >= 0 && ringIndex < ringStates.count else { return realProgress }

        var state = ringStates[ringIndex]
        var displayProgress = realProgress

        // Detect wrap-around: progress dropped significantly (e.g., 0.98 -> 0.02)
        if realProgress < 0.1 && state.previousProgress > 0.9 && !state.isSnappingBack {
            // Start snap-back animation
            state.isSnappingBack = true
            state.snapBackStartTime = currentTime
            state.snapBackStartProgress = realProgress
        }

        if state.isSnappingBack, let startTime = state.snapBackStartTime {
            let elapsed = currentTime.timeIntervalSince(startTime)
            let t = min(elapsed / snapBackDuration, 1.0)

            if t >= 1.0 {
                // Animation complete, resume normal progress
                state.isSnappingBack = false
                state.snapBackStartTime = nil
                displayProgress = realProgress
            } else {
                // Ease-out: starts fast, slows at end
                let easeOut = 1 - pow(1 - t, 2)

                // Animate from 1.0 down toward the current real progress
                // As t goes 0->1, displayProgress goes 1.0 -> realProgress
                let targetProgress = realProgress
                displayProgress = 1.0 - easeOut * (1.0 - targetProgress)
            }
        }

        // Update state
        state.previousProgress = realProgress
        ringStates[ringIndex] = state

        return displayProgress
    }
}

// MARK: - Arced Text View

struct ArcedText: View {
    let text: String
    let center: CGPoint
    let radius: CGFloat
    let endAngle: Double
    let fontSize: CGFloat

    private var characters: [String] {
        text.map { String($0) }
    }

    private var font: Font {
        .system(size: fontSize, weight: .medium, design: .rounded)
    }

    // Proper chord to arc conversion from Stack Overflow
    private func chordToArc(_ chord: CGFloat) -> CGFloat {
        return 2 * asin(chord / (2 * radius))
    }

    // Calculate arc for each character
    private var characterArcs: [CGFloat] {
        characters.map { char in
            // Approximate character width
            let charWidth = fontSize * 0.6
            return chordToArc(charWidth)
        }
    }

    private var totalArc: CGFloat {
        characterArcs.reduce(0, +)
    }

    private var shouldFlip: Bool {
        let normalizedAngle = endAngle.truncatingRemainder(dividingBy: 360)
        let adjustedAngle = normalizedAngle < 0 ? normalizedAngle + 360 : normalizedAngle
        // Bottom half: 0° (3 o'clock) to 180° (9 o'clock)
        return adjustedAngle > 0 && adjustedAngle < 180
    }

    private func sumOfArcs(upTo index: Int, arcs: [CGFloat]) -> CGFloat {
        guard index > 0 else { return 0 }
        return arcs[0..<index].reduce(0, +)
    }

    var body: some View {
        let arcs = characterArcs // Compute once

        return ZStack {
            ForEach(0..<characters.count, id: \.self) { index in
                characterView(at: index, arcs: arcs)
            }
        }
    }

    private func characterView(at index: Int, arcs: [CGFloat]) -> some View {
        let char = characters[index]
        let currentArc = arcs[index]

        // Calculate angle for this character
        let endAngleRad = endAngle * .pi / 180

        // Sum of arcs before this character
        let previousArcs = sumOfArcs(upTo: index, arcs: arcs)

        let charAngleRad: CGFloat
        if shouldFlip {
            // When flipped, position characters going backwards from endAngle
            charAngleRad = endAngleRad - previousArcs - currentArc / 2
        } else {
            // Normal: position characters forwards, ending at endAngle
            let startAngleRad = endAngleRad - totalArc
            charAngleRad = startAngleRad + previousArcs + currentArc / 2
        }

        let x = center.x + radius * cos(charAngleRad)
        let y = center.y + radius * sin(charAngleRad)

        // Rotation: perpendicular to radius, flip if on bottom
        let rotation = charAngleRad * 180 / .pi + (shouldFlip ? -90 : 90)

        return Text(char)
            .font(font)
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 0)
            .rotationEffect(.degrees(rotation))
            .position(x: x, y: y)
    }
}

// MARK: - Arc Ring View

struct ArcRing: View {
    let center: CGPoint
    let radius: CGFloat
    let strokeWidth: CGFloat
    let progress: Double
    let color: Color
    let label: String

    private var fontSize: CGFloat {
        strokeWidth * 0.5
    }

    private var minimumProgress: Double {
        // Calculate minimum arc length needed to fit the text
        let charWidth = fontSize * 0.6
        let estimatedTextWidth = Double(label.count) * charWidth
        let circumference = 2 * .pi * radius
        let minimumDegrees = (estimatedTextWidth / circumference) * 360
        return minimumDegrees / 360
    }

    private var displayProgress: Double {
        // Use at least the minimum progress needed to show the label
        max(progress, minimumProgress)
    }

    private var endAngle: Double {
        -90 + displayProgress * 360
    }

    var body: some View {
        ZStack {
            Path { path in
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(endAngle),
                    clockwise: false
                )
            }
            .stroke(color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))

            if displayProgress > 0.01 {
                ArcedText(
                    text: label,
                    center: center,
                    radius: radius,
                    endAngle: endAngle,
                    fontSize: fontSize
                )
            }
        }
    }
}

// MARK: - Clock Face View

struct ClockFace: View {
    let date: Date
    let size: CGSize
    let animationState: ClockAnimationState

    private var minDimension: CGFloat {
        min(size.width, size.height)
    }

    private var center: CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private var strokeWidth: CGFloat {
        minDimension * 0.04
    }

    private var ringSpacing: CGFloat {
        strokeWidth * 1.8
    }

    private var innerRadius: CGFloat {
        minDimension * 0.12
    }

    var body: some View {
        let rings = TimeCalculator.calculateRings(for: date)

        ZStack {
            ForEach(0..<rings.count, id: \.self) { index in
                let ring = rings[index]
                let radius = innerRadius + CGFloat(index) * ringSpacing
                let displayProgress = animationState.getDisplayProgress(
                    ringIndex: index,
                    realProgress: ring.progress,
                    currentTime: date
                )

                ArcRing(
                    center: center,
                    radius: radius,
                    strokeWidth: strokeWidth,
                    progress: displayProgress,
                    color: ring.color,
                    label: ring.label
                )
            }
        }
    }
}

// MARK: - Main Content View

struct PolarClockContentView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var animationState = ClockAnimationState()

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                ZStack {
                    (colorScheme == .dark ? Color.black : Color.white)
                        .ignoresSafeArea()

                    ClockFace(
                        date: timeline.date,
                        size: geometry.size,
                        animationState: animationState
                    )
                }
            }
        }
    }
}