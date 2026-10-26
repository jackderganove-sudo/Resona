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
    }

    private func schedule() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in SleepTimer.shared.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let np = NowPlaying.shared
        if let endDate, endDate <= Date() {
            fire()
        } else if stopAtSongEnd, np.duration > 0, np.duration - np.currentTime < 0.8 {
            fire()
        }
    }

    private func fire() {
        cancel()
        PlayerController.shared.setPaused(true)
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
            .background(m3.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: M3Shape.extraLarge, style: .continuous))
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
