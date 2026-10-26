//
//  L10n.swift
//  Resona
//
//  Localized count labels ("1 song" / "91 songs") for places that build
//  text from numbers instead of using a LocalizedStringKey literal.
//

import Foundation

enum L10n {
    private static func count(_ n: Int, one: String, other: String) -> String {
        n == 1
            ? NSLocalizedString(one, comment: "")
            : String(format: NSLocalizedString(other, comment: ""), n)
    }

    static func songs(_ n: Int) -> String { count(n, one: "1 song", other: "%d songs") }
    static func episodes(_ n: Int) -> String { count(n, one: "1 episode", other: "%d episodes") }
    static func offlineTracks(_ n: Int) -> String { count(n, one: "1 offline track", other: "%d offline tracks") }
}
