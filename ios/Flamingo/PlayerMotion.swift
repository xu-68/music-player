import Observation
import SwiftUI

enum PlayerMotion {
    static let presentation = Animation.spring(response: 0.46, dampingFraction: 0.9)
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
        withAnimation(reduceMotion ? PlayerMotion.reduced : interactive ? spring : PlayerMotion.presentation,
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
            settle(expanded: progress > 0.55, reduceMotion: reduceMotion)
            return
        }
        let projected = dragOrigin - predictedTranslation / max(1, travel)
        settle(expanded: projected > 0.55, reduceMotion: reduceMotion, velocity: -velocity / max(1, travel))
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
            .clipShape(RoundedRectangle(cornerRadius: reduceMotion ? 0 : collapsed.height / 2 * (1 - min(1, max(0, progress))), style: .continuous))
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
            .clipShape(RoundedRectangle(cornerRadius: 7 + 9 * min(1, max(0, progress)), style: .continuous))
            .opacity(progress > 0 ? 1 : 0)
            .position(x: rect.midX, y: rect.midY)
    }
}

// Both endpoints report their layout before the moving layer is transformed.
struct PlayerMetadataFrames: Equatable {
    var title: CGRect = .zero
    var artist: CGRect = .zero
    var isComplete: Bool { !title.isEmpty && !artist.isEmpty }
    mutating func merge(_ next: Self) {
        if !next.title.isEmpty { title = next.title }
        if !next.artist.isEmpty { artist = next.artist }
    }
}
struct MiniMetadataFrameKey: PreferenceKey {
    static var defaultValue = PlayerMetadataFrames()
    static func reduce(value: inout PlayerMetadataFrames, nextValue: () -> PlayerMetadataFrames) { value.merge(nextValue()) }
}
struct ExpandedMetadataFrameKey: PreferenceKey {
    static var defaultValue = PlayerMetadataFrames()
    static func reduce(value: inout PlayerMetadataFrames, nextValue: () -> PlayerMetadataFrames) { value.merge(nextValue()) }
}
struct PlayerMetadataMeasurement: View {
    var mini: Bool
    var title: Bool
    var body: some View {
        GeometryReader { proxy in
            let rect = proxy.frame(in: .named(mini ? "player-root" : "player-content"))
            let frames = PlayerMetadataFrames(title: title ? rect : .zero, artist: title ? .zero : rect)
            if mini { Color.clear.preference(key: MiniMetadataFrameKey.self, value: frames) }
            else { Color.clear.preference(key: ExpandedMetadataFrameKey.self, value: frames) }
        }.allowsHitTesting(false)
    }
}
struct PlayerTextTransform: AnimatableModifier {
    var progress: CGFloat
    var collapsed: CGRect
    var expanded: CGRect
    var artist = false
    var dark = true
    var animatableData: CGFloat { get { progress } set { progress = newValue } }
    func body(content: Content) -> some View {
        let p = min(1, max(0, progress))
        let rect = interpolatedRect(collapsed, expanded, progress: p)
        let source = dark ? (artist ? 0.65 : 1.0) : (artist ? 0.4 : 0.0)
        let target = artist ? 0.6 : 1.0
        let luminance = source + (target - source) * Double(p)
        content.font(.system(size: max(1, rect.height * 0.83), weight: artist ? .regular : .semibold))
            .foregroundStyle(Color(white: luminance))
            .lineLimit(1).frame(width: rect.width, height: rect.height, alignment: .leading)
            .opacity(p > 0 ? 1 : 0)
            .position(x: rect.midX, y: rect.midY)
    }
}
