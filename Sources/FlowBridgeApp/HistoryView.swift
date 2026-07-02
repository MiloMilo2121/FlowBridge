import FlowBridgeShared
import SwiftUI

/// The local dictation library: full-text search, pin, copy, share, delete.
/// Everything on disk, nothing anywhere else.
struct HistoryView: View {
    @EnvironmentObject private var coordinator: FlowBridgeCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [TranscriptHistoryStore.Entry] = []
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty ? "No dictations yet" : "No matches",
                        systemImage: "waveform",
                        description: Text(query.isEmpty ? "Everything you dictate lives here — on this device only." : "Try different words.")
                    )
                } else {
                    List {
                        ForEach(entries) { entry in
                            row(for: entry)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search your dictations")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await reload() }
            .onChange(of: query) { _, _ in
                Task { await reload() }
            }
        }
    }

    private func row(for entry: TranscriptHistoryStore.Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if entry.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(entry.record.createdAt, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.record.audioDuration.formatted(.number.precision(.fractionLength(0))) + "s")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(entry.record.text)
                .font(.body)
                .lineLimit(4)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                UIPasteboard.general.string = entry.record.text
            } label: {
                Label("Copy", systemImage: "doc.on.clipboard")
            }
            ShareLink(item: entry.record.text) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            if let raw = entry.record.rawText, raw != entry.record.text {
                Button {
                    UIPasteboard.general.string = raw
                } label: {
                    Label("Copy verbatim", systemImage: "text.quote")
                }
            }
            Button {
                Task {
                    try? await coordinator.history?.setPinned(!entry.isPinned, id: entry.id)
                    await reload()
                }
            } label: {
                Label(entry.isPinned ? "Unpin" : "Pin", systemImage: entry.isPinned ? "pin.slash" : "pin")
            }
            Button(role: .destructive) {
                Task {
                    try? await coordinator.history?.delete(id: entry.id)
                    await reload()
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func reload() async {
        guard let store = coordinator.history else { return }
        entries = query.isEmpty ? await store.all() : await store.search(query)
    }
}
