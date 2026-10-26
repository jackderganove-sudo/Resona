//
//  DisplayLinkDriver.swift
//  Resona
//
//  CADisplayLink wrapper that calls back on every display frame (up to
//  120 Hz on ProMotion). Used to drive lyric line changes from the
//  high-resolution PlaybackClock instead of a slow timer.
//

import QuartzCore
import UIKit

@MainActor
final class DisplayLinkDriver {
    private var link: CADisplayLink?
    private let onFrame: (CFTimeInterval) -> Void
    private let preferredFPS: Float

    init(preferredFPS: Float = 120, onFrame: @escaping (CFTimeInterval) -> Void) {
        self.preferredFPS = preferredFPS
        self.onFrame = onFrame
    }

    func start() {
        guard link == nil else { return }
        let proxy = Proxy(owner: self)
        let link = CADisplayLink(target: proxy, selector: #selector(Proxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: preferredFPS, preferred: preferredFPS)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    fileprivate func tick(_ link: CADisplayLink) {
        onFrame(link.targetTimestamp)
    }

    /// Breaks the CADisplayLink → target retain cycle.
    private final class Proxy: NSObject {
        weak var owner: DisplayLinkDriver?
        init(owner: DisplayLinkDriver) { self.owner = owner }

        @objc func tick(_ link: CADisplayLink) {
            MainActor.assumeIsolated { owner?.tick(link) }
        }
    }
}
