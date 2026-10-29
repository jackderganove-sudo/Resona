//
//  LyricsAccountsView.swift
//  Resona
//
//  Settings → Lyrics → Accounts: Deezer (web login reads the `arl` cookie,
//  or paste it) and Musixmatch (paste the desktop user token). Status
//  "Signed in as …" / "Not signed in" / "Please sign in again".
//

import SwiftUI
import WebKit

struct LyricsAccountsSection: View {
    @Environment(\.m3) private var m3
    @Environment(\.openURL) private var openURL
    private let status = LyricsAccountStatus.shared
    @State private var showDeezerLogin = false
    @State private var pasteTarget: LyricsAccount?

    var body: some View {
        M3Section {
            accountRow(.deezer, title: "Deezer", icon: "waveform.circle")
            accountRow(.musixmatch, title: "Musixmatch", icon: "music.mic")
        } header: {
            Text("Accounts")
        } footer: {
            Text("Free accounts improve these sources; without a login they are skipped. Credentials are stored in the Keychain only and never logged. The Deezer login cookie (ARL) gives full access to the Deezer account — sign out to remove it.")
        }
        .sheet(isPresented: $showDeezerLogin) {
            DeezerLoginSheet()
        }
        .sheet(item: $pasteTarget) { account in
            PasteCredentialSheet(account: account)
        }
    }

    private func accountRow(_ account: LyricsAccount, title: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(m3.primary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(m3.onSurface)
                    Text(statusText(account))
                        .font(.m3(.bodySmall))
                        .foregroundStyle(status.expired.contains(account) ? m3.error : m3.onSurfaceVariant)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                if status.isSignedIn(account) && !status.expired.contains(account) {
                    Button("Sign out", role: .destructive) { status.signOut(account) }
                        .buttonStyle(.m3Tonal)
                } else {
                    if account == .deezer {
                        Button("Sign in") { showDeezerLogin = true }
                            .buttonStyle(.m3Filled)
                    }
                    Button(account == .deezer ? LocalizedStringKey("Paste ARL") : LocalizedStringKey("Paste token")) { pasteTarget = account }
                        .buttonStyle(.m3Tonal)
                    Button("Create free account") {
                        let link = account == .deezer ? "https://www.deezer.com/register" : "https://www.musixmatch.com/"
                        if let url = URL(string: link) { openURL(url) }
                    }
                    .buttonStyle(.m3Tonal)
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func statusText(_ account: LyricsAccount) -> String {
        if status.expired.contains(account) { return String(localized: "Please sign in again") }
        guard status.isSignedIn(account) else { return String(localized: "Not signed in") }
        return String(format: String(localized: "Signed in as %@"), status.userNames[account] ?? "–")
    }
}

extension LyricsAccount: Identifiable {
    var id: String { rawValue }
}

// MARK: - Paste ARL / token

private struct PasteCredentialSheet: View {
    let account: LyricsAccount
    @Environment(\.dismiss) private var dismiss
    @Environment(\.m3) private var m3
    @State private var value = ""
    @State private var checking = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(account == .deezer ? LocalizedStringKey("ARL") : LocalizedStringKey("User token"), text: $value)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Paste from clipboard") { value = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
                } footer: {
                    Text(account == .deezer
                         ? LocalizedStringKey("On a computer: sign in on deezer.com, open the developer tools (F12) → Storage/Application → Cookies → www.deezer.com and copy the value of “arl”. It gives full access to your Deezer account — it is only stored in the Keychain.")
                         : LocalizedStringKey("On a computer: sign in on musixmatch.com, open the developer tools (F12) → Network, filter for “usertoken” and copy the value of a request with app_id=web-desktop-app-v1.0. It is only stored in the Keychain."))
                }
                if let error {
                    Section { Text(error).foregroundStyle(m3.error) }
                }
            }
            .navigationTitle(account == .deezer ? "Deezer" : "Musixmatch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(checking ? String(localized: "Checking…") : String(localized: "Save")) { save() }
                        .disabled(value.isEmpty || checking)
                }
            }
        }
    }

    private func save() {
        let secret = value.trimmingCharacters(in: .whitespacesAndNewlines)
        checking = true
        error = nil
        Task {
            let name = account == .deezer
                ? await DeezerSession.userName(arl: secret)
                : await MusixmatchAccount.userName(token: secret)
            checking = false
            if let name {
                LyricsAccountStatus.shared.signedIn(account, secret: secret, userName: name)
                dismiss()
            } else {
                error = String(localized: "This login was not accepted. Please check it and try again.")
            }
        }
    }
}

// MARK: - Deezer web login

private struct DeezerLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        NavigationStack {
            CookieLoginWebView(start: URL(string: "https://www.deezer.com/login")!, cookieName: "arl") { arl in
                guard let name = await DeezerSession.userName(arl: arl) else { return false }
                LyricsAccountStatus.shared.signedIn(.deezer, secret: arl, userName: name)
                dismiss()
                return true
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Deezer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}

/// Web view with a throw-away data store; polls its cookies until
/// `cookieName` appears and `accept` confirms it.
private struct CookieLoginWebView: UIViewRepresentable {
    let start: URL
    let cookieName: String
    let accept: @MainActor (String) async -> Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        webView.load(URLRequest(url: start))
        context.coordinator.poll(webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.task?.cancel()
    }

    func makeCoordinator() -> Coordinator { Coordinator(cookieName: cookieName, accept: accept) }

    @MainActor
    final class Coordinator {
        let cookieName: String
        let accept: @MainActor (String) async -> Bool
        var task: Task<Void, Never>?
        private var tried: Set<String> = []

        init(cookieName: String, accept: @escaping @MainActor (String) async -> Bool) {
            self.cookieName = cookieName
            self.accept = accept
        }

        func poll(_ webView: WKWebView) {
            task = Task { [weak self, weak webView] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(1500))
                    guard let self, let webView else { return }
                    let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                    guard let value = cookies.first(where: { $0.name == self.cookieName && !$0.value.isEmpty })?.value,
                          !self.tried.contains(value) else { continue }
                    self.tried.insert(value)
                    if await self.accept(value) { return }
                }
            }
        }
    }
}
