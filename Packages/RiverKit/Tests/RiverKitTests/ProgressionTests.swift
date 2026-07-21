import XCTest
@testable import RiverKit

/// Campaign completion, skill rating, achievements, leak detection and
/// recommendations (§23–34): pure functions over recorded play.
final class ProgressionTests: XCTestCase {

    func testCampaignLadderIsWellFormed() {
        XCTAssertEqual(CampaignLibrary.tiers.count, 7)
        for (index, tier) in CampaignLibrary.tiers.enumerated() {
            XCTAssertEqual(tier.id, index + 1, "tiers must be numbered 1...7 in order")
            XCTAssertFalse(tier.lineup.isEmpty)
            XCTAssertFalse(tier.bossLineup.isEmpty)
            XCTAssertGreaterThan(tier.handsRequired, 0)
            XCTAssertGreaterThan(tier.maxSevereMistakeRate, 0)
        }
    }

    func testCampaignTierCompletesOnVolumePlusQualityPlusBoss() {
        guard let tier = CampaignLibrary.tier(1) else { return XCTFail() }
        var progress = CampaignProgress()
        XCTAssertEqual(progress.highestUnlockedTier, 1)

        // Clean regular hands up to the requirement: not complete without boss.
        for _ in 0..<tier.handsRequired {
            progress.record(tier: 1, isBoss: false, decisions: 3, severe: 0)
        }
        XCTAssertFalse(progress.progress(for: 1).completed)

        // Boss hands close the tier.
        for _ in 0..<CampaignLibrary.bossHandsRequired {
            progress.record(tier: 1, isBoss: true, decisions: 3, severe: 0)
        }
        XCTAssertTrue(progress.progress(for: 1).completed)
        XCTAssertEqual(progress.highestUnlockedTier, 2)
    }

    func testCampaignTierRejectsSloppyPlayRegardlessOfVolume() {
        guard let tier = CampaignLibrary.tier(1) else { return XCTFail() }
        var progress = CampaignProgress()
        // Every decision severe: rate 100%, far above any tier's limit.
        for _ in 0..<(tier.handsRequired + CampaignLibrary.bossHandsRequired) {
            progress.record(tier: 1, isBoss: false, decisions: 2, severe: 2)
        }
        for _ in 0..<CampaignLibrary.bossHandsRequired {
            progress.record(tier: 1, isBoss: true, decisions: 2, severe: 2)
        }
        XCTAssertFalse(progress.progress(for: 1).completed,
                       "volume alone must never complete a tier")
        XCTAssertEqual(progress.highestUnlockedTier, 1)
    }

    func testRatingOnNoDataIsNeutralAndBounded() {
        let report = RatingEngine.compute(histories: [])
        XCTAssertEqual(report.samples, 0)
        XCTAssertGreaterThanOrEqual(report.overall, 800)
        XCTAssertLessThanOrEqual(report.overall, 1500)
        XCTAssertEqual(report.confidence, .low)
    }

    func testLeakDetectionStaysSilentWithoutSample() {
        XCTAssertTrue(LeakDetector.detect(histories: []).isEmpty,
                      "no data must produce no accusations")
    }

    func testLeakDefinitionsPointAtRealLessons() {
        for definition in LeakDetector.definitions {
            XCTAssertNotNil(Curriculum.lesson(id: definition.lessonID),
                            "leak \(definition.id) references unknown lesson \(definition.lessonID)")
        }
    }

    func testRecommendationForANewPlayerIsTheFirstLesson() {
        let recommendation = RecommendationEngine.recommend(
            histories: [], training: TrainingProgress(), now: Date(timeIntervalSince1970: 0)
        )
        guard let recommendation else { return XCTFail("new players must get a recommendation") }
        guard let lessonID = recommendation.lessonID, let lesson = Curriculum.lesson(id: lessonID) else {
            return XCTFail("recommendation must reference a real lesson")
        }
        XCTAssertTrue(TrainingProgress().isUnlocked(lesson), "recommended lesson must be playable now")
    }

    func testAchievementsAreValidAndStartLocked() {
        XCTAssertGreaterThanOrEqual(AchievementLibrary.all.count, 15)
        let ids = AchievementLibrary.all.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count, "achievement ids must be unique")

        let empty = AchievementEvidence(
            histories: [], training: TrainingProgress(), campaign: CampaignProgress(),
            tournamentsFinished: 0, tournamentWins: 0
        )
        let unlocked = AchievementLibrary.unlocked(evidence: empty)
        XCTAssertTrue(unlocked.isEmpty, "nothing should unlock before any play")
    }

    func testTournamentAchievementsRespondToEvidence() {
        let evidence = AchievementEvidence(
            histories: [], training: TrainingProgress(), campaign: CampaignProgress(),
            tournamentsFinished: 5, tournamentWins: 2
        )
        let unlocked = AchievementLibrary.unlocked(evidence: evidence)
        XCTAssertFalse(unlocked.isEmpty, "tournament results must unlock something")
        for id in unlocked {
            XCTAssertTrue(AchievementLibrary.all.contains { $0.id == id },
                          "unlocked id \(id) missing from library")
        }
    }

    func testICMTighteningReachesBotDecisions() {
        // The same marginal all-in call decision must not get LOOSER on the
        // bubble: the ICM-aware path may only fold more, never call more.
        // Verified indirectly through the risk premium the strategy consumes.
        let bubble = TournamentContext(
            playersRemaining: 3, payouts: [390, 210],
            stacks: [3000, 1500, 1500], onBubble: true, levelIndex: 5
        )
        let comfortable = TournamentContext(
            playersRemaining: 6, payouts: [390, 210],
            stacks: [1500, 1500, 1500, 1500, 1500, 1500], onBubble: false, levelIndex: 0
        )
        let bubblePremium = bubble.riskPremium(for: 1, amount: 1500)
        let earlyPremium = comfortable.riskPremium(for: 1, amount: 1500)
        XCTAssertGreaterThan(bubblePremium, earlyPremium,
                             "bubble risk must exceed early-game risk for the same stack share")
    }
}
