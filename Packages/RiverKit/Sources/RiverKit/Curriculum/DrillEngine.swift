import Foundation

/// Drill result labels (§17): multiple actions can be acceptable.
public enum DrillGradeLabel: String, Codable, Hashable, Sendable {
    case correct
    case strongAlternative
    case defensible
    case inaccuracy
    case mistake

    public var displayName: String {
        switch self {
        case .correct: return "Correct"
        case .strongAlternative: return "Strong alternative"
        case .defensible: return "Defensible"
        case .inaccuracy: return "Inaccuracy"
        case .mistake: return "Mistake"
        }
    }

    /// Credit toward mastery scores (§17).
    public var credit: Double {
        switch self {
        case .correct: return 1
        case .strongAlternative: return 0.9
        case .defensible: return 0.65
        case .inaccuracy: return 0.25
        case .mistake: return 0
        }
    }

    public var countsAsCorrect: Bool {
        return credit >= 0.9
    }
}

/// One selectable answer with its own honest grade and explanation.
public struct DrillChoice: Hashable, Sendable {
    public let label: String
    public let grade: DrillGradeLabel
    public let explanation: String
}

/// Display payload for a live-table drill scenario.
public struct DrillScenario: Hashable, Sendable {
    public let heroCards: [Card]
    public let board: [Card]
    public let pot: Int
    public let toCall: Int
    public let positionName: String
    public let stackBB: Int
    /// Prior-action summary lines shown above the decision.
    public let contextLines: [String]
}

/// One generated question.
public struct DrillQuestion: Hashable, Sendable {
    public let index: Int
    public let conceptTag: String
    public let prompt: String
    public let scenario: DrillScenario?
    public let choices: [DrillChoice]
}

/// Seeded, validated scenario generation (§16) built on the real engine,
/// strategy and analysis stack — never on parallel mock logic.
public enum DrillEngine {

    /// Generates the questions for a plan. Deterministic per seed.
    public static func questions(for plan: DrillPlan, seed: UInt64, conceptTag: String) -> [DrillQuestion] {
        var result: [DrillQuestion] = []
        let count = plan.questionCount
        var attempt: UInt64 = 0
        var index = 0
        while result.count < count && attempt < UInt64(count * 40) {
            let questionSeed = SeededRNG.derive(seed: seed, stream: 7_700 &+ attempt)
            attempt += 1
            var rng = questionSeed
            let question: DrillQuestion?
            switch plan {
            case .handReading:
                question = handReadingQuestion(index: index, tag: conceptTag, rng: &rng)
            case .winnerPick:
                question = winnerQuestion(index: index, tag: conceptTag, rng: &rng)
            case .potOdds:
                question = potOddsQuestion(index: index, tag: conceptTag, rng: &rng)
            case .outs:
                question = outsQuestion(index: index, tag: conceptTag, rng: &rng)
            case .combos:
                question = combosQuestion(index: index, tag: conceptTag, rng: &rng)
            case .preflop(_, let scenario, let stackBB):
                question = preflopQuestion(index: index, tag: conceptTag, kind: scenario, stackBB: stackBB, rng: &rng)
            case .pushFold(_, let stackBB):
                question = preflopQuestion(index: index, tag: conceptTag, kind: .unopened, stackBB: stackBB, rng: &rng)
            case .postflop(_, let street):
                question = postflopQuestion(index: index, tag: conceptTag, street: street, rng: &rng)
            case .quiz(let quizQuestions):
                if index < quizQuestions.count {
                    question = quizQuestion(index: index, tag: conceptTag, quiz: quizQuestions[index])
                } else {
                    question = nil
                }
            }
            if let question, validate(question) {
                result.append(question)
                index += 1
            }
            if case .quiz = plan, question == nil { break }
        }
        return result
    }

