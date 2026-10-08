import SwiftUI
import PokerCore

extension View {
    /// Places the view's top-center at `point` inside a top-leading ZStack.
    func anchoredTopCenter(_ point: CGPoint) -> some View {
        alignmentGuide(.leading) { d in d.width / 2 - point.x }
            .alignmentGuide(.top) { _ in -point.y }
    }

    /// Places the view's bottom-center at `point` inside a top-leading ZStack.
    func anchoredBottomCenter(_ point: CGPoint) -> some View {
        alignmentGuide(.leading) { d in d.width / 2 - point.x }
            .alignmentGuide(.top) { d in d.height - point.y }
    }
}

/// The felt, seats, board, pot and hero area.
struct ArenaView: View {
    let model: TableModel
    let width: CGFloat
    @Environment(\.dynamicTypeSize) private var typeSize

    private var state: TableRenderState { model.state }

    var body: some View {
        let m = TableMetrics(width: width, count: state.playerCount, done: state.phase == .done,
                             longNames: state.hasFullPlayerNames, largeText: typeSize.isAccessibilitySize)
        ZStack(alignment: .topLeading) {
            FeltView(metrics: m)
            CenterView(model: model, metrics: m)
                .anchoredTopCenter(CGPoint(x: m.width / 2, y: m.centerTop))
                .zIndex(2)
            ForEach(state.seats) { seat in
                SeatView(seat: seat, metrics: m, newHandKey: dealKey) { model.session.toggleReveal(seat.id) }
                    .anchoredTopCenter(m.seatPoint(seat.layoutX, seat.layoutY))
                    .zIndex(3)
            }
            HeroView(hero: state.hero, metrics: m, dealKey: dealKey)
                .anchoredBottomCenter(CGPoint(x: m.width / 2, y: m.heroBottom))
                .zIndex(4)
            ChipFlightLayer(model: model, metrics: m)
                .zIndex(5)
        }
        .frame(width: m.width, height: m.height, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.3), value: m.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Texas Hold'em table")
    }

    /// Changes on every new deal and replay, so card views are rebuilt and animate once.
    private var dealKey: String { "\(state.hand)-\(state.replayAttempt)" }
}

// MARK: Felt

private struct FeltView: View {
    let metrics: TableMetrics

    var body: some View {
        let inset = metrics.railInsets
        let railRect = CGRect(x: inset.side, y: inset.top, width: metrics.width - inset.side * 2,
                              height: metrics.height - inset.top - inset.bottom)
        ZStack {
            Ellipse()
                .fill(LinearGradient(stops: [.init(color: Noir.railStops[0], location: 0),
                                             .init(color: Noir.railStops[1], location: 0.45),
                                             .init(color: Noir.railStops[2], location: 1)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Ellipse().strokeBorder(Noir.railBorder, lineWidth: 1))
                .shadow(color: .black.opacity(0.44), radius: 12, y: 23)
            feltLayer
                .padding(metrics.railPadding)
        }
        .frame(width: railRect.width, height: railRect.height)
        .offset(x: railRect.minX, y: railRect.minY)
        .accessibilityHidden(true)
    }

    private var feltLayer: some View {
        ZStack(alignment: .top) {
            Ellipse().fill(EllipticalGradient(colors: [Noir.feltCenter, Noir.felt, Noir.feltEdge],
                                              center: UnitPoint(x: 0.5, y: 0.6), startRadiusFraction: 0,
                                              endRadiusFraction: 0.75))
            Canvas { context, size in
                var dots = Path()
                var y: CGFloat = 2
                while y < size.height {
                    var x: CGFloat = 2
                    while x < size.width {
                        dots.addEllipse(in: CGRect(x: x - 0.7, y: y - 0.7, width: 1.4, height: 1.4))
                        x += 4
                    }
                    y += 4
                }
                context.fill(dots, with: .color(Color(hex: "#b3ffdc08")))
            }
            .clipShape(Ellipse())
            Ellipse().strokeBorder(Noir.feltBorder, lineWidth: 2)
            Ellipse().strokeBorder(Noir.feltOutline, lineWidth: 1).padding(metrics.feltOutlineInset)
            VStack(spacing: metrics.compact ? 5 : 7) {
                Text("N O I R")
                    .font(.system(size: metrics.compact ? 14 : 18, weight: .bold))
                    .tracking(metrics.compact ? 5 : 8)
                Text("POKER CLUB")
                    .font(.system(size: metrics.compact ? 8 : 10))
                    .tracking(metrics.compact ? 2 : 3)
            }
            .foregroundStyle(Noir.watermark)
            .padding(.top, metrics.compact ? 28 : 30)
        }
    }
}

// MARK: Center

private struct CenterView: View {
    let model: TableModel
    let metrics: TableMetrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var state: TableRenderState { model.state }

    var body: some View {
        VStack(spacing: metrics.compact ? 6 : 8) {
            Button {
                model.session.openPotDetails()
            } label: {
                VStack(spacing: 2) {
                    Text(state.potButtonLabel)
                        .noirFont(metrics.compact ? 11 : 12, relativeTo: .caption)
                        .foregroundStyle(Noir.potTrigger)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Noir.mint.opacity(0.2)).frame(height: 1).offset(y: 2)
                        }
                    HStack(spacing: 8) {
                        ChipIcon(size: metrics.compact ? 24 : 28)
                        Text(state.potText)
                            .noirFont(metrics.compact ? 25 : 29, .semibold, relativeTo: .title2, digits: true, tracking: 1)
                            .foregroundStyle(Noir.text)
                            .contentTransition(.numericText())
                            .phaseAnimator([CGFloat(1), CGFloat(1.08)], trigger: potBumpKey) { view, scale in
                                view.scaleEffect(reduceMotion ? 1 : scale)
                            } animation: { _ in .easeOut(duration: 0.2) }
                    }
                }
                .padding(.horizontal, 10)
                .minimumHitTarget()
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("\(state.potButtonLabel), \(state.potText)")
            .accessibilityHint(state.potButtonA11y)
            .accessibilityIdentifier("pot-details")

            HStack(spacing: metrics.boardGap) {
                ForEach(state.board, id: \.index) { slot in
                    BoardSlotCell(slot: slot, size: metrics.boardCard)
                }
            }
            Text(state.boardCaption)
                .noirFont(metrics.compact ? 10 : 12, relativeTo: .caption, tracking: metrics.compact ? 0 : 1)
                .foregroundStyle(Noir.boardCaption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: metrics.width * 0.62, minHeight: 17)
        }
    }

    private var potBumpKey: Int { state.potPulse ? state.board.filter { $0.card != nil }.count : 0 }
}

private struct BoardSlotCell: View {
    let slot: BoardSlot
    let size: CGSize

