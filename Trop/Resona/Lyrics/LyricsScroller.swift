//
//  LyricsScroller.swift
//  Resona
//
//  The ONE source of the lyrics list offset. A critically-tuned spring is
//  integrated on the display link and the published value is rounded to
//  whole device pixels, so (blurred) text never sits on sub-pixel
//  positions and nothing else — no SwiftUI implicit animation, no
//  withAnimation — moves the list. Manual drags set the value directly;
//  resuming / flinging animate from wherever the list currently is.
//

import Observation
import os
import QuartzCore
import SwiftUI

@MainActor
@Observable
final class LyricsScroller {
    enum Reason: String {
        case lineChange = "line change"
        case lineTops = "row positions"
        case height = "stage height"
        case resume = "resume"
        case fling = "fling"
        case initial = "initial"
    }

    /// Content offset (list moved up by `y` points), pixel-rounded.
    private(set) var y: CGFloat = 0
    /// Where the spring is heading (debug overlay).
    private(set) var target: CGFloat = 0
    /// Target changes in the last second (debug overlay).
    private(set) var retargetsPerSecond = 0

    @ObservationIgnored var displayScale: CGFloat = 3
    @ObservationIgnored private var position: CGFloat = 0
    @ObservationIgnored private var velocity: CGFloat = 0
    @ObservationIgnored private var stiffness: CGFloat = 158
    @ObservationIgnored private var damping: CGFloat = 19.6
    @ObservationIgnored private var driver: DisplayLinkDriver?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval?
    @ObservationIgnored private var retargetTimes: [CFTimeInterval] = []

    private static let log = Logger(subsystem: "dev.jackderganove.resona", category: "LyricsStage")

    /// Immediate placement (first position, "scroll animation off").
    func jump(to value: CGFloat, reason: Reason) {
        stop()
        record(value, reason)
        target = value
        position = value
        velocity = 0
        publish()
    }

    /// Direct drag: follows the finger 1:1, no spring.
    func drag(to value: CGFloat) {
        stop()
        target = value
        position = value
        velocity = 0
        publish()
    }

    /// Spring towards `value` (response/damping like SwiftUI's .spring).
    func animate(to value: CGFloat, reason: Reason, response: Double = 0.5, dampingFraction: Double = 0.78) {
        guard abs(value - target) > 0.5 || driver == nil && abs(value - position) > 0.5 else { return }
        record(value, reason)
        target = value
        let omega = 2 * Double.pi / response
        stiffness = CGFloat(omega * omega)
        damping = CGFloat(2 * dampingFraction * omega)
        start()
    }

    // MARK: Spring

    private func start() {
        guard driver == nil else { return }
        lastTimestamp = nil
        let link = DisplayLinkDriver(preferredFPS: 120) { [weak self] timestamp in
            self?.tick(timestamp)
        }
        link.start()
        driver = link
    }

    private func stop() {
        driver?.stop()
        driver = nil
        lastTimestamp = nil
    }

    private func tick(_ timestamp: CFTimeInterval) {
        let dt = min(1.0 / 30, max(0, timestamp - (lastTimestamp ?? timestamp - 1.0 / 120)))
        lastTimestamp = timestamp
        // Semi-implicit Euler in small sub-steps: stable at any frame rate.
        var remaining = dt
        while remaining > 0 {
            let h = min(remaining, 1.0 / 480)
            let force = -stiffness * (position - target) - damping * velocity
            velocity += force * CGFloat(h)
            position += velocity * CGFloat(h)
            remaining -= h
        }
        if abs(position - target) < 0.2, abs(velocity) < 2 {
            position = target
            velocity = 0
            publish()
            stop()
            return
        }
        publish()
    }

    /// Only whole device pixels reach the view (and only when they change).
    private func publish() {
        let scale = max(1, displayScale)
        let rounded = (position * scale).rounded() / scale
        if rounded != y { y = rounded }
    }

    private func record(_ value: CGFloat, _ reason: Reason) {
        let now = CACurrentMediaTime()
        retargetTimes.append(now)
        retargetTimes.removeAll { now - $0 > 1 }
        retargetsPerSecond = retargetTimes.count
        Self.log.debug("scrollY \(self.target, format: .fixed(precision: 1)) → \(value, format: .fixed(precision: 1)) [\(reason.rawValue)]")
    }
}

/// Applies the scroller's offset. Only this modifier re-evaluates per frame
/// while the list glides — the rows themselves are untouched.
struct LyricsScrollerOffset: ViewModifier {
    let scroller: LyricsScroller

    func body(content: Content) -> some View {
        content.offset(y: -scroller.y)
    }
}

/// Test switches (Songtext settings → Developer) to isolate visual effects.
@MainActor
@Observable
final class LyricsDebugOptions {
    static let shared = LyricsDebugOptions()

    var blurOff: Bool { didSet { save("blurOff", blurOff) } }
    var glowOff: Bool { didSet { save("glowOff", glowOff) } }
    var growthOff: Bool { didSet { save("growthOff", growthOff) } }
    var scrollAnimationOff: Bool { didSet { save("scrollAnimationOff", scrollAnimationOff) } }
    var overlay: Bool { didSet { save("overlay", overlay) } }

    private init() {
        let d = UserDefaults.standard
        blurOff = d.bool(forKey: "resona.lyricsDebug.blurOff")
        glowOff = d.bool(forKey: "resona.lyricsDebug.glowOff")
        growthOff = d.bool(forKey: "resona.lyricsDebug.growthOff")
        scrollAnimationOff = d.bool(forKey: "resona.lyricsDebug.scrollAnimationOff")
        overlay = d.bool(forKey: "resona.lyricsDebug.overlay")
    }

    private func save(_ key: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: "resona.lyricsDebug.\(key)")
    }
}
