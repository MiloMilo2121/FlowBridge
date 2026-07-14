import SwiftUI

/// The "the UI understood you" moment: one suggested action under the
/// delivered transcript. Never more than one chip — a suggestion is a
/// confident offer, not a menu. Dismissable, and absent entirely for plain
/// dictations.
struct ContextActionBar: View {
    let suggestion: SuggestedAction?
    let confirmation: String?
    let transcript: String?
    let onPerform: () -> Void
    let onDismiss: () -> Void
    let onCopy: () -> Void

    var body: some View {
        if let confirmation {
            Label(confirmation, systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
                .transition(.opacity.combined(with: .offset(y: 6)))
                .accessibilityLabel(confirmation)
        } else if let suggestion {
            GlassEffectContainer(spacing: FlowTheme.space8) {
                HStack(spacing: FlowTheme.space8) {
                    Button(action: onPerform) {
                        HStack(spacing: FlowTheme.space8) {
                            Image(systemName: suggestion.symbol)
                                .font(.footnote.weight(.semibold))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(suggestion.activityTitle)
                                    .font(.caption.weight(.semibold))
                                if !suggestion.detail.isEmpty {
                                    Text(suggestion.detail)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.caption2.weight(.bold))
                        }
                        .padding(.horizontal, FlowTheme.space12)
                        .padding(.vertical, FlowTheme.space8)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(FlowTheme.accent)
                    .accessibilityLabel("\(suggestion.activityTitle): \(suggestion.detail)")

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.glass)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Dismiss suggestion")
                }
            }
            .transition(.opacity.combined(with: .offset(y: 6)))
        } else if let transcript, !transcript.isEmpty {
            GlassEffectContainer(spacing: FlowTheme.space8) {
                HStack(spacing: FlowTheme.space8) {
                    Button(action: onCopy) {
                        Label("Copy", systemImage: "doc.on.clipboard")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(FlowTheme.accent)

                    ShareLink(item: transcript) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                    }
                    .buttonStyle(.glass)
                }
            }
            .transition(.opacity.combined(with: .offset(y: 6)))
        }
    }
}
