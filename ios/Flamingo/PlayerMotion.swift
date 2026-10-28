import Observation
import SwiftUI

enum PlayerMotion {
    static let presentation = Animation.spring(response: 0.46, dampingFraction: 0.9)
    static let returnToPlayer = Animation.spring(response: 0.38, dampingFraction: 0.92)
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

    func settle(expanded: Bool, reduceMotion: Bool) {
        if expanded && (phase == .expanded || phase == .expanding) { return }
        if !expanded && (phase == .collapsed || phase == .collapsing) { return }
        let token = UUID()
        generation = token
        let returning = phase == .dragging && expanded
        phase = expanded ? .expanding : .collapsing
        withAnimation(reduceMotion ? PlayerMotion.reduced : returning ? PlayerMotion.returnToPlayer : PlayerMotion.presentation,
                      completionCriteria: .removed) {
            progress = expanded ? 1 : 0
        } completion: { [weak self] in
            guard let self, self.generation == token else { return }
            self.renderedProgress = expanded ? 1 : 0
            self.phase = expanded ? .expanded : .collapsed
        }
    }

    func drag(translation: CGFloat, travel: CGFloat) {
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

    func endDrag(predictedTranslation: CGFloat, travel: CGFloat, reduceMotion: Bool) {
        guard phase == .dragging else { return }
        let projected = dragOrigin - predictedTranslation / max(1, travel)
        settle(expanded: projected > 0.55, reduceMotion: reduceMotion)
    }

    func reset() {
        generation = UUID()
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { progress = 0; renderedProgress = 0; phase = .collapsed }
    }
}

struct MiniPlayerFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { let next = nextValue(); if !next.isEmpty { value = next } }
}
struct MiniArtworkFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { let next = nextValue(); if !next.isEmpty { value = next } }
}
struct PlayerArtworkFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { let next = nextValue(); if !next.isEmpty { value = next } }
}

private func interpolatedRect(_ start: CGRect, _ end: CGRect, progress: CGFloat) -> CGRect {
    let p = min(1, max(0, progress))
    return CGRect(x: start.minX + (end.minX - start.minX) * p,
                  y: start.minY + (end.minY - start.minY) * p,
                  width: start.width + (end.width - start.width) * p,
                  height: start.height + (end.height - start.height) * p)
}

// The child keeps its full-screen layout. Only its rendered container transforms.
// Sampling animatableData lets a new drag start at the visible spring position.
struct PlayerContainerTransform: AnimatableModifier {
    var progress: CGFloat
    var motion: PlayerPresentation
    var collapsed: CGRect
    var expanded: CGRect
    var corner: CGFloat
    var reduceMotion: Bool
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue; motion.renderedProgress = newValue }
    }
    func body(content: Content) -> some View {
        let rect = reduceMotion ? expanded : interpolatedRect(collapsed, expanded, progress: progress)
        content
            .scaleEffect(x: rect.width / max(1, expanded.width), y: rect.height / max(1, expanded.height))
            .frame(width: rect.width, height: rect.height)
            .clipShape(RoundedRectangle(cornerRadius: reduceMotion ? 0 : corner * (1 - min(1, max(0, progress))), style: .continuous))
            .opacity(reduceMotion ? Double(progress) : progress > 0 ? 1 : 0)
            .position(x: rect.midX, y: rect.midY)
    }
}

struct PlayerControlsReveal: AnimatableModifier {
    var progress: CGFloat
    var animatableData: CGFloat { get { progress } set { progress = newValue } }
    func body(content: Content) -> some View {
        let p = min(1, max(0, (progress - 0.2) / 0.8))
        content.opacity(Double(p * p * (3 - 2 * p)))
    }
}

struct MiniArtworkVisibility: AnimatableModifier {
    var progress: CGFloat
    var reduceMotion: Bool
    var animatableData: CGFloat { get { progress } set { progress = newValue } }
    func body(content: Content) -> some View {
        content.opacity(!reduceMotion && progress > 0 ? 0 : 1)
    }
}

struct PlayerArtworkTransform: AnimatableModifier {
    var progress: CGFloat
    var collapsed: CGRect
    var expanded: CGRect
    var animatableData: CGFloat { get { progress } set { progress = newValue } }
    func body(content: Content) -> some View {
        let rect = interpolatedRect(collapsed, expanded, progress: progress)
        content.frame(width: rect.width, height: rect.height)
            .clipShape(RoundedRectangle(cornerRadius: 5 + 11 * progress, style: .continuous))
            .opacity(progress > 0 ? 1 : 0)
            .position(x: rect.midX, y: rect.midY)
    }
}
