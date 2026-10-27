//
//  M3Styles.swift
//  Resona
//
//  Colour roles as ShapeStyles that resolve from the environment's dynamic
//  scheme (`\.m3`). Lets any view — including Trop's original screens — use
//  the cover theme (`.foregroundStyle(.m3OnSurfaceVariant)`,
//  `.fill(.m3SurfaceContainerLow)`) without threading the scheme through,
//  instead of fixed system colours (.secondary, systemGray, accentColor).
//

import SwiftUI

struct M3RoleStyle: ShapeStyle {
    let role: KeyPath<M3Scheme, Color>

    func resolve(in environment: EnvironmentValues) -> Color {
        environment.m3[keyPath: role]
    }
}

extension ShapeStyle where Self == M3RoleStyle {
    static var m3Primary: M3RoleStyle { M3RoleStyle(role: \.primary) }
    static var m3OnPrimary: M3RoleStyle { M3RoleStyle(role: \.onPrimary) }
    static var m3PrimaryContainer: M3RoleStyle { M3RoleStyle(role: \.primaryContainer) }
    static var m3OnPrimaryContainer: M3RoleStyle { M3RoleStyle(role: \.onPrimaryContainer) }
    static var m3SecondaryContainer: M3RoleStyle { M3RoleStyle(role: \.secondaryContainer) }
    static var m3OnSecondaryContainer: M3RoleStyle { M3RoleStyle(role: \.onSecondaryContainer) }
    static var m3Surface: M3RoleStyle { M3RoleStyle(role: \.surface) }
    static var m3SurfaceContainerLow: M3RoleStyle { M3RoleStyle(role: \.surfaceContainerLow) }
    static var m3SurfaceContainer: M3RoleStyle { M3RoleStyle(role: \.surfaceContainer) }
    static var m3SurfaceContainerHigh: M3RoleStyle { M3RoleStyle(role: \.surfaceContainerHigh) }
    static var m3SurfaceContainerHighest: M3RoleStyle { M3RoleStyle(role: \.surfaceContainerHighest) }
    static var m3OnSurface: M3RoleStyle { M3RoleStyle(role: \.onSurface) }
    static var m3OnSurfaceVariant: M3RoleStyle { M3RoleStyle(role: \.onSurfaceVariant) }
    static var m3Outline: M3RoleStyle { M3RoleStyle(role: \.outline) }
    static var m3OutlineVariant: M3RoleStyle { M3RoleStyle(role: \.outlineVariant) }
    static var m3Error: M3RoleStyle { M3RoleStyle(role: \.error) }
}

extension Color {
    /// Current dynamic primary (dark scheme) where a plain `Color` value is
    /// required (parameters, UIKit bridges). Prefer `.m3Primary` in views.
    static var m3Primary: Color {
        MainActor.assumeIsolated { ThemeStore.shared.dark.primary }
    }
}
