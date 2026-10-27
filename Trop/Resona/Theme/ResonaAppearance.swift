//
//  ResonaAppearance.swift
//  Resona
//
//  UIKit appearance for system-drawn chrome: navigation bars (title row,
//  back-arrow row) use Poppins and — instead of the default system bar
//  material, which looked bluish against the warm cover colours — the same
//  cover-scheme surface as the navigation rail (surfaceContainerLow) over
//  a blur. ThemeStore re-applies it on every colour change, including to
//  bars that already exist, with a short cross-fade.
//

import SwiftUI
import UIKit

enum ResonaAppearance {
    static func configure() {
        let segment = UIFont(name: "Poppins-Medium", size: 13) ?? .systemFont(ofSize: 13, weight: .medium)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: segment], for: .normal)
    }

    /// Bar appearances from the current dark/light schemes.
    @MainActor
    static func applyNavigationBars(dark: M3Scheme, light: M3Scheme, animated: Bool) {
        func dynamic(_ role: KeyPath<M3Scheme, Color>) -> UIColor {
            let d = UIColor(dark[keyPath: role]), l = UIColor(light[keyPath: role])
            return UIColor { $0.userInterfaceStyle == .light ? l : d }
        }
        let title = UIFont(name: "Poppins-Medium", size: 18) ?? .systemFont(ofSize: 18, weight: .medium)
        let large = UIFont(name: "Poppins-Regular", size: 34) ?? .systemFont(ofSize: 34)
        let text = dynamic(\.onSurface)
        let titles: [NSAttributedString.Key: Any] = [.font: title, .foregroundColor: text]
        let largeTitles: [NSAttributedString.Key: Any] = [.font: large, .foregroundColor: text]

        // Scrolled: rail surface over a blur (content shows through softly).
        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        scrolled.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        scrolled.backgroundColor = dynamic(\.surfaceContainerLow).withAlphaComponent(0.9)
        scrolled.shadowColor = .clear
        scrolled.titleTextAttributes = titles
        scrolled.largeTitleTextAttributes = largeTitles

        // At the top: transparent over the screen's own (cover-tinted) surface.
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        edge.titleTextAttributes = titles
        edge.largeTitleTextAttributes = largeTitles

        let proxy = UINavigationBar.appearance()
        proxy.standardAppearance = scrolled
        proxy.compactAppearance = scrolled
        proxy.scrollEdgeAppearance = edge
        proxy.compactScrollEdgeAppearance = edge

        // Bars that already exist don't pick up proxy changes.
        for scene in UIApplication.shared.connectedScenes {
            for window in (scene as? UIWindowScene)?.windows ?? [] {
                update(window, scrolled: scrolled, edge: edge, animated: animated)
            }
        }
    }

    @MainActor
    private static func update(_ view: UIView, scrolled: UINavigationBarAppearance, edge: UINavigationBarAppearance, animated: Bool) {
        if let bar = view as? UINavigationBar {
            let apply = {
                bar.standardAppearance = scrolled
                bar.compactAppearance = scrolled
                bar.scrollEdgeAppearance = edge
                bar.compactScrollEdgeAppearance = edge
            }
            if animated {
                UIView.transition(with: bar, duration: 0.4, options: [.transitionCrossDissolve, .allowUserInteraction], animations: apply)
            } else {
                apply()
            }
            return
        }
        for sub in view.subviews { update(sub, scrolled: scrolled, edge: edge, animated: animated) }
    }
}
