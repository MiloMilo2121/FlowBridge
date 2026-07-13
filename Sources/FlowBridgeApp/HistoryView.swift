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
    @State private var renameTarget: TranscriptHistoryStore.Entry?

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
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .task { await reload() }
            .onChange(of: query) { _, _ in
                Task { await reload() }
            }
            .sheet(item: $renameTarget) { entry in
                RenameSpeakersSheet(entry: entry, history: coordinator.history) {
                    await reload()
                }
                .presentationDetents([.medium])
                .presentationBackground(.thinMaterial)
                .presentationCornerRadius(FlowTheme.radiusSheet)
            }
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            if isBrowsing && !pinned.isEmpty {
                Section {
                    ForEach(pinned) { entry in
                        row(for: entry)
                    }
                } header: {
                    Text("Pinned").flowEyebrow()
                }
            }
            Section {
                ForEach(isBrowsing ? recent : filteredEntries) { entry in
                    row(for: entry)
                }
            } header: {
                if isBrowsing && !pinned.isEmpty {
                    Text("Recent").flowEyebrow()
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(RoomBackground())
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
                .font(FlowTheme.serifFlavor(15))
        }
        .background(RoomBackground())
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
                    .font(FlowTheme.numeric(11, weight: .medium))
                    .padding(.horizontal, FlowTheme.space8)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule(style: .continuous))
                Text(entry.record.audioDuration.formatted(.number.precision(.fractionLength(0))) + "s")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(SpeakerLabelStyler.attributed(entry.record.text))
                .font(.body)
                .lineLimit(3)
        }
        .padding(FlowTheme.space16)
        .flowCard(radius: FlowTheme.radiusRow)
        .overlay {
            if entry.isPinned {
                RoundedRectangle(cornerRadius: FlowTheme.radiusRow, style: .continuous)
                    .strokeBorder(FlowTheme.accent.opacity(0.35), lineWidth: 1)
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
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
            if SpeakerTranscriptFormatter.labels(in: entry.record.text) != nil {
                Button {
                    renameTarget = entry
                } label: {
                    Label("Rename speakers…", systemImage: "person.2")
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

/// Give the anonymous "Speaker 1/2/…" labels real names — a plain text
/// replacement on this record only, nothing stored beyond it.
private struct RenameSpeakersSheet: View {
    let entry: TranscriptHistoryStore.Entry
    let history: TranscriptHistoryStore?
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var names: [String: String] = [:]

    private var labels: [String] {
        SpeakerTranscriptFormatter.labels(in: entry.record.text) ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(labels, id: \.self) { label in
                        TextField(label, text: binding(for: label))
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }
                    .listRowBackground(FlowTheme.surfaceRaised)
                } header: {
                    Text("Speakers").flowEyebrow()
                } footer: {
                    Text("Names replace the automatic labels in this transcript only. Leave a field empty to keep its label.")
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Rename speakers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.glassProminent)
                    .tint(FlowTheme.accent)
                    .disabled(cleanMapping.isEmpty)
                    .accessibilityLabel("Save names")
                }
            }
        }
    }

    private var cleanMapping: [String: String] {
        names
            .mapValues { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.value.isEmpty }
    }

    private func binding(for label: String) -> Binding<String> {
        Binding(
            get: { names[label] ?? "" },
            set: { names[label] = $0 }
        )
    }

    private func save() {
        let renamed = SpeakerTranscriptFormatter.renamed(entry.record.text, mapping: cleanMapping)
        Task {
            try? await history?.updateText(id: entry.id, text: renamed)
            await onSaved()
            dismiss()
        }
    }
}
