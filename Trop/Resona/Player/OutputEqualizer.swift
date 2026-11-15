//
//  OutputEqualizer.swift
//  Resona
//
//  EQ per output device (round 12): the app remembers the equalizer per
//  output (iPad speaker, "Soundcore Space One", "Echo Dot", an AirPlay name)
//  and switches when the output changes, with a short hint "EQ: <preset> for
//  <device>". Unknown devices use the default EQ; "Same for all devices"
//  turns the feature off. Same logic, texts and icons as Resona-Android's
//  OutputEq.kt.
//
//  Rules (both platforms):
//  - Same for all devices on: every device uses the default EQ, edits change it.
//  - Off: a device with its own EQ uses it; any other device uses the default.
//    An edit on a device saves it as that device's own EQ. "Use default EQ"
//    forgets the device's own EQ.
//

import Foundation
import Observation
import SwiftUI

/// What the equalizer is set to (enough to restore it exactly).
struct EqSnapshot: Codable, Equatable {
    var enabled: Bool
    var presetID: String
    var gains: [Double]
}

struct OutputEqState: Codable, Equatable {
    struct Device: Codable, Equatable {
        var name: String
        var eq: EqSnapshot
    }

    var sameForAll = false
    var standard: EqSnapshot?
    var devices: [String: Device] = [:]
}

/// Pure rules, unit-tested; the same functions exist in Kotlin.
enum OutputEqRules {
    static let builtInKey = "builtin"

    static func key(for output: AudioOutput) -> String {
        guard output.isExternal else { return builtInKey }
        return "\(output.kind):\(output.name.trimmingCharacters(in: .whitespaces).lowercased())"
    }

    static func resolve(_ state: OutputEqState, key: String) -> EqSnapshot? {
        if state.sameForAll { return state.standard }
        return state.devices[key]?.eq ?? state.standard
    }

    static func hasOwn(_ state: OutputEqState, key: String) -> Bool {
        !state.sameForAll && state.devices[key] != nil
    }

    /// An edit while [key] is the output.
    static func record(_ state: OutputEqState, key: String, name: String, eq: EqSnapshot) -> OutputEqState {
        var out = state
        if state.sameForAll {
            out.standard = eq
        } else {
            out.devices[key] = .init(name: name, eq: eq)
        }
        return out
    }

    static func useStandard(_ state: OutputEqState, key: String) -> OutputEqState {
        var out = state
        out.devices[key] = nil
        return out
    }

    /// What to apply when the output becomes [key]; nil = nothing changes.
    static func switchTo(_ state: OutputEqState, key: String, current: EqSnapshot) -> EqSnapshot? {
        guard let target = resolve(state, key: key), target != current else { return nil }
        return target
    }
}

@MainActor
@Observable
final class OutputEqualizer {
    static let shared = OutputEqualizer()
    private static let storageKey = "resona.outputEq"

    private(set) var state: OutputEqState
    private(set) var output: AudioOutput = .builtInSpeaker
    /// "EQ: Bass Boost for Soundcore Space One", shown for a few seconds.
    private(set) var hint: String?
    @ObservationIgnored private var hintTask: Task<Void, Never>?