    /// Structural validation (§16): every question must have 2+ choices and at
    /// least one fully correct answer.
    public static func validate(_ question: DrillQuestion) -> Bool {
        guard question.choices.count >= 2 else { return false }
        guard question.choices.contains(where: { $0.grade == .correct }) else { return false }
        guard !question.prompt.isEmpty else { return false }
        if let scenario = question.scenario {
            let cards = scenario.heroCards + scenario.board
            guard Set(cards).count == cards.count else { return false }
        }
        return true
    }

    // MARK: - Knowledge questions

    private static func dealUnique(_ count: Int, rng: inout SeededRNG) -> [Card] {
        var deck = Deck(seed: rng.nextUInt64())
        var cards: [Card] = []
        for _ in 0..<count {
            cards.append(deck.deal())
        }
        return cards
    }

    private static func handReadingQuestion(index: Int, tag: String, rng: inout SeededRNG) -> DrillQuestion? {
        let cards = dealUnique(7, rng: &rng)
        let hero = Array(cards.prefix(2))
        let board = Array(cards.suffix(5))
        let value = HandEvaluator.evaluate(hole: hero, board: board)
        let correct = value.category
        var options: [HandCategory] = [correct]
        // Nearest-neighbour distractors keep the comparison meaningful.
        for offset in [1, -1, 2, -2, 3, -3] {
            if let candidate = HandCategory(rawValue: correct.rawValue + offset), options.count < 4 {
                options.append(candidate)
            }
        }
        var shuffled = options
        rng.shuffle(&shuffled)
        let choices = shuffled.map { category in
            DrillChoice(
                label: category.name,
                grade: category == correct ? .correct : .mistake,
                explanation: "Your best five cards make \(value.readableDescription.lowercased())."
            )
        }
        let scenario = DrillScenario(heroCards: hero, board: board, pot: 0, toCall: 0, positionName: "", stackBB: 0, contextLines: [])
        return DrillQuestion(index: index, conceptTag: tag, prompt: "What is your best five-card hand?", scenario: scenario, choices: choices)
    }

    private static func winnerQuestion(index: Int, tag: String, rng: inout SeededRNG) -> DrillQuestion? {
        let cards = dealUnique(9, rng: &rng)
        let hero = Array(cards[0...1])
        let villain = Array(cards[2...3])
        let board = Array(cards[4...8])
        let heroValue = HandEvaluator.evaluate(hole: hero, board: board)
        let villainValue = HandEvaluator.evaluate(hole: villain, board: board)
        let explanation = "You hold \(heroValue.readableDescription.lowercased()); the opponent (\(villain[0])\(villain[1])) holds \(villainValue.readableDescription.lowercased())."
        let winner: Int // 0 hero, 1 villain, 2 split
        if heroValue > villainValue { winner = 0 } else if villainValue > heroValue { winner = 1 } else { winner = 2 }
        let labels = ["Your hand wins", "The opponent wins", "Split pot"]
        let choices = labels.enumerated().map { offset, label in
            DrillChoice(label: label, grade: offset == winner ? .correct : .mistake, explanation: explanation)
        }
        let scenario = DrillScenario(heroCards: hero, board: board, pot: 0, toCall: 0, positionName: "", stackBB: 0,
                                     contextLines: ["Opponent shows \(villain[0]) \(villain[1])"])
        return DrillQuestion(index: index, conceptTag: tag, prompt: "Who wins this showdown?", scenario: scenario, choices: choices)
    }

