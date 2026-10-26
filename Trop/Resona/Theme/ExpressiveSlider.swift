//
//  ExpressiveSlider.swift
//  Resona
//
//  Material 3 Expressive slider: thick rounded track split by a slim
//  vertical handle with a gap on both sides, a stop indicator at the end of
//  the inactive track and optional tick dots for discrete values.
//

import SwiftUI

struct ExpressiveSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    /// Number of discrete steps (nil = continuous). Draws tick dots.
    var steps: Int?
    var trackHeight: CGFloat = 16
    var handleHeight: CGFloat = 44
    var activeColor: Color
    var inactiveColor: Color
    var handleColor: Color?
    var showsStopIndicator = true
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var isDragging = false
    @State private var lastStep: Int?

    private let handleWidth: CGFloat = 4
    private let gap: CGFloat = 6

    private var fraction: Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let usable = max(1, width - handleWidth)
            let handleX = CGFloat(fraction) * usable
            let activeWidth = max(0, handleX - gap)
            let inactiveStart = handleX + handleWidth + gap
            let inactiveWidth = max(0, width - inactiveStart)
            let midY = geo.size.height / 2
            let outer = trackHeight / 2
            let inner: CGFloat = 4

            ZStack(alignment: .leading) {
                // Active track
                if activeWidth > 0.5 {
                    UnevenRoundedRectangle(
                        cornerRadii: .init(topLeading: outer, bottomLeading: outer, bottomTrailing: min(inner, activeWidth / 2), topTrailing: min(inner, activeWidth / 2)),
                        style: .continuous
                    )
                    .fill(activeColor)
                    .frame(width: activeWidth, height: trackHeight)
                    .position(x: activeWidth / 2, y: midY)
                }

                // Inactive track
                if inactiveWidth > 0.5 {
                    UnevenRoundedRectangle(
                        cornerRadii: .init(topLeading: min(inner, inactiveWidth / 2), bottomLeading: min(inner, inactiveWidth / 2), bottomTrailing: outer, topTrailing: outer),
                        style: .continuous
                    )
                    .fill(inactiveColor)
                    .frame(width: inactiveWidth, height: trackHeight)
                    .position(x: inactiveStart + inactiveWidth / 2, y: midY)
                }

                // Tick dots / stop indicator
                if let steps, steps > 1 {
                    ForEach(0...steps, id: \.self) { i in
                        let x = CGFloat(Double(i) / Double(steps)) * usable + handleWidth / 2
                        let onActive = x < handleX - gap
                        let hidden = abs(x - (handleX + handleWidth / 2)) < gap + handleWidth
                        Circle()
                            .fill(onActive ? inactiveColor : activeColor)
                            .frame(width: 4, height: 4)
                            .position(x: min(max(x, outer), width - outer), y: midY)
                            .opacity(hidden ? 0 : 1)
                    }
                } else if showsStopIndicator, inactiveWidth > outer * 2 {
                    Circle()
                        .fill(activeColor)
                        .frame(width: 4, height: 4)
                        .position(x: width - outer, y: midY)
                }

                // Handle
                Capsule()
                    .fill(handleColor ?? activeColor)
                    .frame(width: isDragging ? 2 : handleWidth, height: handleHeight)
                    .position(x: handleX + handleWidth / 2, y: midY)
                    .animation(M3Motion.fastSpatial, value: isDragging)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        update(x: g.location.x, usable: usable)
                    }
                    .onEnded { g in
                        update(x: g.location.x, usable: usable)
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: max(handleHeight, trackHeight))
        .sensoryFeedback(.selection, trigger: lastStep)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((fraction * 100).rounded())) %"))
        .accessibilityAdjustableAction { direction in
            let delta = (range.upperBound - range.lowerBound) / Double(steps ?? 20)
            switch direction {
            case .increment: value = min(range.upperBound, value + delta)
            case .decrement: value = max(range.lowerBound, value - delta)
            @unknown default: break
            }
        }
    }

    private func update(x: CGFloat, usable: CGFloat) {
        var f = Double(min(max((x - handleWidth / 2) / usable, 0), 1))
        if let steps, steps > 0 {
            let step = Int((f * Double(steps)).rounded())
            f = Double(step) / Double(steps)
            if step != lastStep { lastStep = step }
        }
        value = range.lowerBound + f * (range.upperBound - range.lowerBound)
    }
}
