import FlowBridgeShared
import Network
import SwiftUI

/// Privacy as a dashboard, not a policy: the network guard's live counters,
/// the architecture badges, and a "prove it" card that invites Airplane
/// Mode. Observation only — this screen never makes a request.
struct PrivacyCockpitView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PrivacyCockpitContent()
                .navigationTitle("Privacy")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

struct PrivacyCockpitContent: View {
    @StateObject private var network = NetworkStatusModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowTheme.space16) {
                hero

                countersCard

                badges

                airplaneCard

                Text("Not a policy — an architecture. The app installs a guard that rejects every network request, the dictation engines run on the Neural Engine, and nothing you say ever has a route off this iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(FlowTheme.space20)
        }
    }

    private var hero: some View {
        HStack(spacing: FlowTheme.space12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 40))
                .foregroundStyle(FlowTheme.accentGradient)
            VStack(alignment: .leading, spacing: 2) {
                Text("Private by architecture")
                    .font(.title3.weight(.semibold))
                Text("Your voice never leaves this iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var countersCard: some View {
        // A slow periodic refresh keeps the blocked counter honest without
        // polling aggressively.
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            VStack(spacing: FlowTheme.space12) {
                LabeledContent {
                    Text("0 — always")
                        .font(FlowTheme.numeric(17))
                        .foregroundStyle(.green)
                } label: {
                    Label("Requests allowed", systemImage: "checkmark.seal")
                }
                Divider()
                LabeledContent {
                    Text("\(NetworkGuard.blockedRequestCount)")
                        .font(FlowTheme.numeric(17))
                        .contentTransition(.numericText())
                } label: {
                    Label("Blocked this session", systemImage: "hand.raised")
                }
            }
            .padding(FlowTheme.space16)
            .flowCard()
        }
    }

    private var badges: some View {
        Grid(horizontalSpacing: FlowTheme.space8, verticalSpacing: FlowTheme.space8) {
            GridRow {
                badge("iphone", "On-device only")
                badge("person.crop.circle.badge.xmark", "No account")
            }
            GridRow {
                badge("airplane", "Airplane Mode ready")
                badge("cpu", "Neural Engine")
            }
        }
    }

    private func badge(_ icon: String, _ text: String) -> some View {
        HStack(spacing: FlowTheme.space8) {
            Image(systemName: icon)
                .foregroundStyle(FlowTheme.accent)
            Text(text)
                .font(.footnote.weight(.medium))
            Spacer(minLength: 0)
        }
        .padding(FlowTheme.space12)
        .flowCard(radius: FlowTheme.radiusControl)
    }

    private var airplaneCard: some View {
        VStack(alignment: .leading, spacing: FlowTheme.space8) {
            Label("Prove it to yourself", systemImage: "airplane.circle.fill")
                .font(.headline)
            Text("Turn on Airplane Mode, then dictate something. Nothing changes — that's the point.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: FlowTheme.space8) {
                Circle()
                    .fill(network.isOffline ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(network.isOffline ? "You're offline — now dictate something." : "Currently online")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(network.isOffline ? .green : .secondary)
            }
            .padding(.top, FlowTheme.space4)
            .animation(FlowMotion.state, value: network.isOffline)
        }
        .padding(FlowTheme.space16)
        .flowCard()
    }
}

/// Observes connectivity for the "try it in Airplane Mode" pill. Watching
/// the path makes no requests — consistent with the guard.
@MainActor
final class NetworkStatusModel: ObservableObject {
    @Published private(set) var isOffline = false

    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            Task { @MainActor in
                self?.isOffline = offline
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.marcomilanello.flowbridge.network-status"))
    }

    deinit {
        monitor.cancel()
    }
}
