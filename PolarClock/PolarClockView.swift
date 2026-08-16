import SwiftUI
import ScreenSaver
import AppKit

@objc(PolarClockView)
class PolarClockScreenSaverView: ScreenSaverView {
    private var hostingView: NSHostingView<PolarClockContentView>?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)

        let contentView = PolarClockContentView(isPreview: isPreview)
        hostingView = NSHostingView(rootView: contentView)
        hostingView?.frame = bounds
        hostingView?.autoresizingMask = [.width, .height]

        if let hostingView = hostingView {
            addSubview(hostingView)
        }

        animationTimeInterval = isPreview ? 1.0 / 30.0 : 1.0 / 60.0
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

    static let durationFormatter: MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.unitStyle = .long
        formatter.unitOptions = .providedUnit
        return formatter
    }()

    static func formatDuration(_ value: Int, unit: UnitDuration) -> String {
        let measurement = Measurement(value: Double(value), unit: unit)
        return durationFormatter.string(from: measurement)
    }

    static func calculateRings(for date: Date) -> [RingData] {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month, .day, .weekday, .hour, .minute, .second, .nanosecond], from: date)

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
            RingData(progress: hourProgress, label: formatDuration(hour, unit: .hours), color: ringColors[3]),
            RingData(progress: minuteProgress, label: formatDuration(minute, unit: .minutes), color: ringColors[4]),
            RingData(progress: secondProgress, label: formatDuration(second, unit: .seconds), color: ringColors[5])
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

// MARK: - Glyph Cache

/// Characters are pre-rasterized so labels can sit at arbitrary sub-pixel offsets.
/// Drawing `Text` directly snaps each glyph to a device pixel grid, which makes the
/// slow rings twitch a pixel at a time instead of drifting smoothly.
enum GlyphCache {
    /// Glyphs are rasterized larger than they are drawn, so rotating them stays crisp.
    private static let supersample: CGFloat = 3

    /// Rasterized glyphs cost about 2 MB per font size. The clock draws one size at a
    /// time, but a resizable window walks through many, so drop them all once a few
    /// have accumulated.
    private static let sizeLimit = 4

    private struct Key: Hashable {
        let character: Character
        let fontSize: CGFloat
    }

    private static var images: [Key: NSImage] = [:]
    private static var advances: [Key: CGFloat] = [:]
    private static var cachedSizes: Set<CGFloat> = []

    private static func font(size: CGFloat) -> NSFont {
        let systemFont = NSFont.systemFont(ofSize: size, weight: .medium)
        guard let descriptor = systemFont.fontDescriptor.withDesign(.rounded),
              let roundedFont = NSFont(descriptor: descriptor, size: size) else {
            return systemFont
        }
        return roundedFont
    }

    private static func attributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
        shadow.shadowBlurRadius = 2 * supersample
        shadow.shadowOffset = .zero

        return [
            .font: font(size: fontSize * supersample),
            .foregroundColor: NSColor.white,
            .shadow: shadow
        ]
    }

    private static func reserve(fontSize: CGFloat) {
        guard !cachedSizes.contains(fontSize) else { return }

        if cachedSizes.count >= sizeLimit {
            images.removeAll()
            advances.removeAll()
            cachedSizes.removeAll()
        }
        cachedSizes.insert(fontSize)
    }

    /// Measured at the rasterized size so that spacing matches the drawn glyphs.
    static func advance(for character: Character, fontSize: CGFloat) -> CGFloat {
        let key = Key(character: character, fontSize: fontSize)
        if let cached = advances[key] {
            return cached
        }
        reserve(fontSize: fontSize)

        let attributes: [NSAttributedString.Key: Any] = [.font: font(size: fontSize * supersample)]
        let advance = (String(character) as NSString).size(withAttributes: attributes).width / supersample
        advances[key] = advance
        return advance
    }

    static func image(for character: Character, fontSize: CGFloat) -> NSImage? {
        let key = Key(character: character, fontSize: fontSize)
        if let cached = images[key] {
            return cached
        }
        reserve(fontSize: fontSize)

        let glyph = NSAttributedString(string: String(character), attributes: attributes(fontSize: fontSize))
        let padding = 4 * supersample
        let glyphSize = glyph.size()
        let pixelSize = CGSize(width: ceil(glyphSize.width + padding * 2),
                               height: ceil(glyphSize.height + padding * 2))

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width),
            pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        glyph.draw(at: CGPoint(x: padding, y: padding))
        NSGraphicsContext.restoreGraphicsState()

        let logicalSize = CGSize(width: pixelSize.width / supersample,
                                 height: pixelSize.height / supersample)
        bitmap.size = logicalSize
        let image = NSImage(size: logicalSize)
        image.addRepresentation(bitmap)
        images[key] = image
        return image
    }

    /// Angle each character subtends when laid out along a circle of the given radius.
    static func characterArcs(for text: String, fontSize: CGFloat, radius: CGFloat) -> [CGFloat] {
        text.map { character in
            2 * asin(min(advance(for: character, fontSize: fontSize) / (2 * radius), 1))
        }
    }
}

