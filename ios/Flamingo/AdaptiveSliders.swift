import FlamingoCore
import MediaPlayer
import SwiftUI
import UIKit

@MainActor private enum SliderMotion {
    static let restingHeight: CGFloat = 4
    static let activeScale: CGFloat = 2.5
    static func animator(_ changes: @escaping () -> Void) -> UIViewPropertyAnimator {
        if UIAccessibility.isReduceMotionEnabled {
            return UIViewPropertyAnimator(duration: 0.12, curve: .easeOut, animations: changes)
        }
        return UIViewPropertyAnimator(duration: 0.22, dampingRatio: 0.94, animations: changes)
    }
}

struct AdaptiveProgressSlider: UIViewRepresentable {
    var value: Double
    var total: Double
    var trackID: UUID?
    var enabled: Bool
    var preview: (Double) -> Void
    var commit: (Double) -> Void
    var cancelled: () -> Void

    func makeUIView(context: Context) -> AdaptiveScrubberControl { AdaptiveScrubberControl() }
    func updateUIView(_ control: AdaptiveScrubberControl, context: Context) {
        // Context invalidation resets UIKit tracking without publishing SwiftUI
        // state from updateUIView. The owning view clears its preview onChange.
        let changedTrack = control.trackID != trackID
        control.trackID = trackID
        control.preview = preview; control.commit = commit; control.cancelled = cancelled
        control.total = total.isFinite ? max(0, total) : 0
        let available = enabled && trackID != nil && control.total > 0
        if changedTrack || !available && control.phase != .idle { control.invalidateInteraction(notify: false) }
        if available && !control.isEnabled { PlayerHaptics.shared.prepareScrubbing() }
        control.isEnabled = available
        control.isAccessibilityElement = available
        control.accessibilityElementsHidden = !available
        if control.phase != .pressed && control.phase != .dragging { control.displayedValue = value }
        control.refreshAccessibility()
    }
    static func dismantleUIView(_ control: AdaptiveScrubberControl, coordinator: ()) {
        control.invalidateInteraction(notify: false)
    }
}