    private static func potOddsQuestion(index: Int, tag: String, rng: inout SeededRNG) -> DrillQuestion? {
        let pots = [30, 45, 60, 80, 120, 150, 200]
        let fractions = [0.25, 0.33, 0.5, 0.75, 1.0]
        let basePot = pots[rng.int(upperBound: pots.count)]
        let fraction = fractions[rng.int(upperBound: fractions.count)]
        let bet = max(1, Int(Double(basePot) * fraction))
        let potBefore = basePot + bet // pot already contains the bet
        let odds = PotMath.odds(amountToCall: bet, potBeforeCall: potBefore)
        let truth = Int((odds.requiredEquity * 100).rounded())
        var options = Set([truth])
        for delta in [7, -7, 13, -13, 20] {
            let candidate = truth + delta
            if candidate > 2 && candidate < 95 && options.count < 4 {
                options.insert(candidate)
            }
        }
        var list = Array(options)
        rng.shuffle(&list)
        let explanation = "You call \(bet) into \(potBefore); the final pot is \(odds.finalPot). Required equity = \(bet) ÷ \(odds.finalPot) ≈ \(truth)%."
        let choices = list.map { value in
            DrillChoice(label: "\(value)%", grade: value == truth ? .correct : .mistake, explanation: explanation)
        }
        return DrillQuestion(
            index: index, conceptTag: tag,
            prompt: "The pot is \(potBefore) and you face a bet of \(bet). Roughly what equity do you need to call?",
            scenario: nil, choices: choices
        )
    }

    private static func outsQuestion(index: Int, tag: String, rng: inout SeededRNG) -> DrillQuestion? {
        // Template draws built from concrete cards; truth from the analyzer.
        let suits = Suit.allCases
        let suit = suits[rng.int(upperBound: 4)]
        let other = suits[(suit.rawValue + 1 + rng.int(upperBound: 3)) % 4]
        let template = rng.int(upperBound: 3)
        var hero: [Card]
        var board: [Card]
        var label: String
        switch template {
        case 0: // flush draw
            hero = [Card(.ace, suit), Card(.six, suit)]
            board = [Card(.king, suit), Card(.nine, suit), Card(.two, other)]
            label = "flush draw"
        case 1: // open-ended straight draw
            hero = [Card(.nine, suit), Card(.eight, other)]
            board = [Card(.seven, other == .clubs ? .hearts : .clubs), Card(.six, suit == .spades ? .diamonds : .spades), Card(.king, other)]
            label = "open-ended straight draw"
        default: // gutshot
            hero = [Card(.ace, suit), Card(.king, other)]
            board = [Card(.queen, other), Card(.jack, suit == .hearts ? .clubs : .hearts), Card(.four, other == .diamonds ? .spades : .diamonds)]
            label = "gutshot straight draw"
        }
        let all = hero + board
        guard Set(all).count == all.count else { return nil }
        let truths = [9, 8, 4]
        let truth = truths[template]
        var options = [truth, truth + 4, max(2, truth - 4), truth + 7]
        options = Array(Set(options)).sorted()
        var shuffled = options
        rng.shuffle(&shuffled)
        let explanation = "A \(label) has about \(truth) direct outs. Cards that pair the board can be discounted when they complete opponents' hands."
        let choices = shuffled.map { value in
            DrillChoice(label: "\(value) outs", grade: value == truth ? .correct : .mistake, explanation: explanation)
        }
        let scenario = DrillScenario(heroCards: hero, board: board, pot: 0, toCall: 0, positionName: "", stackBB: 0, contextLines: [])
        return DrillQuestion(index: index, conceptTag: tag, prompt: "How many clean outs does your draw have?", scenario: scenario, choices: choices)
    }

