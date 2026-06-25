//
//  Extensions.swift
//  PeakBar
//
//  Small shared conveniences.
//

import Foundation

extension Comparable {
    /// Clamps a value to a closed range.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
