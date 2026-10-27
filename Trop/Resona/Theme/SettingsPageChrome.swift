//
//  SettingsPageChrome.swift
//  Resona
//
//  One header for every settings page (home and all subpages): round M3
//  back arrow top left, large page title flush with the left edge of the
//  list column, and a small title in the bar only after the large one has
//  scrolled away. The system back button is hidden; swipe-back keeps
//  working through the re-enabled interactive pop gesture below.
//

import SwiftUI
import UIKit

/// Large page title at the top of the centred settings column.
struct SettingsPageTitle: View {
    @Environment(\.m3) private var m3
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.m3(.headlineLarge))
            .foregroundStyle(m3.onSurface)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
    }
}

/// Applied to the page's ScrollView.
struct SettingsPageChrome: ViewModifier {
    @Environment(\.m3) private var m3
    let title: LocalizedStringKey
    var showsBackButton = true
    @State private var titleInBar = false

    func body(content: Content) -> some View {
        let base = content
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top > 44
            } action: { _, scrolled in
                withAnimation(M3Motion.quickFade) { titleInBar = scrolled }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.m3(.titleMedium, weight: .medium))
                        .foregroundStyle(m3.onSurface)
                        .opacity(titleInBar ? 1 : 0)
                }
            }
        if showsBackButton {
            base.m3BackButton()
        } else {
            base
        }
    }
}

extension View {
    func settingsPageChrome(_ title: LocalizedStringKey, showsBackButton: Bool = true) -> some View {
        modifier(SettingsPageChrome(title: title, showsBackButton: showsBackButton))
    }
}

/// Keeps the edge swipe-back working on pages whose system back button is
/// hidden (round M3 back buttons everywhere in the app).
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