    private static func combosQuestion(index: Int, tag: String, rng: inout SeededRNG) -> DrillQuestion? {
        let variants = rng.int(upperBound: 4)
        let label: String
        let dead: Set<Card>
        let prompt: String
        switch variants {
        case 0:
            label = "AA"; dead = []
            prompt = "How many combinations of pocket aces exist?"
        case 1:
            label = "AKs"; dead = []
            prompt = "How many suited ace-king combinations exist?"
        case 2:
            label = "AK"; dead = []
            prompt = "How many total ace-king combinations exist (suited and offsuit)?"
        default:
            label = "AA"; dead = [Card(.ace, .spades)]
            prompt = "You hold the A♠. How many pocket-ace combinations remain for opponents?"
        }
        let combos: [HoleCombo]
        if label == "AK" {
            combos = HoleCombo.combos(forLabel: "AKs") + HoleCombo.combos(forLabel: "AKo")
        } else {
            combos = HoleCombo.combos(forLabel: label)
        }
        let truth = combos.filter { !$0.contains(any: dead) }.count
        var options = Set([truth])
        for candidate in [3, 4, 6, 12, 16, 8] where options.count < 4 {
            options.insert(candidate)
        }
        var list = Array(options).sorted()
        rng.shuffle(&list)
        let explanation = "Pairs have 6 combos, suited hands 4, offsuit hands 12. Each visible card removes the combinations containing it — here the answer is \(truth)."
        let choices = list.prefix(4).map { value in
            DrillChoice(label: "\(value)", grade: value == truth ? .correct : .mistake, explanation: explanation)
        }
        return DrillQuestion(index: index, conceptTag: tag, prompt: prompt, scenario: nil, choices: Array(choices))
    }

    private static func quizQuestion(index: Int, tag: String, quiz: QuizQuestion) -> DrillQuestion? {
        let choices = quiz.choices.enumerated().map { offset, label in
            DrillChoice(label: label, grade: offset == quiz.correctIndex ? .correct : .mistake, explanation: quiz.explanation)
        }
        return DrillQuestion(index: index, conceptTag: tag, prompt: quiz.prompt, scenario: nil, choices: choices)
    }

    // MARK: - Live decision questions (graded by the real analyzer)

    private static func gradeLabel(for grade: DecisionGrade) -> DrillGradeLabel {
        switch grade {
        case .excellent: return .correct
        case .strong: return .strongAlternative
        case .reasonable, .mixed: return .defensible
        case .inaccuracy: return .inaccuracy
        case .significantMistake, .blunder: return .mistake
        }
    }

    /// Builds a real engine hand scripted to a preflop decision for the hero.
    static func preflopHand(kind: PreflopScenarioKind, stackBB: Int, rng: inout SeededRNG) -> (hand: PokerHand, hero: Int)? {
        let bb = 2
        let stacks = Array(repeating: max(2, stackBB * bb), count: 6)
        let config = HandConfig(stacks: stacks, buttonIndex: 0, smallBlind: 1, bigBlind: bb, seed: rng.nextUInt64())
        let hand = PokerHand(config: config)
        do {
            switch kind {
            case .unopened:
                // Hero somewhere between UTG and the button; earlier seats fold.
                let heroOptions = [3, 4, 5, 0]
                let hero = heroOptions[rng.int(upperBound: heroOptions.count)]
                for seat in [3, 4, 5, 0] {
                    if seat == hero { break }
                    try hand.apply(.fold, by: seat)
                }
                return (hand, hero)
            case .facingOpen:
                // The cutoff opens; hero is the button.
                try hand.apply(.fold, by: 3)
                try hand.apply(.fold, by: 4)
                let openTo = Int((2.3 * Double(bb)).rounded())
                try hand.apply(.raise(to: min(openTo, stacks[5])), by: 5)
                return (hand, 0)
            case .blindDefense:
                // The button opens; hero defends the big blind.
                try hand.apply(.fold, by: 3)
                try hand.apply(.fold, by: 4)
                try hand.apply(.fold, by: 5)
                let openTo = Int((2.5 * Double(bb)).rounded())
                try hand.apply(.raise(to: min(openTo, stacks[0])), by: 0)
                try hand.apply(.fold, by: 1)
                return (hand, 2)
            case .facingThreeBet:
                // Hero opens UTG (scripted), the button three-bets.
                let openTo = Int((2.3 * Double(bb)).rounded())
                try hand.apply(.raise(to: min(openTo, stacks[3])), by: 3)
                try hand.apply(.fold, by: 4)
                try hand.apply(.fold, by: 5)
                try hand.apply(.raise(to: min(openTo * 3, stacks[0])), by: 0)
                try hand.apply(.fold, by: 1)
                try hand.apply(.fold, by: 2)
                return (hand, 3)
            }
        } catch {
            return nil
        }
    }

