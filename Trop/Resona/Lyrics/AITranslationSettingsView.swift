//
//  AITranslationSettingsView.swift
//  Resona
//
//  Settings → Lyrics → AI translation: OpenRouter key (Keychain only),
//  model, own prompt, connection test.
//

import SwiftUI

struct AITranslationSettingsView: View {
    @Environment(\.settingsStore) private var settings
    @Environment(\.m3) private var m3
    @Environment(\.openURL) private var openURL
    private let status = LyricsAccountStatus.shared
    @State private var keyField = ""
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        @Bindable var settings = settings

        M3Form(title: "AI translation") {
            M3Section {
                if status.isSignedIn(.openRouter) {
                    HStack {
                        Label("API key saved", systemImage: "checkmark.seal")
                            .foregroundStyle(m3.onSurface)
                        Spacer()
                        Button("Remove", role: .destructive) { status.signOut(.openRouter) }
                            .buttonStyle(.m3Tonal)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        SecureField("OpenRouter API key", text: $keyField)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        HStack {
                            Button("Paste") { keyField = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
                                .buttonStyle(.m3Tonal)
                            Button("Save") {
                                status.signedIn(.openRouter, secret: keyField.trimmingCharacters(in: .whitespacesAndNewlines), userName: "OpenRouter")
                                keyField = ""
                            }
                            .buttonStyle(.m3Filled)
                            .disabled(keyField.trimmingCharacters(in: .whitespaces).isEmpty)
                            Spacer()
                            Button("Get a key") {
                                if let url = URL(string: "https://openrouter.ai/keys") { openURL(url) }
                            }
                            .buttonStyle(.m3Tonal)
                        }
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            } header: {
                Text("OpenRouter")
            } footer: {
                Text("Your own OpenRouter key; it is stored in the Keychain only. The lyrics lines of a song are sent to the chosen model to translate them into German. Costs depend on the model on your OpenRouter account.")
            }

            M3Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model").font(.m3(.labelLarge)).foregroundStyle(m3.onSurfaceVariant)
                    TextField(AILyricsTranslator.defaultModel, text: $settings.openRouterModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Own prompt (optional)").font(.m3(.labelLarge)).foregroundStyle(m3.onSurfaceVariant)
                        .padding(.top, 6)
                    TextEditor(text: $settings.openRouterPrompt)
                        .frame(minHeight: 90)
                        .scrollContentBackground(.hidden)
                        .background(m3.surfaceContainerHighest, in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                HStack {
                    Button(testing ? String(localized: "Testing…") : String(localized: "Test")) { test() }
                        .buttonStyle(.m3Tonal)
                        .disabled(testing || !status.isSignedIn(.openRouter))
                    if let testResult {
                        Text(testResult).font(.m3(.bodySmall)).foregroundStyle(m3.onSurfaceVariant)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            } header: {
                Text("Model and prompt")
            } footer: {
                Text("The own prompt is appended to the default instructions (e.g. “keep slang”, “informal Du”).")
            }
        }
        .m3ScreenBackground()
    }

    /// Two placeholder lines through the configured model.
    private func test() {
        guard let key = LyricsAccountSecrets.shared.secret(.openRouter) else { return }
        testing = true
        testResult = nil
        Task {
            do {
                let result = try await AILyricsTranslator.translate(["good morning", "see you tomorrow"], model: settings.openRouterModel,
                                                                    customPrompt: settings.openRouterPrompt, apiKey: key)
                testResult = String(localized: "Works") + ": " + result.joined(separator: " / ")
            } catch {
                testResult = error.localizedDescription
            }
            testing = false
        }
    }
}