    var body: some View {
        Group {
            if let face = slot.card {
                CardFaceView(card: face.card, width: size.width, height: size.height, best: face.best)
                    .dealIn(style: .flip, animate: face.animate, delayMs: face.delayMs)
                    .id(face.card.key)
            } else {
                BoardSlotView(glyph: slot.placeholderGlyph, width: size.width, height: size.height)
                    .accessibilityLabel(slot.a11y)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: Deal animation

enum DealStyle { case deal, flip }

private struct DealIn: ViewModifier {
    let style: DealStyle
    let animate: Bool
    let delayMs: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        let visible = shown || !animate || reduceMotion
        return content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : (style == .deal ? -36 : -10))
            .rotationEffect(.degrees(visible || style == .flip ? 0 : -12))
            .scaleEffect(visible || style == .flip ? 1 : 0.75)
            .rotation3DEffect(.degrees(visible || style == .deal ? 0 : 90), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .onAppear {
                guard animate, !reduceMotion, !shown else { return }
                let curve: Animation = style == .deal
                    ? .timingCurve(0.15, 0.65, 0.25, 1, duration: 0.6)
                    : .timingCurve(0.2, 0.6, 0.2, 1, duration: 0.65)
                withAnimation(curve.delay(Double(delayMs) / 1000)) { shown = true }
            }
    }
}

extension View {
    func dealIn(style: DealStyle, animate: Bool, delayMs: Int) -> some View {
        modifier(DealIn(style: style, animate: animate, delayMs: delayMs))
    }
}

// MARK: Chip flights

/// Three chips fly from the actor to the pot for each bet, call or raise.
private struct ChipFlightLayer: View {
    let model: TableModel
    let metrics: TableMetrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.chipFlights) { flight in
                ChipFlightView(from: origin(flight.seat), to: potCenter, skip: reduceMotion) {
                    model.finishFlight(flight.id)
                }
            }
        }
        .frame(width: metrics.width, height: metrics.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var potCenter: CGPoint { CGPoint(x: metrics.width / 2, y: metrics.centerTop + (metrics.compact ? 36 : 42)) }

    private func origin(_ seat: Int) -> CGPoint {
        if seat == 0 { return CGPoint(x: metrics.width / 2, y: metrics.heroBottom - 40) }
        guard let s = model.state.seats.first(where: { $0.id == seat }) else { return potCenter }
        let top = metrics.seatPoint(s.layoutX, s.layoutY)
        return CGPoint(x: top.x, y: top.y + metrics.cardBack.height + 30)
    }
}

private struct ChipFlightView: View {
    let from: CGPoint
    let to: CGPoint
    let skip: Bool
    let done: () -> Void
    @State private var arrived = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color(hex: "#276452"))
                    .overlay(Circle().strokeBorder(Color(hex: "#aef5d3"), style: StrokeStyle(lineWidth: 2, dash: [3, 2])))
                    .frame(width: 17, height: 17)
                    .shadow(color: .black.opacity(0.33), radius: 1, y: 2)
                    .scaleEffect(arrived ? 0.7 : 1)
                    .opacity(arrived ? 0 : 1)
                    .position(arrived ? to : CGPoint(x: from.x + CGFloat(i) * 3, y: from.y - CGFloat(i) * 3))
                    .animation(.timingCurve(0.2, 0.7, 0.3, 1, duration: 0.52).delay(Double(i) * 0.06), value: arrived)
            }
        }
        .onAppear {
            if skip { done(); return }
            DispatchQueue.main.async { arrived = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { done() }
        }
    }
}