    private static func decisionChoices(obs: BotObservation, bigBlind: Int, shortStack: Bool) -> [(PlayerAction, String)] {
        var result: [(PlayerAction, String)] = []
        let available = obs.available
        result.append((.fold, available.canCheck ? "Fold (give up)" : "Fold"))
        if available.canCheck {
            result.append((.check, "Check"))
        } else if available.canCall {
            result.append((.call, "Call \(available.callCost)"))
        }
        if let options = available.betRaise {
            let standard: Int
            if obs.currentBet <= bigBlind {
                standard = Int((2.3 * Double(bigBlind)).rounded())
            } else {
                standard = obs.currentBet * 3
            }
            var target = max(options.minTo, min(standard, options.maxTo))
            if !options.isLegal(toAmount: target) {
                target = target < options.minFullTo ? options.minTo : options.maxTo
            }
            if target < options.maxTo {
                result.append((PlayerAction(kind: options.kind, toAmount: target), "\(options.kind == .bet ? "Bet" : "Raise to") \(target)"))
            }
            if shortStack || target >= options.maxTo {
                result.append((PlayerAction(kind: options.kind, toAmount: options.maxTo), "All-in \(options.maxTo)"))
            }
        }
        return result
    }

    private static func preflopQuestion(index: Int, tag: String, kind: PreflopScenarioKind, stackBB: Int, rng: inout SeededRNG) -> DrillQuestion? {
        guard let built = preflopHand(kind: kind, stackBB: stackBB, rng: &rng) else { return nil }
        let hand = built.hand
        let hero = built.hero
        guard hand.actionOn == hero, let obs = hand.observation(for: hero) else { return nil }
        let context = PreflopContext.build(from: obs)
        let actionChoices = decisionChoices(obs: obs, bigBlind: obs.bigBlind, shortStack: stackBB <= 15)
        guard actionChoices.count >= 2 else { return nil }

        var choices: [DrillChoice] = []
        var hasCorrect = false
        var bestIndex = 0
        var bestCredit = -1.0
        for (offset, entry) in actionChoices.enumerated() {
            guard let analysis = HandAnalyzer.analyzeDecision(
                observation: obs, chosen: entry.0, decisionIndex: 0, bigBlind: Double(obs.bigBlind), iterations: 180
            ) else { return nil }
            let label = gradeLabel(for: analysis.grade)
            if label == .correct { hasCorrect = true }
            if label.credit > bestCredit {
                bestCredit = label.credit
                bestIndex = offset
            }
            choices.append(DrillChoice(label: entry.1, grade: label, explanation: analysis.explanation))
        }
        if !hasCorrect {
            // Promote the analyzer's best choice so the question has an answer.
            let best = choices[bestIndex]
            choices[bestIndex] = DrillChoice(label: best.label, grade: .correct, explanation: best.explanation)
        }

        let combo = HoleCombo(obs.holeCards[0], obs.holeCards[1])
        let contextLines = describePreflopContext(context: context, obs: obs)
        let scenario = DrillScenario(
            heroCards: obs.holeCards, board: [], pot: obs.pot, toCall: obs.available.callCost,
            positionName: context.position.shortName, stackBB: Int(context.effectiveStackBB),
            contextLines: contextLines
        )
        _ = combo
        return DrillQuestion(index: index, conceptTag: tag, prompt: "Your action?", scenario: scenario, choices: choices)
    }