final class AdaptiveScrubberControl: UIControl {
    var trackID: UUID?
    var total: Double = 0
    var preview: ((Double) -> Void)?
    var commit: ((Double) -> Void)?
    var cancelled: (() -> Void)?
    private(set) var phase = SliderInteractionPhase.idle
    var displayedValue: Double = 0 { didSet { setNeedsLayout() } }
    private let track = UIView()
    private let fill = UIView()
    private var animator: UIViewPropertyAnimator?
    private var generation = UUID()
    private var boundary = ScrubberBoundaryFeedback()
    private weak var trackedTouch: UITouch?
    private var backgroundObserver: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isEnabled = false
        isMultipleTouchEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = [.adjustable]
        accessibilityLabel = "播放进度"
        accessibilityIdentifier = "playback-progress"
        track.backgroundColor = .white.withAlphaComponent(0.2)
        fill.backgroundColor = .white.withAlphaComponent(0.72)
        track.layer.cornerRadius = SliderMotion.restingHeight / 2
        track.clipsToBounds = true
        track.isUserInteractionEnabled = false
        track.addSubview(fill); addSubview(track)
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.invalidateInteraction(notify: true) }
        }
    }
    required init?(coder: NSCoder) { return nil }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 44) }
    override func layoutSubviews() {
        super.layoutSubviews()
        track.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: SliderMotion.restingHeight)
        track.center = CGPoint(x: bounds.midX, y: bounds.midY)
        let fraction = total > 0 && displayedValue.isFinite ? min(1, max(0, displayedValue / total)) : 0
        fill.frame = CGRect(x: 0, y: 0, width: track.bounds.width * fraction, height: track.bounds.height)
    }
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard trackedTouch == nil, startInteraction(at: fraction(for: touch)) else { return false }
        trackedTouch = touch
        return true
    }
    @discardableResult func startInteraction(at fraction: Double) -> Bool {
        guard isEnabled, total.isFinite, total > 0, fraction.isFinite, phase != .pressed, phase != .dragging else { return false }
        boundary = ScrubberBoundaryFeedback()
        phase = .pressed
        animateTrack(active: true)
        PlayerHaptics.shared.scrubberActivated()
        update(fraction: fraction)
        return true
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard trackedTouch === touch else { return false }
        return moveInteraction(to: fraction(for: touch))
    }
    @discardableResult func moveInteraction(to fraction: Double) -> Bool {
        guard phase == .pressed || phase == .dragging else { return false }
        phase = .dragging
        update(fraction: fraction)
        return true // Continue outside the hit area; values clamp to either end.
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        guard phase == .pressed || phase == .dragging else { return }
        guard let touch else { invalidateInteraction(notify: true); return }
        guard trackedTouch === touch else { return }
        trackedTouch = nil
        finishInteraction(at: fraction(for: touch))
    }
    func finishInteraction(at fraction: Double) {
        guard phase == .pressed || phase == .dragging else { return }
        guard isEnabled, fraction.isFinite else { invalidateInteraction(notify: true); return }
        update(fraction: fraction)
        let target = displayedValue
        phase = .settling
        animateTrack(active: false)
        commit?(target) // One seek per completed touch, never one per move.
    }
    override func cancelTracking(with event: UIEvent?) {
        invalidateInteraction(notify: true)
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { invalidateInteraction(notify: false) }
    }
    private func fraction(for touch: UITouch) -> Double {
        Double(touch.location(in: self).x / max(1, bounds.width))
    }
    private func update(fraction raw: Double) {
        guard raw.isFinite else { return }
        let fraction = min(1, max(0, raw))
        displayedValue = fraction * total
        preview?(displayedValue)
        refreshAccessibility()
        if boundary.update(fraction: fraction) != nil { PlayerHaptics.shared.boundaryReached() }
    }
    func invalidateInteraction(notify: Bool) {
        trackedTouch = nil
        let interrupted = phase == .pressed || phase == .dragging
        if interrupted, notify, window != nil, UIApplication.shared.applicationState == .active {
            phase = .cancelled
            animateTrack(active: false)
            cancelled?()
            return
        }
        generation = UUID()
        if animator?.state == .active { animator?.stopAnimation(true) }
        animator = nil
        track.transform = .identity
        phase = .idle
        boundary = ScrubberBoundaryFeedback()
        if interrupted, notify { cancelled?() }
    }
    private func animateTrack(active: Bool) {
        let token = UUID(); generation = token
        if animator?.state == .active {
            animator?.stopAnimation(false); animator?.finishAnimation(at: .current)
        }
        let next = SliderMotion.animator { [weak self] in
            self?.track.transform = active ? CGAffineTransform(scaleX: 1, y: SliderMotion.activeScale) : .identity
        }
        next.addCompletion { [weak self] _ in
            guard let self, self.generation == token else { return }
            self.animator = nil
            if !active { self.phase = .idle }
        }
        animator = next; next.startAnimation()
    }
    func refreshAccessibility() {
        accessibilityValue = "\(PlaybackTime.label(displayedValue))，总时长 \(PlaybackTime.label(total))"
        accessibilityTraits = isEnabled ? [.adjustable] : [.adjustable, .notEnabled]
    }
    override func accessibilityIncrement() { adjust(by: 10) }
    override func accessibilityDecrement() { adjust(by: -10) }
    private func adjust(by delta: Double) {
        guard isEnabled else { return }
        displayedValue = min(total, max(0, displayedValue + delta))
        refreshAccessibility()
        commit?(displayedValue)
        PlayerHaptics.shared.discreteSelection()
    }
    deinit { if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) } }
}

// Observes touches on the public container without inspecting MPVolumeView's
// subviews, cancelling their touches, or preventing its native recognizers.
private final class PassiveVolumeTouch: UIGestureRecognizer {
    var began: (() -> Void)?
    var moved: (() -> Void)?
    var finished: (() -> Void)?
    var interrupted: (() -> Void)?
    private weak var primaryTouch: UITouch?
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard primaryTouch == nil, let touch = touches.first else { return }
        primaryTouch = touch; state = .began; began?()
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let primaryTouch, touches.contains(primaryTouch) else { return }
        state = .changed; moved?()
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let primaryTouch, touches.contains(primaryTouch) else { return }
        state = .ended; finished?()
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled; interrupted?()
    }
    override func reset() { super.reset(); primaryTouch = nil }
}

