//
//  SpeakerPicker.swift
//  Resona
//
//  "Speakers" (round 12): the player's output button opens a glass sheet with
//  the current output and the system's output list (AVRoutePickerView: iPad,
//  Bluetooth devices in range, AirPlay). iOS lets apps neither search for nor
//  pair Bluetooth devices, so the sheet only points to the iPad settings for
//  new ones. Same texts, icons and order as Resona-Android's sheet.
//

import AVFoundation
import AVKit
import Observation
import SwiftUI
import UIKit

/// The current audio output, as the player and mini player show it.
struct AudioOutput: Equatable {
    enum Kind: Equatable {
        case builtIn, bluetooth, headphones, airPlay, car, tv, other
    }

    let kind: Kind
    let name: String

    static let builtInSpeaker = AudioOutput(kind: .builtIn, name: "")

    static func kind(forPortType type: String) -> Kind {
        switch type {
        case AVAudioSession.Port.builtInSpeaker.rawValue, AVAudioSession.Port.builtInReceiver.rawValue:
            return .builtIn
        case AVAudioSession.Port.bluetoothA2DP.rawValue, AVAudioSession.Port.bluetoothLE.rawValue,
             AVAudioSession.Port.bluetoothHFP.rawValue:
            return .bluetooth
        case AVAudioSession.Port.headphones.rawValue, AVAudioSession.Port.usbAudio.rawValue,
             AVAudioSession.Port.lineOut.rawValue:
            return .headphones
        case AVAudioSession.Port.airPlay.rawValue:
            return .airPlay
        case AVAudioSession.Port.carAudio.rawValue:
            return .car
        case AVAudioSession.Port.HDMI.rawValue:
            return .tv
        default:
            return .other
        }
    }

    /// Same icon meaning as Android: speaker, headphones, AirPlay, car, TV.
    var systemImage: String {
        switch kind {
        case .builtIn: return "ipad"
        case .bluetooth:
            let lower = name.lowercased()
            if lower.contains("airpods") { return "airpods" }
            if lower.contains("buds") || lower.contains("headphone") || lower.contains("kopfhörer") { return "headphones" }
            return "hifispeaker.fill"
        case .headphones: return "headphones"
        case .airPlay: return "airplayaudio"
        case .car: return "car.fill"
        case .tv: return "tv"
        case .other: return "speaker.wave.2.fill"
        }
    }

    var displayName: String {
        kind == .builtIn || name.isEmpty ? String(localized: "This device") : name
    }

    var isExternal: Bool { kind != .builtIn }
}

@MainActor
@Observable
final class AudioOutputMonitor {
    static let shared = AudioOutputMonitor()

    private(set) var current: AudioOutput = .builtInSpeaker
    /// Other outputs in reach (AirPlay / Bluetooth), only known while the sheet is open.
    private(set) var othersAvailable = false

    @ObservationIgnored private let detector = AVRouteDetector()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        refresh()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AudioOutputMonitor.shared.refresh() }
        })
        observers.append(center.addObserver(forName: .AVRouteDetectorMultipleRoutesDetectedDidChange, object: nil, queue: .main) { _ in
            Task { @MainActor in AudioOutputMonitor.shared.othersAvailable = AudioOutputMonitor.shared.detector.multipleRoutesDetected }
        })
    }

    func refresh() {
        guard let port = AVAudioSession.sharedInstance().currentRoute.outputs.first else {
            current = .builtInSpeaker
            return
        }
        current = AudioOutput(kind: AudioOutput.kind(forPortType: port.portType.rawValue), name: port.portName)
    }

    /// Route detection costs battery: only while the sheet is visible.
    func setDetecting(_ on: Bool) {
        detector.isRouteDetectionEnabled = on
        othersAvailable = on && detector.multipleRoutesDetected
    }
}

