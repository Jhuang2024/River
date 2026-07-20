import SwiftUI
import RiverKit

/// Profile tab (§1): customization, assistance, pacing, accessibility-related
/// options, audio/haptics, data management.
struct ProfileView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var game: GameViewModel
    @State private var confirmingErase = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            List {
                Section("Appearance") {
                    Picker("Accent colour", selection: $settingsStore.settings.accent) {
                        ForEach(AccentChoice.allCases) { choice in
                            HStack {
                                Circle().fill(choice.color).frame(width: 12, height: 12)
                                Text(choice.displayName)
                            }
                            .tag(choice)
                        }
                    }
                    Picker("Deck style", selection: $settingsStore.settings.deckStyle) {
                        ForEach(DeckStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                }

                Section("Table pace") {
                    Picker("Game speed", selection: $settingsStore.settings.speed) {
                        ForEach(GameSpeed.allCases) { speed in
                            Text(speed.displayName).tag(speed)
                        }
                    }
                    Picker("Next hand", selection: $settingsStore.settings.autoDeal) {
                        ForEach(AutoDealSetting.allCases) { setting in
                            Text(setting.displayName).tag(setting)
                        }
                    }
                    Picker("Decision timer", selection: $settingsStore.settings.decisionTimer) {
                        ForEach(DecisionTimerSetting.allCases) { setting in
                            Text(setting.displayName).tag(setting)
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
                    Toggle("Required equity", isOn: $settingsStore.settings.showRequiredEquity)
                    Toggle("Board texture labels", isOn: $settingsStore.settings.showBoardTexture)
                    Toggle("Hints on request", isOn: $settingsStore.settings.allowRecommendations)
                    Toggle("Reveal bot cards after hand", isOn: $settingsStore.settings.revealFoldedBotCards)
                }

                Section("Safety & input") {
                    Toggle("Confirm all-ins", isOn: $settingsStore.settings.confirmAllIn)
                    Toggle("Protect strong hands", isOn: $settingsStore.settings.protectStrongHands)
                    Toggle("Swipe down to fold", isOn: $settingsStore.settings.swipeDownToFold)
                    Toggle("Left-handed layout", isOn: $settingsStore.settings.leftHandedMode)
                }

                Section("Sound & feel") {
                    Toggle("Sound", isOn: $settingsStore.settings.soundEnabled)
                    Toggle("Haptics", isOn: $settingsStore.settings.hapticsEnabled)
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
            .navigationTitle("Profile")
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
        .tint(settingsStore.accent)
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
        var fresh = AppSettings()
        fresh.hasCompletedOnboarding = true
        settingsStore.settings = fresh
        exportURL = nil
    }
}
