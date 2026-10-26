//
//  AccountMenu.swift
//  Resona
//
//  Top app bar of the main tabs (brand + "•••" button) and the floating
//  account dropdown it opens (reference screenshot 10): avatar + account
//  name, then History and Settings. The dropdown is drawn by the root view so
//  it floats above every tab's content.
//

import SwiftUI

@MainActor
@Observable
final class AccountMenuState {
    static let shared = AccountMenuState()
    var isPresented = false
    /// Global frame of the button that opened the menu.
    var anchor: CGRect = .zero
    private init() {}
}

/// "♫ Resona                     (•••)" bar used at the top of the tabs.
struct ResonaTopBar: View {
    @Environment(\.m3) private var m3
    @Environment(\.usesNavigationRail) private var usesRail
    private let menu = AccountMenuState.shared

    var body: some View {
        HStack(spacing: 10) {
            // With the rail the brand mark already sits in the rail.
            if !usesRail {
                ResonaGlyph()
                    .frame(width: 34, height: 34)
            }
            Text(verbatim: "Resona")
                .font(.m3(.headlineSmall))
                .foregroundStyle(m3.onSurface)
            Spacer()
            GeometryReader { geo in
                Button {
                    menu.anchor = geo.frame(in: .global)
                    withAnimation(M3Motion.defaultSpatial) { menu.isPresented = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(m3.onSurface)
                        .frame(width: 44, height: 44)
                        .background(m3.surfaceContainerHigh, in: Circle())
                }
                .buttonStyle(.expressive(scale: 0.88))
                .accessibilityLabel(Text("Account"))
            }
            .frame(width: 44, height: 44)
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

/// The dropdown card plus a tap-to-dismiss scrim. Lives in ContentView.
struct AccountMenuOverlay: View {
    @Environment(\.m3) private var m3
    @Environment(\.artworkColors) private var artwork
    private let menu = AccountMenuState.shared
    private let account = AccountSheetState.shared

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { close() }

                card
                    .frame(width: min(300, geo.size.width - 32))
                    .offset(
                        x: max(16, min(menu.anchor.maxX - origin.x, geo.size.width - 16) - min(300, geo.size.width - 32)),
                        y: menu.anchor.maxY - origin.y + 8
                    )
                    .transition(.scale(scale: 0.6, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                open(.settings)
            } label: {
                HStack(spacing: 16) {
                    Group {
                        if account.isLoggedIn, let url = account.accountImageUrl {
                            AsyncImageView(url: url)
                        } else {
                            ZStack {
                                m3.primaryContainer
                                Image(systemName: "person.fill")
                                    .foregroundStyle(m3.onPrimaryContainer)
                            }
                        }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())

                    Text(account.isLoggedIn ? account.accountName : String(localized: "Sign in"))
                        .font(.m3(.titleMedium, weight: .regular))
                        .foregroundStyle(m3.onSurface)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(m3.onSurfaceVariant)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(m3.outlineVariant)
                .frame(height: 1)
                .padding(.horizontal, 16)

            item(icon: "clock.fill", title: "History") { open(.history) }
            item(icon: "arrow.down.circle.fill", title: "Downloads") { open(.downloads) }
            item(icon: "gearshape", title: "Settings") { open(.settings) }
                .padding(.bottom, 8)
        }
        .padding(.top, 4)
        .background {
            let shape = RoundedRectangle(cornerRadius: M3Shape.extraLarge, style: .continuous)
            ZStack {
                FrostedSurface(shape: shape, tint: m3.surfaceContainerHigh, role: .floating)
                // Faint wash of the current cover colour.
                shape.fill(artwork.accent.container.opacity(0.22))
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
    }

    private func item(icon: String, title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(m3.onSurface)
                    .frame(width: 28)
                Text(title)
                    .font(.m3(.titleMedium, weight: .regular))
                    .foregroundStyle(m3.onSurface)
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func open(_ route: DetailRoute) {
        close()
        AppRouter.shared.open(route)
    }

    private func close() {
        withAnimation(M3Motion.defaultSpatial) { menu.isPresented = false }
    }
}
