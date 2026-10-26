//
//  ResonaAppearance.swift
//  Resona
//
//  UIKit appearance proxies so system-drawn chrome (navigation titles,
//  segmented controls, alerts' tint) uses Poppins like the rest of the UI.
//

import UIKit

enum ResonaAppearance {
    static func configure() {
        let title = UIFont(name: "Poppins-Medium", size: 18) ?? .systemFont(ofSize: 18, weight: .medium)
        let large = UIFont(name: "Poppins-Regular", size: 34) ?? .systemFont(ofSize: 34)

        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.titleTextAttributes = [.font: title]
        nav.largeTitleTextAttributes = [.font: large]
        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        scrolled.titleTextAttributes = [.font: title]
        scrolled.largeTitleTextAttributes = [.font: large]

        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().compactAppearance = scrolled
        UINavigationBar.appearance().scrollEdgeAppearance = nav

        let segment = UIFont(name: "Poppins-Medium", size: 13) ?? .systemFont(ofSize: 13, weight: .medium)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: segment], for: .normal)
    }
}
