import Observation
import SwiftUI

enum PlayerMotion {
    static let presentation = Animation.timingCurve(0.22, 0.8, 0.25, 1, duration: 0.42)
    static let dismissal = Animation.timingCurve(0.3, 0, 0.65, 1, duration: 0.34)
    static let control = Animation.spring(response: 0.24, dampingFraction: 0.9)
    static let artwork = Animation.spring(response: 0.42, dampingFraction: 0.92)
    static let panel = Animation.easeOut(duration: 0.24)
    static let reduced = Animation.easeOut(duration: 0.15)
}

enum PlayerPresentationPhase: Equatable { case collapsed, expanding, expanded, dragging, collapsing }

// One coordinator for all tabs. No playback state or audio work lives here.
@Observable final class PlayerPresentation {
    private(set) var phase = PlayerPresentationPhase.collapsed
    private(set) var progress: CGFloat = 0
    @ObservationIgnored var renderedProgress: CGFloat = 0
    @ObservationIgnored private var dragOrigin: CGFloat = 1
    @ObservationIgnored private var generation = UUID()
    var isPresented: Bool { phase != .collapsed }

    func settle(expanded: Bool, reduceMotion: Bool, velocity: CGFloat = 0) {
        if expanded && (phase == .expanded || phase == .expanding) { return }
        if !expanded && (phase == .collapsed || phase == .collapsing) { return }
        let token = UUID()
        generation = token
        let interactive = phase == .dragging
        let returning = interactive && expanded
        let target: CGFloat = expanded ? 1 : 0
        let distance = target - renderedProgress
        let initialVelocity = abs(distance) > 0.001 ? max(-12, min(12, velocity / distance)) : 0
        let spring = Animation.interpolatingSpring(mass: 1, stiffness: returning ? 300 : 260,
                                                   damping: returning ? 34 : 32, initialVelocity: initialVelocity)
        phase = expanded ? .expanding : .collapsing
        withAnimation(reduceMotion ? PlayerMotion.reduced : interactive ? spring : expanded ? PlayerMotion.presentation : PlayerMotion.dismissal,
                      completionCriteria: .removed) {
            progress = expanded ? 1 : 0
        } completion: { [weak self] in
            guard let self, self.generation == token else { return }
            self.renderedProgress = expanded ? 1 : 0
            self.phase = expanded ? .expanded : .collapsed
        }
    }

    func drag(translation: CGFloat, travel: CGFloat) {
        guard translation.isFinite, travel.isFinite, travel > 0 else { return }
        if phase != .dragging {
            generation = UUID() // Invalidates any interrupted animation completion.
            dragOrigin = min(1, max(0, renderedProgress))
            phase = .dragging
        }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            progress = min(1, max(0, dragOrigin - translation / max(1, travel)))
            renderedProgress = progress
        }
    }

    func endDrag(predictedTranslation: CGFloat, travel: CGFloat, reduceMotion: Bool, velocity: CGFloat = 0) {
        guard phase == .dragging else { return }
        guard predictedTranslation.isFinite, travel.isFinite, travel > 0, velocity.isFinite else {
            settle(expanded: progress > 0.78, reduceMotion: reduceMotion)
            return
        }
        let projected = dragOrigin - predictedTranslation / max(1, travel)
        settle(expanded: projected > 0.78, reduceMotion: reduceMotion, velocity: -velocity / max(1, travel))
    }

    func reset() {
        generation = UUID()
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { progress = 0; renderedProgress = 0; phase = .collapsed }
    }
}

// Keep the page at its final size throughout the transition. Only translation,
// edge rounding and a short fade change; interrupted drags sample the visible position.
struct PlayerContainerTransform: AnimatableModifier {
    var progress: CGFloat
    var motion: PlayerPresentation
    var expanded: CGRect
    var reduceMotion: Bool
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue; motion.renderedProgress = newValue }
    }
    func body(content: Content) -> some View {
        let p = min(1, max(0, progress))
        content
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: reduceMotion ? 0 : 28 * (1 - p),
                                             topTrailingRadius: reduceMotion ? 0 : 28 * (1 - p)))
            .opacity(reduceMotion ? Double(p) : Double(min(1, p * 5)))
            .position(x: expanded.midX, y: expanded.midY + (reduceMotion ? 0 : expanded.height * (1 - p)))
    }
}