struct AdaptiveSystemVolumeSlider: UIViewRepresentable {
    var enabled: Bool
    var trackID: UUID?
    func makeUIView(context: Context) -> AdaptiveVolumeContainer { AdaptiveVolumeContainer() }
    func updateUIView(_ view: AdaptiveVolumeContainer, context: Context) {
        view.isUserInteractionEnabled = enabled
        view.accessibilityElementsHidden = !enabled
        view.volume.isUserInteractionEnabled = enabled
        if view.trackID != trackID || !enabled && view.phase != .idle { view.cancelInteraction() }
        view.trackID = trackID
    }
    static func dismantleUIView(_ view: AdaptiveVolumeContainer, coordinator: ()) { view.cancelInteraction() }
}

final class AdaptiveVolumeContainer: UIView {
    let volume = MPVolumeView()
    var trackID: UUID?
    private(set) var phase = SliderInteractionPhase.idle
    private var animator: UIViewPropertyAnimator?
    private var generation = UUID()
    private var backgroundObserver: NSObjectProtocol?
    private let observer = PassiveVolumeTouch()
    override init(frame: CGRect) {
        super.init(frame: frame)
        volume.showsRouteButton = false
        volume.tintColor = .white.withAlphaComponent(0.75)
        volume.accessibilityLabel = "系统音量"
        accessibilityIdentifier = "system-volume"
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
        for state: UIControl.State in [.normal, .highlighted] {
            volume.setVolumeThumbImage(thumb, for: state)
            volume.setMinimumVolumeSliderImage(Self.trackImage(.white.withAlphaComponent(0.8)), for: state)
            volume.setMaximumVolumeSliderImage(Self.trackImage(.white.withAlphaComponent(0.22)), for: state)
        }
        addSubview(volume)
        observer.cancelsTouchesInView = false
        observer.delaysTouchesBegan = false; observer.delaysTouchesEnded = false
        observer.began = { [weak self] in self?.activate() }
        observer.moved = { [weak self] in self?.phase = .dragging }
        observer.finished = { [weak self] in self?.restore(cancelled: false) }
        observer.interrupted = { [weak self] in self?.restore(cancelled: true) }
        addGestureRecognizer(observer)
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelInteraction() }
        }
    }
    required init?(coder: NSCoder) { return nil }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 44) }
    override func layoutSubviews() {
        super.layoutSubviews()
        volume.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: 20)
        volume.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }
    private static func trackImage(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 12, height: SliderMotion.restingHeight)).image { _ in
            color.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 12, height: SliderMotion.restingHeight), cornerRadius: 2).fill()
        }.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: 3, bottom: 0, right: 3))
    }
    private func activate() {
        phase = .pressed
        animate(active: true)
    }
    private func restore(cancelled: Bool) {
        guard phase == .pressed || phase == .dragging else { return }
        phase = cancelled ? .cancelled : .settling
        animate(active: false)
    }
    private func animate(active: Bool) {
        let token = UUID(); generation = token
        if animator?.state == .active {
            animator?.stopAnimation(false); animator?.finishAnimation(at: .current)
        }
        let next = SliderMotion.animator { [weak self] in
            self?.volume.transform = active ? CGAffineTransform(scaleX: 1, y: SliderMotion.activeScale) : .identity
        }
        next.addCompletion { [weak self] _ in
            guard let self, self.generation == token else { return }
            self.animator = nil
            if !active { self.phase = .idle }
        }
        animator = next; next.startAnimation()
    }
    func cancelInteraction() {
        phase = .idle
        generation = UUID()
        if animator?.state == .active { animator?.stopAnimation(true) }
        animator = nil
        volume.isUserInteractionEnabled = false
        volume.isUserInteractionEnabled = isUserInteractionEnabled
        observer.isEnabled = false; observer.isEnabled = true
        volume.transform = .identity
        phase = .idle
    }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { cancelInteraction() } }
    deinit { if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) } }
}
