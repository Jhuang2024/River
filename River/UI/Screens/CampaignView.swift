import SwiftUI
import RiverKit

/// The Stakes Ladder (§23): seven tiers, each closed by a boss table.
/// Completion depends on decision quality over a required volume - luck can't
/// buy a tier and one bad river can't take it away.
struct CampaignView: View {
    @EnvironmentObject var game: GameViewModel
    @EnvironmentObject var settingsStore: SettingsStore

    private var accent: Color { settingsStore.accent }
    private var campaign: CampaignProgress {
        return game.store.load(CampaignProgress.self, from: "campaign") ?? CampaignProgress()
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Text("Advance by playing well, not by winning flips. Each tier needs solid decisions over real hands, then a boss table.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textSecondary)
                    ForEach(CampaignLibrary.tiers) { tier in
                        tierCard(tier)
                    }
                }
                .padding(Theme.Spacing.xl)
            }
            .readableColumn()
        }
        .navigationTitle("Stakes Ladder")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func tierCard(_ tier: CampaignTier) -> some View {
        let progress = campaign.progress(for: tier.id)
        let unlockedTier = campaign.highestUnlockedTier
        let state: TierState = progress.completed ? .completed : (tier.id == unlockedTier ? .active : (tier.id < unlockedTier ? .completed : .locked))

        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Image(systemName: state == .locked ? "lock.fill" : (state == .completed ? "checkmark.seal.fill" : "flag.fill"))
                    .foregroundStyle(state == .completed ? Theme.positive : (state == .active ? accent : Theme.textTertiary))
                Text("Tier \(tier.id) · \(tier.name)")
                    .font(Theme.Fonts.body.weight(.bold))
                    .foregroundStyle(state == .locked ? Theme.textTertiary : Theme.textPrimary)
                Spacer()
                Text(tier.difficulty.displayName)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(tier.purpose)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if state == .active {
                activeControls(tier, progress: progress)
            } else if state == .completed {
                Text("Completed · boss \(tier.bossName) defeated")
                    .font(Theme.Fonts.caption.weight(.semibold))
                    .foregroundStyle(Theme.positive)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .fill(Theme.backgroundElevated.opacity(state == .locked ? 0.5 : 1))
        )
    }

    @ViewBuilder
    private func activeControls(_ tier: CampaignTier, progress: TierProgress) -> some View {
        let handsFraction = min(1, Double(progress.handsPlayed) / Double(tier.handsRequired))
        let qualityOK = progress.severeMistakeRate <= tier.maxSevereMistakeRate || progress.analyzedDecisions < 20
        let volumeDone = progress.handsPlayed >= tier.handsRequired

        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                ProgressView(value: handsFraction)
                    .tint(qualityOK ? accent : Theme.caution)
                Text("\(progress.handsPlayed)/\(tier.handsRequired)")
                    .font(Theme.Fonts.telemetry)
                    .foregroundStyle(Theme.textSecondary)
            }
            if progress.analyzedDecisions >= 20 {
                Text(String(format: "Severe mistakes: %.1f%% (limit %.0f%%)", progress.severeMistakeRate, tier.maxSevereMistakeRate))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(qualityOK ? Theme.positive : Theme.caution)
            }
            if !qualityOK {
                Text("Too many severe mistakes: the rate falls as you play more clean hands. Review your graded hands to see what went wrong.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ActionButton(title: "Play \(tier.name)", role: .primary, accent: accent, identifier: "campaign.play") {
                startTable(tier, boss: false)
            }

            if volumeDone && qualityOK {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BOSS: \(tier.bossName.uppercased())").sectionHeader()
                    Text(tier.bossDescription)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if progress.bossHandsPlayed > 0 {
                        Text("Boss hands: \(progress.bossHandsPlayed)/\(CampaignLibrary.bossHandsRequired)")
                            .font(Theme.Fonts.caption)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ActionButton(title: "Face \(tier.bossName)", role: .destructive, accent: accent, identifier: "campaign.boss") {
                        startTable(tier, boss: true)
                    }
                }
                .padding(.top, 4)
            } else {
                Text("Boss table unlocks after \(tier.handsRequired) clean hands: \(tier.bossName): \(tier.bossDescription)")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func startTable(_ tier: CampaignTier, boss: Bool) {
        let config = SessionConfig(
            handsTarget: 0,
            seed: UITestSupport.seedOverride ?? UInt64.random(in: UInt64.min...UInt64.max),
            bots: boss ? tier.bossLineup : tier.lineup
        )
        game.startNewSession(config: config, campaign: CampaignTag(tier: tier.id, isBoss: boss))
    }

    private enum TierState {
        case locked
        case active
        case completed
    }
}
