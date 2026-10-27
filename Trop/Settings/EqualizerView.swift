//
//  EqualizerView.swift
//  Trop / Resona
//
//  10-band equalizer in Material 3: a graph whose points are dragged up and
//  down (±12 dB) with a dB axis on the left, the band frequency under every
//  point and a value bubble while dragging; presets as M3 filter chips.
//

import SwiftUI

struct EqualizerView: View {
    @Environment(\.settingsStore) private var settings
    @Environment(\.m3) private var m3
    @State private var dragIndex: Int?

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(spacing: 20) {
                SettingsPageTitle(title: "Equalizer")
                    .padding(.horizontal, 16)
                VStack(spacing: 16) {
                    Toggle(isOn: $settings.equalizerEnabled) {
                        Text(LocalizedStringKey(settings.equalizerEnabled ? "Equalizer On" : "Equalizer Off"))
                            .font(.m3(.titleMedium, weight: .medium))
                            .foregroundStyle(m3.onSurface)
                    }
                    .toggleStyle(.m3)

                    EqualizerGraph(gains: $settings.equalizerGains, activeDrag: $dragIndex)
                        .frame(height: 280)
                        .opacity(settings.equalizerEnabled ? 1 : 0.55)
                }
                .padding(20)
                .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: M3Shape.extraLarge, style: .continuous))
                .padding(.horizontal, 16)

                presetStrip(settings: settings)
            }
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .m3ScreenBackground()
        .settingsPageChrome("Equalizer")
        .onChange(of: settings.equalizerEnabled) { _, _ in
            PlayerController.shared.applyPlaybackSettings()
        }
    }

    private func presetStrip(settings: SettingsStore) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(EqualizerPresets.all, id: \.id) { preset in
                    M3Chip(
                        title: String(localized: String.LocalizationValue(preset.name)),
                        isSelected: settings.equalizerPresetID == preset.id
                    ) {
                        settings.equalizerGains = preset.gains
                        settings.equalizerPresetID = preset.id
                        PlayerController.shared.applyPlaybackSettings()
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

/// Interactive band graph: fixed x per band, y from the gain.
private struct EqualizerGraph: View {
    @Environment(\.m3) private var m3
    @Binding var gains: [Double]
    @Binding var activeDrag: Int?

    /// Room on the left for the dB axis, at the bottom for frequencies.
    private let axisWidth: CGFloat = 46
    private let freqHeight: CGFloat = 24
    private let inset: CGFloat = 14
    private let axisValues: [Double] = [12, 6, 0, -6, -12]

    var body: some View {
        GeometryReader { geo in
            let plot = CGRect(
                x: axisWidth + inset,
                y: inset,
                width: max(1, geo.size.width - axisWidth - inset * 2),
                height: max(1, geo.size.height - freqHeight - inset * 2)
            )
            let points = gains.enumerated().map { point(index: $0.offset, gain: $0.element, in: plot) }

            ZStack(alignment: .topLeading) {
                // Grid + dB axis (vertical, left).
                ForEach(axisValues, id: \.self) { db in
                    let y = yFor(gain: db, in: plot)
                    Path { p in
                        p.move(to: CGPoint(x: plot.minX, y: y))
                        p.addLine(to: CGPoint(x: plot.maxX, y: y))
                    }
                    .stroke(m3.outlineVariant.opacity(db == 0 ? 0.9 : 0.45), style: StrokeStyle(lineWidth: 1, dash: db == 0 ? [] : [4, 4]))
                    Text(db > 0 ? "+\(Int(db)) dB" : "\(Int(db)) dB")
                        .font(.m3(.labelSmall))
                        .foregroundStyle(m3.onSurfaceVariant)
                        .frame(width: axisWidth, alignment: .trailing)
                        .position(x: axisWidth / 2, y: y)
                }

                if points.count >= 2 {
                    fillPath(points, plot: plot)
                        .fill(LinearGradient(colors: [m3.primary.opacity(0.28), m3.primary.opacity(0)], startPoint: .top, endPoint: .bottom))
                    linePath(points)
                        .stroke(m3.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }

                ForEach(Array(points.enumerated()), id: \.offset) { index, p in
                    let active = activeDrag == index
                    Circle()
                        .fill(m3.primary)
                        .frame(width: active ? 22 : 14, height: active ? 22 : 14)
                        .overlay(Circle().stroke(m3.onPrimary, lineWidth: 2))
                        .position(p)
                        .animation(M3Motion.fastSpatial, value: active)

                    // Frequency under every point.
                    Text(Self.label(for: equalizerFrequencies[safe: index] ?? 0))
                        .font(.m3(.labelSmall))
                        .foregroundStyle(active ? m3.primary : m3.onSurfaceVariant)
                        .fixedSize()
                        .position(x: p.x, y: geo.size.height - freqHeight / 2)

                    // Value bubble while dragging.
                    if active {
                        let gain = gains[index]
                        Text(gain > 0 ? "+\(Int(gain)) dB" : "\(Int(gain)) dB")
                            .font(.m3(.labelLarge, weight: .medium))
                            .foregroundStyle(m3.onPrimaryContainer)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(m3.primaryContainer, in: Capsule())
                            .fixedSize()
                            .position(x: p.x, y: max(14, p.y - 30))
                            .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let index = activeDrag ?? bandIndex(for: value.location.x, in: plot)
                        if activeDrag == nil { withAnimation(M3Motion.fastSpatial) { activeDrag = index } }
                        setGain(gain(for: value.location.y, in: plot), at: index)
                    }
                    .onEnded { _ in
                        withAnimation(M3Motion.fastSpatial) { activeDrag = nil }
                    }
            )
            .sensoryFeedback(.selection, trigger: activeDrag.map { gains[$0] })
        }
    }

    static func label(for hz: Double) -> String {
        hz >= 1000 ? (hz.truncatingRemainder(dividingBy: 1000) == 0 ? "\(Int(hz / 1000))k" : String(format: "%.1fk", hz / 1000)) : "\(Int(hz))"
    }

    private func yFor(gain: Double, in plot: CGRect) -> CGFloat {
        let normalized = (gain - equalizerMinGain) / (equalizerMaxGain - equalizerMinGain)
        return plot.minY + plot.height * CGFloat(1 - normalized)
    }

    private func point(index: Int, gain: Double, in plot: CGRect) -> CGPoint {
        let x = plot.minX + plot.width * CGFloat(index) / CGFloat(max(1, gains.count - 1))
        return CGPoint(x: x, y: yFor(gain: gain, in: plot))
    }

    private func linePath(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: points[0])
        for p in points.dropFirst() { path.addLine(to: p) }
        return path
    }

    private func fillPath(_ points: [CGPoint], plot: CGRect) -> Path {
        var path = linePath(points)
        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: plot.maxY))
        path.addLine(to: CGPoint(x: points[0].x, y: plot.maxY))
        path.closeSubpath()
        return path
    }

    private func bandIndex(for x: CGFloat, in plot: CGRect) -> Int {
        let f = max(0, min(1, (x - plot.minX) / plot.width))
        return min(max(0, Int((f * CGFloat(gains.count - 1)).rounded())), gains.count - 1)
    }

    private func gain(for y: CGFloat, in plot: CGRect) -> Double {
        let f = max(0, min(1, (y - plot.minY) / plot.height))
        let gain = equalizerMinGain + (1 - Double(f)) * (equalizerMaxGain - equalizerMinGain)
        return min(equalizerMaxGain, max(equalizerMinGain, gain.rounded()))
    }

    private func setGain(_ gain: Double, at index: Int) {
        guard gains.indices.contains(index), gains[index] != gain else { return }
        gains[index] = gain
        SettingsStore.shared.equalizerPresetID = "custom"
        PlayerController.shared.applyPlaybackSettings()
    }
}
