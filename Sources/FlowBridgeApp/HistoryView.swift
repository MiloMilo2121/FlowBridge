import FlowBridgeShared
import SwiftUI

/// The same immutable diary format used by FlowBridge for Mac.
struct HistoryView: View {
    @EnvironmentObject private var coordinator: FlowBridgeCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [VoceDiario] = []
    @State private var query = ""
    @State private var selected: VoceDiario?
    @State private var callText: String?
    @State private var pinned = Set<String>()

    private var visible: [VoceDiario] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = value.isEmpty ? entries : Diario.cerca(value, in: entries)
        return matches.sorted {
            let a = pinned.contains($0.id.uuidString), b = pinned.contains($1.id.uuidString)
            return a == b ? $0.quando > $1.quando : a
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visible.isEmpty {
                    VStack(spacing: 12) {
                        Text(coordinator.diaryStatus).font(.caption).foregroundStyle(.secondary)
                        ContentUnavailableView(query.isEmpty ? "Your diary is empty" : "No matches",
                                               systemImage: "waveform",
                                               description: Text(query.isEmpty
                                                    ? "Dictations, notes, and Mac call transcripts appear here after iCloud sync."
                                                    : "Try different words."))
                    }
                } else {
                    List {
                        Section {
                            ForEach(visible) { entry in row(entry) }
                        } header: {
                            Text(coordinator.diaryStatus)
                        }
                    }
                }
            }
            .navigationTitle("Diary")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search dictations and calls")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .task {
                pinned = Set(UserDefaults.standard.stringArray(forKey: "diaryPinnedIDs") ?? [])
                await reload()
            }
            .sheet(item: $selected) { entry in
                NavigationStack {
                    ScrollView {
                        Text(entry.tipo == .call ? (callText ?? "Transcript is syncing from the Mac.")
                             : (entry.testo ?? ""))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle(entry.titolo ?? entry.tipo.rawValue.capitalized)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button("Done") { selected = nil } }
                    }
                    .task(id: entry.id) { callText = await coordinator.diaryCallText(entry) }
                }
            }
        }
    }

    private func row(_ entry: VoceDiario) -> some View {
        Button {
            callText = nil
            selected = entry
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if pinned.contains(entry.id.uuidString) { Image(systemName: "pin.fill") }
                    Text(entry.tipo.rawValue.capitalized)
                    Spacer()
                    Text(entry.quando, format: .dateTime.day().month().hour().minute())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(entry.titolo ?? entry.testo ?? "")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
            }
        }
        .contextMenu {
            if let text = entry.testo {
                Button("Copy", systemImage: "doc.on.clipboard") { UIPasteboard.general.string = text }
                ShareLink(item: text) { Label("Share", systemImage: "square.and.arrow.up") }
            }
            if let raw = entry.testoGrezzo, raw != entry.testo {
                Button("Copy verbatim", systemImage: "text.quote") { UIPasteboard.general.string = raw }
            }
            Button(pinned.contains(entry.id.uuidString) ? "Unpin" : "Pin",
                   systemImage: pinned.contains(entry.id.uuidString) ? "pin.slash" : "pin") {
                if !pinned.insert(entry.id.uuidString).inserted { pinned.remove(entry.id.uuidString) }
                UserDefaults.standard.set(Array(pinned), forKey: "diaryPinnedIDs")
            }
            if entry.tipo != .call {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    Task {
                        try? await coordinator.deleteDiaryEntry(entry.id)
                        await reload()
                    }
                }
            }
        }
    }

    private func reload() async { entries = await coordinator.diaryEntries() }
}
