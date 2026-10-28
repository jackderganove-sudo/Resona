//
//  SleepTimer.swift
//  Resona
//
//  Pauses playback after a number of minutes or at the end of the current
//  song, plus the Material 3 dialog to set it (reference: sleep timer dialog
//  over the player).
//

import SwiftUI

@MainActor
@Observable
final class SleepTimer {
    static let shared = SleepTimer()

    private(set) var endDate: Date?
    private(set) var stopAtSongEnd = false
    private var timer: Timer?

    var isActive: Bool { endDate != nil || stopAtSongEnd }

    var remaining: TimeInterval? {
        endDate.map { max(0, $0.timeIntervalSinceNow) }
    }

    func start(minutes: Int) {
        stopAtSongEnd = false
        endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        schedule()
    }

    func startUntilSongEnd() {
        endDate = nil
        stopAtSongEnd = true
        schedule()
    }

    func cancel() {
        endDate = nil
        stopAtSongEnd = false
        timer?.invalidate()
        timer = nil
        restoreVolume()
    }

    /// Seconds left until the timer pauses playback (nil if unknown).
    private var secondsLeft: TimeInterval? {
        if let endDate { return endDate.timeIntervalSinceNow }
        let np = NowPlaying.shared
        if stopAtSongEnd, np.duration > 0 { return np.duration - np.currentTime }
        return nil
    }

    /// Fade-out in the last N seconds (setting; 0 = off).
    private func applyFade() {
        let fade = SettingsStore.shared.sleepFadeSeconds
        let player = PlayerController.shared
        guard fade > 0, let left = secondsLeft, left < fade else {
            if player.sleepFadeGain != 1 { restoreVolume() }
            return
        }
        let x = min(1, max(0, left / fade))
        let gain = x * x * (3 - 2 * x)   // smooth, ends at 0
        if abs(gain - player.sleepFadeGain) > 0.005 {
            player.sleepFadeGain = gain
            player.applyPlayerVolume()
        }
    }

    private func restoreVolume() {
        let player = PlayerController.shared
        guard player.sleepFadeGain != 1 else { return }
        player.sleepFadeGain = 1
        player.applyPlayerVolume()
    }

    private func schedule() {
        timer?.invalidate()
        // 10 Hz so the fade-out is smooth.
        let t = Timer(timeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in SleepTimer.shared.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        applyFade()
        let np = NowPlaying.shared
        if let endDate, endDate <= Date() {
            fire()
        } else if stopAtSongEnd, np.duration > 0, np.duration - np.currentTime < 0.8 {
            fire()
        }
    }

    private func fire() {
        endDate = nil
        stopAtSongEnd = false
        timer?.invalidate()
        timer = nil
        PlayerController.shared.setPaused(true)
        // Volume back to normal for the next play (after the pause landed).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            SleepTimer.shared.restoreVolume()
        }
    }
}

/// Material 3 basic dialog with a discrete expressive slider (5–120 min).
struct SleepTimerDialog: View {
    @Environment(\.m3) private var m3
    @Binding var isPresented: Bool
    @State private var minutes: Double = 30
    private let timer = SleepTimer.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                Text("Sleep timer")
                    .font(.m3(.headlineSmall))
                    .foregroundStyle(m3.onSurface)
                Text(minutesLabel)
                    .font(.m3(.titleMedium, weight: .regular))
                    .foregroundStyle(m3.onSurface)
                    .contentTransition(.numericText())
                    .animation(M3Motion.fastEffects, value: minutes)
                    .padding(.top, 2)

                ExpressiveSlider(
                    value: $minutes,
                    range: 5...120,
                    steps: 23,
                    activeColor: m3.primary,
                    inactiveColor: m3.primaryContainer
                )
                .padding(.top, 24)
                .padding(.horizontal, 12)

                Button {
                    timer.startUntilSongEnd()
                    dismiss()
                } label: {
                    Text("End of song")
                        .font(.m3(.labelLarge, weight: .regular))
                        .foregroundStyle(m3.onSurfaceVariant)
                        .padding(.horizontal, 24)
                        .frame(height: 40)
                        .overlay(Capsule().strokeBorder(m3.outline, lineWidth: 1))
                }
                .buttonStyle(.expressive)
                .padding(.top, 20)

                HStack {
                    if timer.isActive {
                        textButton("Reset") {
                            timer.cancel()
                            dismiss()
                        }
                    }
                    Spacer()
                    textButton("Cancel") { dismiss() }
                    textButton("OK") {
                        timer.start(minutes: Int(minutes))
                        dismiss()
                    }
                }
                .padding(.top, 28)
            }
            .padding(24)
            .frame(maxWidth: 400)
            .background {
                ResonaGlassBackground(shape: RoundedRectangle(cornerRadius: M3Shape.extraLarge, style: .continuous))
            }
            .padding(.horizontal, 24)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        .onAppear {
            if let remaining = timer.remaining {
                minutes = min(120, max(5, (remaining / 60 / 5).rounded() * 5))
            }
        }
    }

    private var minutesLabel: String {
        String(format: NSLocalizedString("%d minutes", comment: "Sleep timer duration"), Int(minutes))
    }

    private func textButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.m3(.labelLarge, weight: .medium))
                .foregroundStyle(m3.primary)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.expressive)
    }

    private func dismiss() {
        withAnimation(M3Motion.defaultSpatial) { isPresented = false }
    }
}

// MARK: - Player button

/// Sleep timer button for the player's bottom row. Inactive: moon. Active:
/// the remaining time counting down live (or "End of track"), widened with
/// a spring and filled with the player accent. Tapping while active turns
/// the timer off immediately.
struct SleepTimerButton: View {
    @Environment(\.playerAccent) private var playerAccent
    private let timer = SleepTimer.shared
    let onOpen: () -> Void
    let onCancelled: () -> Void

    var body: some View {
        Button {
            if timer.isActive {
                timer.cancel()
                onCancelled()
            } else {
                onOpen()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: timer.isActive ? "moon.fill" : "moon")
                    .font(.system(size: timer.isActive ? 15 : 19, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                if timer.isActive {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(label)
                            .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText(countsDown: true))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
                }
            }
            .foregroundStyle(timer.isActive ? playerAccent.on : .white.opacity(0.92))
            .padding(.horizontal, timer.isActive ? 16 : 0)
            .frame(minWidth: 48)
            .frame(height: 48)
            .background(timer.isActive ? playerAccent.container : .white.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.expressive)
        .animation(M3Motion.defaultSpatial, value: timer.isActive)
        .sensoryFeedback(.impact(weight: .medium), trigger: timer.isActive) { was, now in was && !now }
        .accessibilityLabel(Text(timer.isActive ? "Turn off sleep timer" : "Sleep timer"))
        .accessibilityIdentifier("player.sleep")
    }

    private var label: String {
        if timer.stopAtSongEnd { return String(localized: "End of track") }
        let remaining = Int((timer.remaining ?? 0).rounded(.up))
        let h = remaining / 3600, m = (remaining % 3600) / 60, s = remaining % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Small transient notice ("Sleep timer off").
struct PlayerToast: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.poppins(14, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background {
                ResonaGlassBackground(shape: Capsule())
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
