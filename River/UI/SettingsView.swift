import SwiftUI
import RiverKit

struct SettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var game: GameViewModel
    @State private var confirmingErase = false
    @State private var exportURL: URL?

    var body: some View {
        List {
            Section("Table pace") {
                Picker("Game speed", selection: $settingsStore.settings.speed) {
                    ForEach(GameSpeed.allCases) { speed in
                        Text(speed.displayName).tag(speed)
                    }
                }
            }

            Section("Assistance") {
                Picker("Style", selection: Binding(
                    get: { settingsStore.settings.assistanceLevel },
                    set: { settingsStore.settings.applyAssistancePreset($0) }
                )) {
                    ForEach(AssistanceLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Current hand strength", isOn: $settingsStore.settings.showHandStrength)
                Toggle("Pot odds when facing a bet", isOn: $settingsStore.settings.showPotOdds)
                Toggle("Advice on request", isOn: $settingsStore.settings.allowRecommendations)
                Toggle("Reveal bot cards after hand", isOn: $settingsStore.settings.revealFoldedBotCards)
            }

            Section("Feel") {
                Toggle("Sound", isOn: $settingsStore.settings.soundEnabled)
                Toggle("Haptics", isOn: $settingsStore.settings.hapticsEnabled)
                Toggle("Four-color deck", isOn: $settingsStore.settings.fourColorDeck)
                Toggle("Confirm all-ins", isOn: $settingsStore.settings.confirmAllIn)
                Toggle("Show deck seed after hands", isOn: $settingsStore.settings.showSeedAfterHand)
            }

            Section("Data") {
                Button("Export hand histories (JSON)") {
                    exportHistories()
                }
                if let url = exportURL {
                    ShareLink(item: url) {
                        Label("Share export", systemImage: "square.and.arrow.up")
                    }
                }
                Button("Erase all progress", role: .destructive) {
                    confirmingErase = true
                }
            }

            Section("About") {
                LabeledContent("Chips", value: "Fictional — never purchasable")
                LabeledContent("Data", value: "Stays on this device")
                LabeledContent("Fairness", value: "Seeded shuffle, no rigging")
                Text("The same deck seed and actions always reproduce the same hand. Cards are never altered for drama or progression.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Erase all progress?", isPresented: $confirmingErase, titleVisibility: .visible) {
            Button("Erase everything", role: .destructive) {
                eraseAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes the saved session, all hand histories and settings. This cannot be undone.")
        }
    }

    private func exportHistories() {
        let histories = game.store.loadHistories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(histories) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("river-hand-histories.json")
        do {
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            exportURL = nil
        }
    }

    private func eraseAll() {
        game.endSessionAndClear()
        game.store.delete(PersistenceStore.FileName.histories)
        game.store.delete(PersistenceStore.FileName.settings)
        settingsStore.settings = AppSettings()
        exportURL = nil
    }
}