    var key: String { OutputEqRules.key(for: output) }
    var hasOwn: Bool { OutputEqRules.hasOwn(state, key: key) }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(OutputEqState.self, from: data) {
            state = saved
        } else {
            state = OutputEqState()
        }
        if state.standard == nil {
            state.standard = Self.currentSnapshot()
            save()
        }
    }

    /// Called at launch: take the current output without switching.
    func start() {
        output = AudioOutputMonitor.shared.current
    }

    static func currentSnapshot() -> EqSnapshot {
        let s = SettingsStore.shared
        return EqSnapshot(enabled: s.equalizerEnabled, presetID: s.equalizerPresetID, gains: s.equalizerGains)
    }

    /// From AudioOutputMonitor whenever the route changes.
    func outputChanged(_ new: AudioOutput) {
        let changed = OutputEqRules.key(for: new) != key
        output = new
        guard changed else { return }
        applyResolved(showHint: true)
    }

    /// The EQ screen changed something: remember it for this output (or for all).
    func recordEdit() {
        state = OutputEqRules.record(state, key: key, name: output.displayName, eq: Self.currentSnapshot())
        save()
    }

    func setSameForAll(_ on: Bool) {
        guard state.sameForAll != on else { return }
        if on {
            // The EQ heard right now becomes the one for all devices.
            state.standard = Self.currentSnapshot()
        }
        state.sameForAll = on
        save()
        applyResolved(showHint: false)
    }

    func useStandard() {
        state = OutputEqRules.useStandard(state, key: key)
        save()
        applyResolved(showHint: false)
    }

    private func applyResolved(showHint: Bool) {
        guard let target = OutputEqRules.switchTo(state, key: key, current: Self.currentSnapshot()) else { return }
        let s = SettingsStore.shared
        s.equalizerEnabled = target.enabled
        s.equalizerPresetID = target.presetID
        if target.gains.count == equalizerFrequencies.count { s.equalizerGains = target.gains }
        PlayerController.shared.applyPlaybackSettings()
        if showHint { show(Self.hintText(target, device: output.displayName)) }
    }

    nonisolated static func presetName(_ eq: EqSnapshot) -> String {
        guard eq.enabled else { return String(localized: "Off") }
        if let preset = EqualizerPresets.all.first(where: { $0.id == eq.presetID }) {
            return String(localized: String.LocalizationValue(preset.name))
        }
        return String(localized: "Custom")
    }

    nonisolated static func hintText(_ eq: EqSnapshot, device: String) -> String {
        String(format: String(localized: "EQ: %1$@ for %2$@"), presetName(eq), device)
    }

    private func show(_ text: String) {
        hintTask?.cancel()
        withAnimation(M3Motion.defaultSpatial) { hint = text }
        hintTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(M3Motion.defaultSpatial) { self.hint = nil }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

/// Small pill at the top: "EQ: Bass Boost for Soundcore Space One".
struct OutputEqHintView: View {
    @Environment(\.m3) private var m3
    private let eq = OutputEqualizer.shared

    var body: some View {
        ZStack {
            if let hint = eq.hint {
                Label(hint, systemImage: "slider.vertical.3")
                    .font(.m3(.labelLarge, weight: .medium))
                    .foregroundStyle(m3.onSurface)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(m3.surfaceContainerHigh, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityIdentifier("eq.output.hint")
            }
        }
        .allowsHitTesting(false)
    }
}

/// Top of the EQ screen: "Applies to: <device>", "Same for all devices".
struct OutputEqHeader: View {
    @Environment(\.m3) private var m3
    private let eq = OutputEqualizer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: eq.state.sameForAll ? "speaker.wave.2.fill" : eq.output.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(m3.primary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: String(localized: "Applies to: %@"),
                                eq.state.sameForAll ? String(localized: "All devices") : eq.output.displayName))
                        .font(.m3(.titleSmall, weight: .semibold))
                        .foregroundStyle(m3.onSurface)
                        .accessibilityIdentifier("eq.output.appliesTo")
                    if !eq.state.sameForAll {
                        Text(LocalizedStringKey(eq.hasOwn ? "Own EQ for this device" : "Default EQ – changes apply to this device only"))
                            .font(.m3(.bodySmall))
                            .foregroundStyle(m3.onSurfaceVariant)
                    }
                }
                Spacer(minLength: 0)
            }
            Toggle(isOn: Binding(get: { eq.state.sameForAll }, set: { eq.setSameForAll($0) })) {
                Text("Same for all devices")
                    .font(.m3(.bodyLarge))
                    .foregroundStyle(m3.onSurface)
            }
            .toggleStyle(.m3)
            .accessibilityIdentifier("eq.output.sameForAll")
            if eq.hasOwn {
                Button("Use default EQ") { eq.useStandard() }
                    .font(.m3(.labelLarge, weight: .semibold))
                    .foregroundStyle(m3.primary)
                    .accessibilityIdentifier("eq.output.useDefault")
            }
        }
        .padding(20)
        .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: M3Shape.extraLarge, style: .continuous))
    }
}
