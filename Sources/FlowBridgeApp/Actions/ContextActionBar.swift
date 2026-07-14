import SwiftUI

/// The "the UI understood you" moment: one suggested action under the
/// delivered transcript. Never more than one chip — a suggestion is a
/// confident offer, not a menu. Dismissable, and absent entirely for plain
/// dictations.
struct ContextActionBar: View {
    let suggestion: SuggestedAction?
    let confirmation: String?
    let onPerform: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        if let confirmation {
            Label(confirmation, systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
                .transition(.opacity.combined(with: .offset(y: 6)))
                .accessibilityLabel(confirmation)
        } else if let suggestion {
            HStack(spacing: FlowTheme.space8) {
                Button(action: onPerform) {
                    HStack(spacing: FlowTheme.space8) {
                        Image(systemName: suggestion.symbol)
                            .font(.footnote.weight(.semibold))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(suggestion.label)
                                .font(.caption.weight(.semibold))
                            if !suggestion.detail.isEmpty {
                                Text(suggestion.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.horizontal, FlowTheme.space12)
                    .padding(.vertical, FlowTheme.space8)
                }
                .buttonStyle(.glass)
                .tint(FlowTheme.accent)
                .accessibilityLabel("Create \(suggestion.label): \(suggestion.detail)")

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss suggestion")

                Spacer(minLength: 0)
            }
            .transition(.opacity.combined(with: .offset(y: 6)))
        }
    }
}
