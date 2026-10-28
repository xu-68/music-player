import CoreHaptics
import UIKit

enum SliderInteractionPhase: Equatable {
    case idle, pressed, dragging, settling, cancelled
}

enum ScrubberBoundary: Equatable { case start, end }

struct ScrubberBoundaryFeedback {
    private(set) var boundary: ScrubberBoundary?
    mutating func update(fraction: Double) -> ScrubberBoundary? {
        guard fraction.isFinite else { return nil }
        if fraction <= 0, boundary != .start { boundary = .start; return .start }
        if fraction >= 1, boundary != .end { boundary = .end; return .end }
        if fraction > 0.02, fraction < 0.98 { boundary = nil }
        return nil
    }
}

struct HapticThrottle {
    private var lastEmission: TimeInterval?
    mutating func allow(at time: TimeInterval) -> Bool {
        guard time.isFinite else { return false }
        if let lastEmission, time - lastEmission < 0.12 { return false }
        lastEmission = time
        return true
    }
}

// UI events only. Playback observers, remote commands and animation frames never
// call this manager. The OS remains responsible for honoring system haptic policy.
@MainActor final class PlayerHaptics {
    static let shared = PlayerHaptics()
    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var impact: UIImpactFeedbackGenerator?
    private var selection: UISelectionFeedbackGenerator?
    private var throttle = HapticThrottle()
    private var enabled: Bool {
        supported && UIApplication.shared.applicationState == .active &&
            AppPreferences.defaults.bool(forKey: "hapticFeedback")
    }
    private func prepareGenerators() {
        if impact == nil { impact = UIImpactFeedbackGenerator(style: .soft) }
        if selection == nil { selection = UISelectionFeedbackGenerator() }
    }
    func prepareScrubbing() {
        guard enabled else { return }
        prepareGenerators()
        impact?.prepare()
    }
    func scrubberActivated() {
        guard enabled, throttle.allow(at: ProcessInfo.processInfo.systemUptime) else { return }
        prepareGenerators()
        impact?.impactOccurred(intensity: 0.35)
        selection?.prepare() // Prepare once for a possible later boundary event.
    }
    func boundaryReached() {
        discreteSelection()
    }
    func discreteSelection() {
        guard enabled, throttle.allow(at: ProcessInfo.processInfo.systemUptime) else { return }
        prepareGenerators()
        selection?.selectionChanged()
        selection?.prepare()
    }
    func releaseResources() {
        impact = nil; selection = nil
        throttle = HapticThrottle()
    }
}
