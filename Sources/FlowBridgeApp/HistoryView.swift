import FlowBridgeShared
import SwiftUI

/// The local dictation library: full-text search with token filters, pinned
/// section, swipe actions. Everything on disk, nothing anywhere else.
struct HistoryView: View {
    @EnvironmentObject private var coordinator: FlowBridgeCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [TranscriptHistoryStore.Entry] = []
    @State private var query = ""
    @State private var tokens: [HistoryToken] = []
    @State private var suggestedTokens = HistoryToken.allCases

    enum HistoryToken: String, Identifiable, CaseIterable {
        case pinned = "Pinned"
        case today = "Today"
        case week = "This week"
        case recovered = "Recovered"
        case polished = "Polished"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .pinned: return "pin"
            case .today: return "sun.max"
            case .week: return "calendar"
            case .recovered: return "lifepreserver"
            case .polished: return "sparkles"
            }
        }

        func matches(_ entry: TranscriptHistoryStore.Entry) -> Bool {
            switch self {
            case .pinned:
                return entry.isPinned
            case .today:
                return Calendar.current.isDateInToday(entry.record.createdAt)
            case .week:
                return entry.record.createdAt > Date().addingTimeInterval(-7 * 86_400)
            case .recovered:
                return entry.record.source == .recovered
            case .polished:
                return entry.record.rawText != nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredEntries.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                tokens: $tokens,
                suggestedTokens: $suggestedTokens,
                prompt: Text("Search your dictations")
            ) { token in
                Label(token.rawValue, systemImage: token.icon)
            }
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

    // MARK: - List

    private var list: some View {
        List {
            if isBrowsing && !pinned.isEmpty {
                Section("Pinned") {
                    ForEach(pinned) { entry in
                        row(for: entry)
                    }
                }
            }
            Section(isBrowsing && !pinned.isEmpty ? "Recent" : "") {
                ForEach(isBrowsing ? recent : filteredEntries) { entry in
                    row(for: entry)
                }
            }
        }
        .animation(.snappy(duration: 0.3), value: entries.map(\.id))
    }

    /// Browsing (no query, no tokens) gets the pinned/recent split; a search
    /// gets one flat result list.
    private var isBrowsing: Bool {
        query.isEmpty && tokens.isEmpty
    }

    private var filteredEntries: [TranscriptHistoryStore.Entry] {
        entries.filter { entry in
            tokens.allSatisfy { $0.matches(entry) }
        }
    }

    private var pinned: [TranscriptHistoryStore.Entry] {
        filteredEntries.filter(\.isPinned)
    }

    private var recent: [TranscriptHistoryStore.Entry] {
        filteredEntries.filter { !$0.isPinned }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text(isBrowsing ? "No dictations yet" : "No matches")
            } icon: {
                Image(systemName: isBrowsing ? "waveform" : "waveform.badge.magnifyingglass")
                    .foregroundStyle(FlowTheme.accentGradient)
            }
        } description: {
            Text(isBrowsing
                ? "Your Action Button is getting bored. Everything you dictate lives here — on this device only."
                : "Try different words, or drop a filter.")
        }
    }

    // MARK: - Row

    private func row(for entry: TranscriptHistoryStore.Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: FlowTheme.space8) {
                if entry.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(FlowTheme.accent)
                }
                Text(entry.record.createdAt, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(wordCount(of: entry)) words")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, FlowTheme.space8)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule(style: .continuous))
                Text(entry.record.audioDuration.formatted(.number.precision(.fractionLength(0))) + "s")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(entry.record.text)
                .font(.body)
                .lineLimit(3)
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task {
                    try? await coordinator.history?.delete(id: entry.id)
                    await reload()
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                Task {
                    try? await coordinator.history?.setPinned(!entry.isPinned, id: entry.id)
                    await reload()
                }
            } label: {
                Label(entry.isPinned ? "Unpin" : "Pin", systemImage: entry.isPinned ? "pin.slash" : "pin")
            }
            .tint(FlowTheme.accent)

            Button {
                UIPasteboard.general.string = entry.record.text
            } label: {
                Label("Copy", systemImage: "doc.on.clipboard")
            }
            .tint(.secondary)
        }
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

    private func wordCount(of entry: TranscriptHistoryStore.Entry) -> Int {
        entry.record.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private func reload() async {
        guard let store = coordinator.history else { return }
        entries = query.isEmpty ? await store.all() : await store.search(query)
    }
}
