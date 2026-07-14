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
    @State private var selectedEntry: TranscriptHistoryStore.Entry?

    private struct HistoryGroup: Identifiable {
        let id: String
        let title: String
        let entries: [TranscriptHistoryStore.Entry]
    }

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
            .sheet(item: $selectedEntry) { entry in
                HistoryDetailView(entry: entry)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.thinMaterial)
                    .presentationCornerRadius(FlowTheme.radiusSheet)
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            Section {
                historyHeader
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20))
            }

            if isBrowsing && !pinned.isEmpty {
                Section {
                    ForEach(pinned) { entry in
                        row(for: entry)
                    }
                } header: {
                    Text("Pinned").flowEyebrow()
                }
            }
            if isBrowsing {
                ForEach(historyGroups) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            row(for: entry)
                        }
                    } header: {
                        Text(group.title).flowEyebrow()
                    }
                }
            } else {
                Section {
                    ForEach(filteredEntries) { entry in
                        row(for: entry)
                    }
                } header: {
                    Text("Matches").flowEyebrow()
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

    private var historyGroups: [HistoryGroup] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfWeek = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfYesterday

        let candidates: [(String, String, (Date) -> Bool)] = [
            ("today", "Today", { $0 >= startOfToday }),
            ("yesterday", "Yesterday", { $0 >= startOfYesterday && $0 < startOfToday }),
            ("week", "Previous 7 days", { $0 >= startOfWeek && $0 < startOfYesterday }),
            ("earlier", "Earlier", { $0 < startOfWeek }),
        ]

        return candidates.compactMap { id, title, matches in
            let grouped = recent.filter { matches($0.record.createdAt) }
            return grouped.isEmpty ? nil : HistoryGroup(id: id, title: title, entries: grouped)
        }
    }

    private var historyHeader: some View {
        HStack(spacing: FlowTheme.space16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LOCAL VOICE TRAIL")
                    .font(FlowTheme.fieldLabel(10))
                    .tracking(1)
                    .foregroundStyle(FlowTheme.accent)
                Text("\(entries.count) dictations")
                    .font(.title3.weight(.semibold))
                Text("Search, reuse, or follow what each voice note became.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "waveform.path.ecg")
                .font(.title2.weight(.medium))
                .foregroundStyle(FlowTheme.accentGradient)
                .frame(width: 52, height: 52)
                .flowGlass()
        }
        .padding(FlowTheme.space16)
        .flowCard()
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
        Button {
            selectedEntry = entry
        } label: {
            HStack(alignment: .top, spacing: FlowTheme.space12) {
                VStack(spacing: 3) {
                    Circle()
                        .fill(entry.isPinned ? FlowTheme.accent : FlowTheme.accent.opacity(0.38))
                        .frame(width: entry.isPinned ? 10 : 8, height: entry.isPinned ? 10 : 8)
                    Rectangle()
                        .fill(FlowTheme.accent.opacity(0.12))
                        .frame(width: 1, height: 58)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: FlowTheme.space8) {
                        if entry.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(FlowTheme.accent)
                        }
                        Text(entry.record.createdAt, format: .dateTime.hour().minute())
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("\(wordCount(of: entry)) words")
                            .font(FlowTheme.numeric(10, weight: .medium))
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    Text(SpeakerLabelStyler.attributed(entry.record.text))
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    if let action = entry.record.actionTaken {
                        Label(action, systemImage: "arrow.turn.down.right")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(FlowTheme.accent)
                    }
                }
            }
            .padding(.vertical, FlowTheme.space8)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
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

private struct HistoryDetailView: View {
    let entry: TranscriptHistoryStore.Entry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FlowTheme.space20) {
                    HStack(spacing: FlowTheme.space12) {
                        Image(systemName: "waveform")
                            .foregroundStyle(FlowTheme.accentGradient)
                            .frame(width: 44, height: 44)
                            .flowGlass()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.record.createdAt, format: .dateTime.day().month().year().hour().minute())
                                .font(.subheadline.weight(.semibold))
                            Text("\(wordCount) words · \(Int(entry.record.audioDuration.rounded())) seconds")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(SpeakerLabelStyler.attributed(entry.record.text))
                        .font(FlowTheme.hero(22))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(FlowTheme.space20)
                        .flowCard()

                    if let action = entry.record.actionTaken {
                        Label(action, systemImage: "arrow.turn.down.right.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FlowTheme.accent)
                    }

                    HStack(spacing: FlowTheme.space12) {
                        Button {
                            UIPasteboard.general.string = entry.record.text
                        } label: {
                            Label("Copy", systemImage: "doc.on.clipboard")
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(FlowTheme.accent)

                        ShareLink(item: entry.record.text) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                        .buttonStyle(.glass)
                    }

                    if let raw = entry.record.rawText, raw != entry.record.text {
                        DisclosureGroup("Verbatim version") {
                            Text(raw)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .padding(.top, FlowTheme.space8)
                        }
                        .padding(FlowTheme.space16)
                        .flowCard(radius: FlowTheme.radiusRow)
                    }
                }
                .padding(FlowTheme.space20)
            }
            .background(RoomBackground())
            .navigationTitle("Dictation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var wordCount: Int {
        entry.record.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
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