/// Player button where the AirPlay button was: a round icon on this device,
/// a pill with icon + name ("Echo Dot") in the cover accent on an external
/// output. Always 48 pt high, so no player layout moves.
struct PlayerSpeakerButton: View {
    @Environment(\.playerAccent) private var playerAccent
    @State private var showPicker = false
    private let monitor = AudioOutputMonitor.shared

    var body: some View {
        Button {
            showPicker = true
        } label: {
            let external = monitor.current.isExternal
            HStack(spacing: 8) {
                Image(systemName: monitor.current.systemImage)
                    .font(.system(size: 19, weight: .semibold))
                if external {
                    Text(monitor.current.displayName)
                        .font(.m3(.labelLarge, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: 140)
                        .fixedSize()
                }
            }
            .foregroundStyle(external ? playerAccent.on : .white.opacity(0.85))
            .padding(.horizontal, external ? 16 : 0)
            .frame(minWidth: 48, minHeight: 48, maxHeight: 48)
            .background(external ? playerAccent.container : .white.opacity(0.1), in: Capsule())
            .animation(M3Motion.defaultSpatial, value: monitor.current)
        }
        .buttonStyle(.expressive(scale: 0.9))
        .accessibilityLabel(Text("Speakers"))
        .accessibilityValue(Text(monitor.current.displayName))
        .accessibilityIdentifier("player.speakers")
        .sheet(isPresented: $showPicker) {
            SpeakerPickerSheet()
        }
    }
}

/// Small "icon + name" line for the player and mini player, only for external outputs.
struct CurrentOutputLabel: View {
    var font: Font = .m3(.labelMedium, weight: .medium)
    var color: Color = .white.opacity(0.8)
    private let monitor = AudioOutputMonitor.shared

    var body: some View {
        if monitor.current.isExternal {
            Label(monitor.current.displayName, systemImage: monitor.current.systemImage)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .accessibilityIdentifier("output.current")
        }
    }
}

/// Sheet: current output · choose output (system list) · pairing hint.
struct SpeakerPickerSheet: View {
    @Environment(\.m3) private var m3
    @Environment(\.openURL) private var openURL
    private let monitor = AudioOutputMonitor.shared

    var body: some View {
        SheetChrome {
            Text("Speakers")
                .font(.m3(.titleLarge, weight: .semibold))
                .foregroundStyle(m3.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            MenuCard {
                HStack(spacing: 20) {
                    Image(systemName: monitor.current.systemImage)
                        .font(.system(size: 21))
                        .foregroundStyle(m3.primary)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(monitor.current.displayName)
                            .font(.m3(.titleMedium))
                            .foregroundStyle(m3.onSurface)
                        Text("Connected")
                            .font(.m3(.bodyMedium))
                            .foregroundStyle(m3.onSurfaceVariant)
                    }
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(m3.primary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("speakers.current")

                Divider().padding(.leading, 68)

                // The system list sits invisibly over the row: one tap opens it.
                MenuRowLabel(
                    icon: "list.bullet",
                    title: "Choose output",
                    subtitle: monitor.othersAvailable
                        ? String(localized: "iPad, Bluetooth devices in range and AirPlay")
                        : String(localized: "No other output found yet")
                )
                .overlay(SystemRoutePicker())
                .accessibilityIdentifier("speakers.choose")
            }

            MenuCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("New Bluetooth device? Pair it once in the iPad settings.", systemImage: "info.circle")
                        .font(.m3(.bodyMedium))
                        .foregroundStyle(m3.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        Text("Open Settings")
                            .font(.m3(.labelLarge, weight: .semibold))
                    }
                    .accessibilityIdentifier("speakers.openSettings")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            monitor.refresh()
            monitor.setDetecting(true)
        }
        .onDisappear { monitor.setDetecting(false) }
    }
}

/// AVRoutePickerView with an invisible glyph, stretched over a row.
private struct SystemRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .clear
        picker.activeTintColor = .clear
        picker.prioritizesVideoDevices = false
        picker.backgroundColor = .clear
        return picker
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