// MARK: - Arced Text View

struct ArcedText: View {
    let text: String
    let center: CGPoint
    let radius: CGFloat
    let endAngle: Double
    let fontSize: CGFloat

    private var shouldFlip: Bool {
        let normalizedAngle = endAngle.truncatingRemainder(dividingBy: 360)
        let adjustedAngle = normalizedAngle < 0 ? normalizedAngle + 360 : normalizedAngle
        // Bottom half: 0° (3 o'clock) to 180° (9 o'clock)
        return adjustedAngle > 0 && adjustedAngle < 180
    }

    var body: some View {
        Canvas { context, _ in
            let arcs = GlyphCache.characterArcs(for: text, fontSize: fontSize, radius: radius)
            let endAngleRad = CGFloat(endAngle) * .pi / 180
            let flip = shouldFlip

            // Flipped text reads outward from the arc endpoint; otherwise it ends there
            var precedingArc: CGFloat = flip ? 0 : -arcs.reduce(0, +)

            for (index, character) in text.enumerated() {
                let angle = flip
                    ? endAngleRad - precedingArc - arcs[index] / 2
                    : endAngleRad + precedingArc + arcs[index] / 2
                precedingArc += arcs[index]

                guard let glyph = GlyphCache.image(for: character, fontSize: fontSize) else { continue }

                var characterContext = context
                characterContext.translateBy(
                    x: center.x + radius * cos(angle),
                    y: center.y + radius * sin(angle)
                )
                characterContext.rotate(by: .radians(angle + (flip ? -.pi / 2 : .pi / 2)))
                characterContext.draw(context.resolve(Image(nsImage: glyph)), at: .zero, anchor: .center)
            }
        }
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
        // The arc must be at least long enough to fit its label
        let labelArc = GlyphCache.characterArcs(for: label, fontSize: fontSize, radius: radius).reduce(0, +)
        return Double(labelArc) / (2 * .pi)
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
    let isPreview: Bool

    private var minDimension: CGFloat {
        min(size.width, size.height)
    }

    private var center: CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private var strokeWidth: CGFloat {
        let baseWidth = minDimension * 0.04
        return isPreview ? max(baseWidth, 2.0) : baseWidth
    }

    private var ringSpacing: CGFloat {
        strokeWidth * 1.4
    }

    private var innerRadius: CGFloat {
        let baseRadius = minDimension * 0.08
        return isPreview ? max(baseRadius, 8.0) : baseRadius
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

    let isPreview: Bool

    init(isPreview: Bool = false) {
        self.isPreview = isPreview
    }

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                ZStack {
                    (colorScheme == .dark ? Color.black : Color.white)
                        .ignoresSafeArea()

                    ClockFace(
                        date: timeline.date,
                        size: geometry.size,
                        animationState: animationState,
                        isPreview: isPreview
                    )
                }
            }
        }
    }
}