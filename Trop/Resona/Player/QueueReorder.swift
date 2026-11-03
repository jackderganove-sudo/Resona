//
//  QueueReorder.swift
//  Resona
//
//  Round 11: the queue's own drag-to-reorder (replaces List.onMove, whose
//  system lift photographed the transparent row on a dark, square platter
//  wider than the side panel). Pure maths here; the view lifts an opaque,
//  rounded copy of the row and the other rows slide by one row to open the
//  gap at the target.
//

import CoreGraphics

enum QueueReorder {
    /// Index the dragged row lands on for a vertical `translation`.
    static func target(from: Int, translation: CGFloat, pitch: CGFloat, count: Int) -> Int {
        guard count > 0, pitch > 0 else { return from }
        let steps = Int((translation / pitch).rounded())
        return min(max(from + steps, 0), count - 1)
    }

    /// How far row `index` moves aside while row `from` hovers over `to`.
    static func shift(index: Int, from: Int, to: Int, pitch: CGFloat) -> CGFloat {
        if index == from { return 0 }
        if from < to, index > from, index <= to { return -pitch }
        if to < from, index >= to, index < from { return pitch }
        return 0
    }

    /// `move(fromOffsets:toOffset:)` destination for dropping `from` on `to`.
    static func moveDestination(from: Int, to: Int) -> Int {
        to > from ? to + 1 : to
    }
}
