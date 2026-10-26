//
//  SettingsComponents.swift
//  Trop / Resona
//
//  Created by 686udjie on 20/08/2026.
//  Material 3 rows for the settings subpages (used inside `M3Section`):
//  outline icon in a tonal circle, M3 switch, M3 dropdown, slider instead
//  of a stepper.
//

import SwiftUI

struct SettingsNavigationRow<Destination: View>: View {
    @Environment(\.m3) private var m3
    let title: String
    let icon: String
    @ViewBuilder var destination: () -> Destination

    init(_ title: String, icon: String, @ViewBuilder destination: @escaping () -> Destination) {
        self.title = title
        self.icon = icon
        self.destination = destination
    }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Label(LocalizedStringKey(title), systemImage: icon)
                    .foregroundStyle(m3.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(m3.onSurfaceVariant)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(M3RowPressStyle())
    }
}

struct SettingsToggleRow: View {
    @Environment(\.m3) private var m3
    let title: String
    let icon: String?
    @Binding var isOn: Bool

    init(_ title: String, icon: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.icon = icon
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            if let icon {
                Label(LocalizedStringKey(title), systemImage: icon)
            } else {
                Text(LocalizedStringKey(title))
                    .font(.m3(.titleMedium, weight: .regular))
            }
        }
        .toggleStyle(.m3)
        .foregroundStyle(m3.onSurface)
    }
}

struct SettingsPickerRow<T: SettingsOption>: View {
    @Environment(\.m3) private var m3
    let title: String
    let icon: String?
    @Binding var selection: T

    init(_ title: String, icon: String? = nil, selection: Binding<T>) {
        self.title = title
        self.icon = icon
        self._selection = selection
    }

    var body: some View {
        M3DropdownRow(
            selection: $selection,
            options: T.allCases.map { (value: $0, title: String(localized: String.LocalizationValue($0.displayName))) }
        ) {
            if let icon {
                Label(LocalizedStringKey(title), systemImage: icon)
            } else {
                Text(LocalizedStringKey(title))
                    .font(.m3(.titleMedium, weight: .regular))
            }
        }
        .foregroundStyle(m3.onSurface)
    }
}

/// Former stepper: now a stepped expressive slider with the value on the right.
struct SettingsStepperRow: View {
    @Environment(\.m3) private var m3
    let title: String
    let icon: String?
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    @Binding var value: Double

    init(_ title: String,
         icon: String? = nil,
         value: Binding<Double>,
         in range: ClosedRange<Double> = 0.5...2.0,
         step: Double = 0.1,
         format: @escaping (Double) -> String = { String(format: "%.1fx", $0) }) {
        self.title = title
        self.icon = icon
        self._value = value
        self.range = range
        self.step = step
        self.format = format
    }

    var body: some View {
        M3SliderRow(value: $value, range: range, step: step, format: format) {
            if let icon {
                Label(LocalizedStringKey(title), systemImage: icon)
            } else {
                Text(LocalizedStringKey(title))
                    .font(.m3(.titleMedium, weight: .regular))
            }
        }
        .foregroundStyle(m3.onSurface)
    }
}

struct SettingsLinkRow: View {
    @Environment(\.m3) private var m3
    let title: String
    let icon: String
    let url: URL

    init(_ title: String, icon: String, url: URL) {
        self.title = title
        self.icon = icon
        self.url = url
    }

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Label(LocalizedStringKey(title), systemImage: icon)
                    .foregroundStyle(m3.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(m3.onSurfaceVariant)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(M3RowPressStyle())
    }
}
