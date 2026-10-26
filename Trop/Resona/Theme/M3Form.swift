//
//  M3Form.swift
//  Resona
//
//  Material 3 settings forms. `M3Form` / `M3Section` are drop-in
//  replacements for `List` / `Section` (same call syntax incl. `header:` /
//  `footer:`), so every settings page keeps its logic while each row becomes
//  a tonal card with the segmented corners of the settings home page,
//  section titles in the accent colour (normal case), M3 switches and
//  outline icons in tonal circles.
//

import SwiftUI

// MARK: - Form

struct M3Form<Content: View>: View {
    @Environment(\.m3) private var m3
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .toggleStyle(.m3)
        .labelStyle(M3RowLabelStyle())
        .buttonStyle(M3RowPressStyle())
        .tint(m3.primary)
        .background(m3.surface.ignoresSafeArea())
    }
}

// MARK: - Section

struct M3Section<Content: View, Header: View, Footer: View>: View {
    @Environment(\.m3) private var m3
    private let content: Content
    private let header: Header
    private let footer: Footer

    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header, @ViewBuilder footer: () -> Footer) {
        self.content = content()
        self.header = header()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
                .font(.m3(.titleSmall, weight: .medium))
                .foregroundStyle(m3.primary)
                .textCase(nil)
                .padding(.horizontal, 12)

            Group(subviews: content) { rows in
                VStack(spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        let position = M3GroupPosition.of(index: index, count: rows.count)
                        row
                            .font(.m3(.bodyLarge))
                            .foregroundStyle(m3.onSurface)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .frame(minHeight: 60)
                            .background(m3.surfaceContainerLow, in: position.shape)
                            .contentShape(position.shape)
                    }
                }
            }

            footer
                .font(.m3(.bodySmall))
                .foregroundStyle(m3.onSurfaceVariant)
                .padding(.horizontal, 12)
        }
    }
}

extension M3Section where Header == EmptyView, Footer == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content, header: { EmptyView() }, footer: { EmptyView() })
    }
}

extension M3Section where Footer == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.init(content: content, header: header, footer: { EmptyView() })
    }
}

extension M3Section where Header == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(content: content, header: { EmptyView() }, footer: footer)
    }
}

extension M3Section where Header == Text, Footer == EmptyView {
    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { Text(title) }, footer: { EmptyView() })
    }
}

// MARK: - Row label

/// Outline icon in a tonal circle + title (used for every settings row and
/// menu entry, so icon styles are consistent app-wide).
struct M3RowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            M3IconCircle { configuration.icon }
            configuration.title
                .font(.m3(.titleMedium, weight: .regular))
                .lineLimit(2)
        }
    }
}

/// Tonal icon container: secondaryContainer circle, onSecondaryContainer
/// glyph (calm instead of bright white discs).
struct M3IconCircle<Icon: View>: View {
    @Environment(\.m3) private var m3
    var size: CGFloat = 40
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        icon()
            .font(.system(size: size * 0.45, weight: .regular))
            .symbolVariant(.none)
            .foregroundStyle(m3.onSecondaryContainer)
            .frame(width: size, height: size)
            .background(m3.secondaryContainer, in: Circle())
    }
}

// MARK: - Dropdown

/// Material 3 exposed dropdown: label on the left, current value in a tonal
/// pill with a chevron; opens a menu with a check next to the selection.
struct M3DropdownRow<Value: Hashable, Label: View>: View {
    @Environment(\.m3) private var m3
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    @ViewBuilder var label: () -> Label

    var body: some View {
        HStack(spacing: 12) {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                ForEach(options.indices, id: \.self) { i in
                    let option = options[i]
                    Button {
                        selection = option.value
                    } label: {
                        if option.value == selection {
                            SwiftUI.Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(currentTitle)
                        .font(.m3(.labelLarge, weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(m3.onSecondaryContainer)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(m3.secondaryContainer, in: Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
    }

    private var currentTitle: String {
        options.first { $0.value == selection }?.title ?? ""
    }
}

// MARK: - Slider row

/// Replaces steppers: title + value, an expressive slider, optional preview.
struct M3SliderRow<Label: View, Preview: View>: View {
    @Environment(\.m3) private var m3
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    @ViewBuilder var label: () -> Label
    @ViewBuilder var preview: () -> Preview

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                label()
                Spacer()
                Text(format(value))
                    .font(.m3(.labelLarge, weight: .medium).monospacedDigit())
                    .foregroundStyle(m3.primary)
                    .contentTransition(.numericText())
                    .animation(M3Motion.fastEffects, value: value)
            }
            ExpressiveSlider(
                value: Binding(
                    get: { value },
                    set: { value = (($0 / step).rounded() * step).clamped(to: range) }
                ),
                range: range,
                steps: Int(((range.upperBound - range.lowerBound) / step).rounded()),
                trackHeight: 14,
                handleHeight: 36,
                activeColor: m3.primary,
                inactiveColor: m3.secondaryContainer
            )
            preview()
        }
        .padding(.vertical, 6)
    }
}

extension M3SliderRow where Preview == EmptyView {
    init(value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: @escaping (Double) -> String, @ViewBuilder label: @escaping () -> Label) {
        self.init(value: value, range: range, step: step, format: format, label: label, preview: { EmptyView() })
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
