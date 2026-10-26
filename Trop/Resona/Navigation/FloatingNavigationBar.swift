//
//  FloatingNavigationBar.swift
//  Resona
//
//  Floating short navigation bar (bottom, compact width) and navigation rail
//  (side, regular width). The active destination gets a pill indicator that
//  slides between items with an expressive spring and stretches while moving.
//

import SwiftUI

// MARK: - Bottom bar

struct FloatingNavigationBar: View {
    @Environment(\.m3) private var m3
    @Binding var selection: ResonaTab
    /// 0 = standalone, 1 = docked under the mini player (junction corners).
    var miniPlayerProximity: CGFloat
    var onReselect: (ResonaTab) -> Void

    @Namespace private var pill

    var body: some View {
        let top = lerp(M3Metrics.floatingBarStandaloneRadius, M3Metrics.floatingBarJunctionRadius, miniPlayerProximity)
        let bottom = lerp(M3Metrics.floatingBarStandaloneRadius, M3Metrics.floatingBarOuterRadius, miniPlayerProximity)
        let shape = UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: top, bottomLeading: bottom, bottomTrailing: bottom, topTrailing: top),
            style: .continuous
        )

        HStack(spacing: 0) {
            ForEach(ResonaTab.ordered) { tab in
                NavigationItem(
                    tab: tab,
                    isSelected: tab == selection,
                    namespace: pill,
                    layout: .bar
                ) {
                    select(tab)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: 360)
        .padding(.vertical, 8)
        .frame(maxWidth: M3Metrics.navigationBarMaxWidth)
        .frame(height: M3Metrics.navigationBarHeight)
        .frame(maxWidth: .infinity)
        // Frosted: content scrolling behind the bar shows through blurred.
        .background { FrostedSurface(shape: shape, tint: m3.surfaceContainer, tintOpacity: 0.74) }
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        .animation(M3Motion.defaultSpatial, value: miniPlayerProximity)
    }

    private func select(_ tab: ResonaTab) {
        if tab == selection {
            onReselect(tab)
        } else {
            withAnimation(M3Motion.defaultSpatial) { selection = tab }
        }
    }
}

// MARK: - Rail

struct NavigationRail: View {
    @Environment(\.m3) private var m3
    @Binding var selection: ResonaTab
    var onReselect: (ResonaTab) -> Void

    @Namespace private var pill

    var body: some View {
        VStack(spacing: 12) {
            ResonaGlyph()
                .frame(width: 40, height: 40)
                .padding(.top, 12)
                .padding(.bottom, 28)

            ForEach(ResonaTab.ordered) { tab in
                NavigationItem(tab: tab, isSelected: tab == selection, namespace: pill, layout: .rail) {
                    if tab == selection {
                        onReselect(tab)
                    } else {
                        withAnimation(M3Motion.defaultSpatial) { selection = tab }
                    }
                }
            }
            Spacer()
        }
        .frame(width: M3Metrics.navigationRailWidth)
        .frame(maxHeight: .infinity)
        .background(m3.surfaceContainerLow.ignoresSafeArea())
    }
}

// MARK: - Item

private struct NavigationItem: View {
    enum Layout { case bar, rail }

    @Environment(\.m3) private var m3
    let tab: ResonaTab
    let isSelected: Bool
    let namespace: Namespace.ID
    let layout: Layout
    let action: () -> Void

    @State private var bounce = 0

    var body: some View {
        Button {
            bounce += 1
            action()
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(m3.primaryContainer)
                            .matchedGeometryEffect(id: "pill", in: namespace)
                            .frame(width: 56, height: 32)
                            .transition(.scale(scale: 0.4, anchor: .center).combined(with: .opacity))
                    }
                    Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                        .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? m3.primary : m3.onSurfaceVariant)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: bounce)
                }
                .frame(width: 64, height: 32)

                Text(tab.title)
                    .font(.m3(.labelMedium, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? m3.primary : m3.onSurfaceVariant)
                    .lineLimit(1)
            }
            .frame(maxWidth: layout == .bar ? .infinity : nil)
            .frame(height: layout == .bar ? 62 : 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.expressive(scale: 0.9))
        .accessibilityLabel(Text(tab.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Brand glyph

/// Resona's mark (dot + resonance arcs), drawn in the current primary colour.
struct ResonaGlyph: View {
    @Environment(\.m3) private var m3

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let center = CGPoint(x: s * 0.36, y: s * 0.5)
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - s * 0.12, y: center.y - s * 0.12, width: s * 0.24, height: s * 0.24)), with: .color(m3.primary))
            for (i, r) in [0.22, 0.34, 0.46].enumerated() {
                var arc = Path()
                let angle = Angle.degrees([56.0, 48.0, 40.0][i])
                arc.addArc(center: center, radius: s * r, startAngle: -angle, endAngle: angle, clockwise: false)
                ctx.stroke(arc, with: .color(m3.primary.opacity(1 - Double(i) * 0.25)), style: StrokeStyle(lineWidth: s * 0.07, lineCap: .round))
            }
        }
    }
}

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * min(max(t, 0), 1)
}