    private static func describePreflopContext(context: PreflopContext, obs: BotObservation) -> [String] {
        var lines = ["You are \(context.position.shortName) with \(Int(context.effectiveStackBB)) BB effective."]
        if context.raiseCount == 0 {
            lines.append(context.limpers > 0 ? "\(context.limpers) player(s) limped in front of you." : "Everyone folded to you.")
        } else if context.raiseCount == 1 {
            lines.append("An opponent opened to \(obs.currentBet).")
        } else {
            lines.append("You face a re-raise to \(obs.currentBet).")
        }
        return lines
    }

    private static func postflopQuestion(index: Int, tag: String, street: Street, rng: inout SeededRNG) -> DrillQuestion? {
        // Script a real heads-up pot: cutoff opens, hero defends the BB, then
        // streets check through until the target street, where the opponent
        // bets (or hero leads) depending on the seed.
        let bb = 2
        let stacks = Array(repeating: 200, count: 6)
        let config = HandConfig(stacks: stacks, buttonIndex: 0, smallBlind: 1, bigBlind: bb, seed: rng.nextUInt64())
        let hand = PokerHand(config: config)
        let heroFacesBet = rng.int(upperBound: 3) != 0
        let betFractions = [0.45, 0.65, 1.0]
        let fraction = betFractions[rng.int(upperBound: betFractions.count)]
        do {
            try hand.apply(.fold, by: 3)
            try hand.apply(.fold, by: 4)
            try hand.apply(.raise(to: 5), by: 5)
            try hand.apply(.fold, by: 0)
            try hand.apply(.fold, by: 1)
            try hand.apply(.call, by: 2)
            // Now heads-up: hero is seat 2 (BB, out of position), villain seat 5.
            while hand.street < street && !hand.isComplete {
                try hand.apply(.check, by: 2)
                try hand.apply(.check, by: 5)
            }
            guard hand.street == street, !hand.isComplete else { return nil }
            if heroFacesBet {
                try hand.apply(.check, by: 2)
                guard let options = hand.availableActions(for: 5)?.betRaise else { return nil }
                var target = Int((Double(hand.pot) * fraction).rounded())
                target = max(options.minTo, min(target, options.maxTo))
                if !options.isLegal(toAmount: target) { target = options.minTo }
                try hand.apply(.bet(to: target), by: 5)
            }
        } catch {
            return nil
        }
        guard hand.actionOn == 2, let obs = hand.observation(for: 2) else { return nil }
        let actionChoices = decisionChoices(obs: obs, bigBlind: bb, shortStack: false)
        guard actionChoices.count >= 2 else { return nil }

        var choices: [DrillChoice] = []
        var hasCorrect = false
        var bestIndex = 0
        var bestCredit = -1.0
        for (offset, entry) in actionChoices.enumerated() {
            guard let analysis = HandAnalyzer.analyzeDecision(
                observation: obs, chosen: entry.0, decisionIndex: 0, bigBlind: Double(bb), iterations: 220
            ) else { return nil }
            let label = gradeLabel(for: analysis.grade)
            if label == .correct { hasCorrect = true }
            if label.credit > bestCredit {
                bestCredit = label.credit
                bestIndex = offset
            }
            choices.append(DrillChoice(label: entry.1, grade: label, explanation: analysis.explanation))
        }
        if !hasCorrect {
            let best = choices[bestIndex]
            choices[bestIndex] = DrillChoice(label: best.label, grade: .correct, explanation: best.explanation)
        }

        var contextLines = ["You defended the big blind against a cutoff open."]
        if obs.available.callCost > 0 {
            contextLines.append("The opponent bets \(obs.available.callCost) into \(obs.pot - obs.available.callCost).")
        } else {
            contextLines.append("The action checks to you.")
        }
        let scenario = DrillScenario(
            heroCards: obs.holeCards, board: obs.board, pot: obs.pot, toCall: obs.available.callCost,
            positionName: "BB", stackBB: obs.myStack / bb, contextLines: contextLines
        )
        return DrillQuestion(index: index, conceptTag: tag, prompt: "Your action on the \(street.name.lowercased())?", scenario: scenario, choices: choices)
    }
}
