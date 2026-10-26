//
//  ResonaTab.swift
//  Resona
//
//  The three top-level destinations of the reference app. Raw values are the
//  tab indices AppRouter already uses for Trop's per-tab navigation paths.
//

import SwiftUI

enum ResonaTab: Int, CaseIterable, Identifiable {
    case home = 0
    case search = 3
    case library = 1

    var id: Int { rawValue }

    /// Order shown in the bar/rail.
    static let ordered: [ResonaTab] = [.home, .search, .library]

    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .search: "Search"
        case .library: "Library"
        }
    }

    var icon: String {
        switch self {
        case .home: "safari"
        case .search: "magnifyingglass"
        case .library: "square.grid.2x2"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home: "safari.fill"
        case .search: "magnifyingglass"
        case .library: "square.grid.2x2.fill"
        }
    }

    init(index: Int) {
        // Explore (2) lives inside the Search tab in Resona.
        self = ResonaTab(rawValue: index) ?? (index == 2 ? .search : .home)
    }
}
