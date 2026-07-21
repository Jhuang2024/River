import SwiftUI
import RiverKit

/// Progress tab (§26): skill rating with honest confidence, per-street
/// breakdown, detected leaks, the Stakes Ladder, achievements and lifetime
/// statistics — all computed from real recorded hands.
struct ProgressHomeView: View {
    @EnvironmentObject var game: GameViewModel
    @EnvironmentObject var training: TrainingStore
    @EnvironmentObject var settingsStore: SettingsStore

    @State private var rating: RatingReport?
    @State private var leaks: [LeakReport] = []
    @State private var lifetime: SessionStats?
    @State private var unlockedAchievements: Set<String> = []
    @State private var computed = false

    private var accent: Color { settingsStore.accent }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        ratingCard
                        leaksCard
                        campaignCard
                        achievementsCard
                        lifetimeCard
                    }
                    .padding(Theme.Spacing.xl)
                }
            }
            .navigationTitle("Progress")
            .navigationDestination(for: Lesson.self) { lesson in
                LessonView(lesson: lesson)
            }
            .navigationDestination(for: String.self) { destination in
                if destination == "campaign" {
                    CampaignView()
                }
            }
        }
        .tint(accent)
        .task {
            await computeReports()
        }
        .onAppear {
            if computed {
                Task { await computeReports() }
            }
        }
    }

    private func computeReports() async {
        let histories = game.store.loadHistories()
        let trainingProgress = training.progress
        let campaign = game.store.load(CampaignProgress.self, from: "campaign") ?? CampaignProgress()
        let meta = game.store.load(PlayerMeta.self, from: "meta") ?? PlayerMeta()
        let result = await Task.detached(priority: .utility) { () -> (RatingReport, [LeakReport], SessionStats, Set<String>) in
            let rating = RatingEngine.compute(histories: histories)
            let leaks = LeakDetector.detect(histories: histories)
            let stats = SessionStats.compute(histories: histories, seat: heroSeatIndex)
            let evidence = AchievementEvidence(
                histories: histories,
                training: trainingProgress,
                campaign: campaign,
                tournamentsFinished: meta.tournamentsFinished,
                tournamentWins: meta.tournamentWins
            )
            let unlocked = AchievementLibrary.unlocked(evidence: evidence)
            return (rating, leaks, stats, unlocked)
        }.value
        rating = result.0
        leaks = result.1
        lifetime = result.2
        unlockedAchievements = result.3
        computed = true
    }

    // MARK: - Skill rating (§27)

    private var ratingCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("SKILL RATING").sectionHeader()
            if let rating {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                    Text("\(rating.overall)")
                        .font(Theme.Fonts.display)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(confidenceLabel(rating.confidence))
                            .font(Theme.Fonts.caption.weight(.bold))
                            .foregroundStyle(confidenceColor(rating.confidence))
                        if rating.recentTrend != 0 {
                            Label(rating.recentTrend > 0 ? "+\(rating.recentTrend) recently" : "\(rating.recentTrend) recently",
                                  systemImage: rating.recentTrend > 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(rating.recentTrend > 0 ? Theme.positive : Theme.danger)
                        }
                    }
                    Spacer()
                }
                Text(rating.changeSummary)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                streetBars(rating)
            } else {
                Text("Play analyzed hands to build a rating.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
    }

    private func streetBars(_ rating: RatingReport) -> some View {
        let streets: [Street] = [.preflop, .flop, .turn, .river]
        return VStack(spacing: 6) {
            ForEach(streets, id: \.self) { street in
                if let entry = rating.byStreet[street] {
                    HStack(spacing: Theme.Spacing.m) {
                        Text(street.name)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 52, alignment: .leading)
                        ProgressView(value: Double(entry.rating - 800) / 700.0)
                            .tint(accent)
                        Text("\(entry.rating)")
                            .font(Theme.Fonts.telemetry)
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func confidenceLabel(_ confidence: AnalysisConfidence) -> String {
        switch confidence {
        case .high: return "High confidence"
        case .moderate: return "Moderate confidence"
        case .low: return "Low confidence — small sample"
        }
    }

    private func confidenceColor(_ confidence: AnalysisConfidence) -> Color {
        switch confidence {
        case .high: return Theme.positive
        case .moderate: return Theme.caution
        case .low: return Theme.textTertiary
        }
    }

    // MARK: - Leaks (§30)

    private var leaksCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("LEAKS").sectionHeader()
            if leaks.isEmpty {
                Text(computed
                     ? "No statistically supported leaks right now. Keep playing — detection needs volume."
                     : "Analyzing your hands…")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(leaks.prefix(4)) { leak in
                    leakRow(leak)
                }
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
    }

    private func leakRow(_ leak: LeakReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(leak.severity > 0.66 ? Theme.danger : (leak.severity > 0.33 ? Theme.caution : Theme.info))
                    .frame(width: 8, height: 8)
                Text(leak.definition.title)
                    .font(Theme.Fonts.secondaryAction)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            Text(leak.summary)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let lesson = Curriculum.lesson(id: leak.definition.lessonID) {
                NavigationLink(value: lesson) {
                    Text("Fix it: \(lesson.title)")
                        .font(Theme.Fonts.caption.weight(.semibold))
                        .foregroundStyle(accent)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Campaign summary (§23)

    private var campaignCard: some View {
        let campaign = game.store.load(CampaignProgress.self, from: "campaign") ?? CampaignProgress()
        let unlockedTier = campaign.highestUnlockedTier
        let tier = CampaignLibrary.tier(unlockedTier)
        return NavigationLink(value: "campaign") {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    Text("STAKES LADDER").sectionHeader()
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(tier.map { "Tier \($0.id): \($0.name)" } ?? "Campaign complete")
                    .font(Theme.Fonts.body.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                if let tier {
                    let progress = campaign.progress(for: tier.id)
                    ProgressView(value: min(1, Double(progress.handsPlayed) / Double(tier.handsRequired)))
                        .tint(accent)
                    Text("\(progress.handsPlayed)/\(tier.handsRequired) hands · boss: \(tier.bossName)")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Achievements (§29)

    private var achievementsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Text("ACHIEVEMENTS").sectionHeader()
                Spacer()
                Text("\(unlockedAchievements.count)/\(AchievementLibrary.all.count)")
                    .font(Theme.Fonts.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.s) {
                ForEach(AchievementLibrary.all) { achievement in
                    achievementCell(achievement, unlocked: unlockedAchievements.contains(achievement.id))
                }
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
    }

    private func achievementCell(_ achievement: AchievementDefinition, unlocked: Bool) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: unlocked ? achievement.symbolName : "lock.fill")
                .font(.system(size: 14))
                .foregroundStyle(unlocked ? accent : Theme.textTertiary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(achievement.title)
                    .font(Theme.Fonts.caption.weight(.semibold))
                    .foregroundStyle(unlocked ? Theme.textPrimary : Theme.textTertiary)
                    .lineLimit(1)
                Text(achievement.detail)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.chip).fill(Theme.surface.opacity(unlocked ? 1 : 0.5)))
    }

    // MARK: - Lifetime stats (§28)

    @ViewBuilder
    private var lifetimeCard: some View {
        if let lifetime, lifetime.handsPlayed > 0 {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("LIFETIME").sectionHeader()
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.m) {
                    statCell("Hands", "\(lifetime.handsPlayed)")
                    statCell("Net chips", lifetime.netChips >= 0 ? "+\(lifetime.netChips)" : "\(lifetime.netChips)")
                    statCell("VPIP", String(format: "%.0f%%", lifetime.vpipPercent))
                    statCell("PFR", String(format: "%.0f%%", lifetime.pfrPercent))
                    statCell("Showdowns won", "\(lifetime.showdownsWon)/\(lifetime.showdownsSeen)")
                    statCell("Biggest pot", "\(lifetime.biggestPotWon)")
                }
                Text("Stored hands: \(game.store.loadHistories().count) · retention is configurable in Profile.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
        }
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.Fonts.potValue)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
