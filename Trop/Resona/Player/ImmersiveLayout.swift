//
//  ImmersiveLayout.swift
//  Resona
//
//  Geometry of the Immersive player style (round 11 fix): header in its own
//  strip at the top, then one vertically centred block — the disc as large as
//  the space allows, title and controls below it. The controls keep their
//  space while hidden (they only fade), so the disc never moves, and the
//  block always fits the visible area: on short windows the toggle row goes
//  first, then the header, then the disc.
//

import CoreGraphics

struct ImmersiveLayoutMetrics: Equatable {
    static let headerHeight: CGFloat = 52
    static let margin: CGFloat = 16
    static let side: CGFloat = 24
    static let gap: CGFloat = 28
    /// Toggle row (shuffle, repeat, …): 56 pt row + 12 pt spacing.
    static let togglesHeight: CGFloat = 68
    static let maxControlsWidth: CGFloat = 560
    /// Below this the toggle row makes room for the disc.
    static let comfortableDisc: CGFloat = 160
    /// Below this the disc is left out rather than shown as a dot.
    static let smallestDisc: CGFloat = 96
    /// Estimate until the controls have been measured once.
    static let estimatedCoreHeight: CGFloat = 300

    let size: CGSize
    let disc: CGFloat
    let showsToggles: Bool
    let showsHeader: Bool
    let controlsWidth: CGFloat
    let controlsHeight: CGFloat

    /// `coreControlsHeight` = title, slider, play buttons and bottom row
    /// (everything but the toggle row), as measured.
    init(size: CGSize, coreControlsHeight core: CGFloat) {
        self.size = size
        let usableWidth = max(0, size.width - 2 * Self.side)
        controlsWidth = min(usableWidth, Self.maxControlsWidth)

        func discFor(toggles: Bool, header: Bool) -> CGFloat {
            let controls = core + (toggles ? Self.togglesHeight : 0)
            let height = size.height - 2 * Self.margin - (header ? Self.headerHeight : 0)
            return max(0, min(usableWidth, height - controls - Self.gap))
        }

        var toggles = true
        var header = true
        var disc = discFor(toggles: true, header: true)
        if disc < Self.comfortableDisc {
            toggles = false
            disc = discFor(toggles: false, header: true)
        }
        if disc < Self.smallestDisc, core + 2 * Self.margin + Self.headerHeight > size.height {
            header = false
            disc = discFor(toggles: false, header: false)
        }
        showsToggles = toggles
        showsHeader = header
        self.disc = disc >= Self.smallestDisc ? disc.rounded(.down) : 0
        controlsHeight = core + (toggles ? Self.togglesHeight : 0)
    }

    var usableHeight: CGFloat { size.height - 2 * Self.margin - (showsHeader ? Self.headerHeight : 0) }

    /// Disc + gap + controls.
    var blockHeight: CGFloat { (disc > 0 ? disc + Self.gap : 0) + controlsHeight }

    /// Everything inside the visible area.
    var fits: Bool {
        blockHeight <= usableHeight + 0.5 && disc <= size.width - 2 * Self.side + 0.5
    }

    /// Top of the disc in the layout's own coordinates (block centred in the
    /// space below the header).
    var discTop: CGFloat {
        Self.margin + (showsHeader ? Self.headerHeight : 0) + max(0, (usableHeight - blockHeight) / 2)
    }
}
