//
//  StatToggleBlock.swift
//  PeakBar
//
//  A single stat block: name, live value, and a checkbox in the top-right.
//  Selected blocks get an accent-colored border. The whole block is tappable.
//

import SwiftUI

struct StatToggleBlock: View {
    let stat: StatType
    let value: String
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                Text(stat.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundColor(.primary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.gray.opacity(0.25),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
