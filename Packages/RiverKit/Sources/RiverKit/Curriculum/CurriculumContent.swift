import Foundation

/// All authored curriculum content (§4-§12). Text stays short by design: the
/// player should spend more time deciding than reading (§2). Live-decision
/// drills are generated and graded by the real engine and analyzer.
enum CurriculumContent {

    private static func lesson(
        _ id: String, _ academy: AcademyID, _ title: String, diff: Int,
        prereq: [String] = [], objectives: [String], intro: String,
        sections: [LessonSection] = [], drill: DrillPlan,
        threshold: Double = 0.8, tags: [String], minutes: Int = 5
    ) -> Lesson {
        return Lesson(
            id: id, academy: academy, title: title, difficulty: diff,
            prerequisites: prereq, objectives: objectives, intro: intro,
            sections: sections, drill: drill, masteryThreshold: threshold,
            conceptTags: tags, estimatedMinutes: minutes
        )
    }

    static let lessons: [Lesson] = foundations + preflop + flop + turn + river + math + exploit + tournament + advanced

    // MARK: - Academy 1: Poker Foundations (§4)

    private static let foundations: [Lesson] = [
        lesson("f.objective", .foundations, "How you win", diff: 1,
            objectives: ["Two ways to win a pot", "Chips as score"],
            intro: "Poker has exactly two ways to win a pot: show the best five-card hand at showdown, or make every other player fold before showdown. Chips are the score. You do not need to win many hands: you need to win chips. Folding a bad hand costs almost nothing; playing it badly costs a lot.",
            sections: [LessonSection("Two paths", "Strong hands want the pot big. Weak hands can still win by credible betting: that is a bluff. Both paths are normal poker, not tricks.")],
            drill: .quiz([
                QuizQuestion("You bet and every opponent folds. What happens?", ["You win the pot immediately", "You must show your cards to win", "The pot carries to the next hand"], correct: 0, why: "When all opponents fold, the last player wins the pot at once and never has to show their cards."),
                QuizQuestion("What is the long-term goal in poker?", ["Winning the most hands", "Winning the most chips", "Reaching showdown often"], correct: 1, why: "Chips are the score. Winning a few large pots beats winning many tiny ones."),
                QuizQuestion("A bluff is…", ["an illegal play", "betting so better hands fold", "checking a strong hand"], correct: 1, why: "A bluff wins the pot by folding out better hands: one of the two legitimate ways to win."),
                QuizQuestion("Folding costs you…", ["the pot plus your stack", "only what you already put in", "nothing, ever"], correct: 1, why: "When you fold you abandon only the chips you already committed. Your remaining stack is safe.")
            ]),
            tags: ["rules"], minutes: 3),

        lesson("f.cards", .foundations, "Cards and notation", diff: 1, prereq: ["f.objective"],
            objectives: ["Ranks and suits", "Shorthand like AKs"],
            intro: "A standard 52-card deck: thirteen ranks (2 through Ace) in four suits. You get two private hole cards; five community cards are shared. Shorthand: A♠K♠ names exact cards. AKs means ace-king suited (same suit); AKo means offsuit. Suits have no rank order: a spade flush ties a heart flush.",
            drill: .quiz([
                QuizQuestion("What does \"AJs\" mean?", ["Ace and jack of spades", "Ace and jack, same suit", "Ace and jack, different suits"], correct: 1, why: "The little s means suited: both cards share one suit. A specific suit would be written like A♠J♠."),
                QuizQuestion("How many hole cards do you get in Hold'em?", ["2", "4", "5"], correct: 0, why: "Two private hole cards, combined with up to five shared community cards."),
                QuizQuestion("Which suit is the strongest?", ["Spades", "Hearts", "No suit outranks another"], correct: 2, why: "Suits never break ties in Hold'em; equal hands split the pot."),
                QuizQuestion("How many combinations make an offsuit hand like AKo?", ["4", "6", "12"], correct: 2, why: "Four aces times four kings is 16 combos; 4 are suited, so 12 are offsuit.")
            ]),
            tags: ["rules", "notation"], minutes: 3),

        lesson("f.rankings", .foundations, "Hand rankings", diff: 1, prereq: ["f.cards"],
            objectives: ["All nine hand categories", "Reading your best five"],
            intro: "From weakest to strongest: high card, pair, two pair, three of a kind, straight, flush, full house, four of a kind, straight flush. Your hand is always the best five cards from your two plus the board. The ace plays high or low in straights: A-2-3-4-5 is the lowest straight.",
            sections: [LessonSection("Tricky cases", "Kickers break ties between equal pairs. If the board itself is the best five cards, everyone left splits. Watch counterfeits: your small two pair can die when the board pairs twice.")],
            drill: .handReading(count: 8),
            threshold: 0.75, tags: ["hand rankings"], minutes: 7),

        lesson("f.table", .foundations, "The table and blinds", diff: 1, prereq: ["f.objective"],
            objectives: ["Button, blinds, positions", "Why position rotates"],
            intro: "The dealer button moves one seat left every hand. The player left of the button posts the small blind; the next posts the big blind: forced bets that create something to fight for. Six-max positions: UTG, Hijack, Cutoff, Button, Small Blind, Big Blind. The button acts last after the flop: the best seat at the table.",
            drill: .quiz([
                QuizQuestion("Who posts the small blind?", ["The dealer button", "The seat left of the button", "The seat right of the button"], correct: 1, why: "The small blind sits directly left of the button; the big blind is next. Heads-up is the exception: the button posts the small blind."),
                QuizQuestion("Who acts first preflop at a full table?", ["The player left of the big blind", "The small blind", "The button"], correct: 0, why: "Preflop, action starts left of the big blind (under the gun). The blinds already have chips in and act last."),
                QuizQuestion("Why do blinds exist?", ["To punish tight players", "To create a pot worth fighting for", "To speed up dealing"], correct: 1, why: "Without forced bets, everyone could wait for aces. Blinds create dead money that drives action."),
                QuizQuestion("Which position acts last on every postflop street?", ["Big blind", "Cutoff", "Button"], correct: 2, why: "The button always acts last after the flop: more information, more control, more profit.")
            ]),
            tags: ["rules", "position"], minutes: 4),

        lesson("f.streets", .foundations, "The four streets", diff: 1, prereq: ["f.table"],
            objectives: ["Preflop → flop → turn → river", "Showdown"],
            intro: "Betting happens on four streets. Preflop: only your two hole cards. Flop: three community cards arrive. Turn: a fourth. River: the fifth and final card. If two or more players remain after river betting, hands are shown and the best five-card hand wins. Each street is a fresh betting round.",
            drill: .quiz([
                QuizQuestion("How many community cards arrive on the flop?", ["1", "2", "3"], correct: 2, why: "The flop is three cards at once; the turn and river add one each."),
                QuizQuestion("When does a showdown happen?", ["After every river", "When two or more players finish river betting", "Whenever someone goes all-in"], correct: 1, why: "A showdown only happens if at least two players are still in after the final betting round."),
                QuizQuestion("What changes about your information each street?", ["Nothing", "More shared cards are revealed", "Opponents must show one card"], correct: 1, why: "Each street reveals more board cards and more betting decisions: both are information."),
                QuizQuestion("The river is…", ["the first community card", "the last community card", "the highest card on the board"], correct: 1, why: "River = fifth and final community card. After it, no more cards are coming: only decisions.")
            ]),
            tags: ["rules"], minutes: 3),

        lesson("f.actions", .foundations, "Legal actions", diff: 1, prereq: ["f.streets"],
            objectives: ["Fold, check, call, bet, raise, all-in", "Minimum raise"],
            intro: "Facing no bet you may check (pass) or bet. Facing a bet you may fold, call (match it), or raise. A raise must increase the bet by at least the size of the last raise: blinds set the first minimum. Going all-in with less than a minimum raise is allowed, but it may not reopen the betting.",
            drill: .quiz([
                QuizQuestion("Nobody has bet this street. You may…", ["only call or fold", "check or bet", "only check"], correct: 1, why: "With no bet to face, checking is free and betting is your aggressive option. Folding here just donates your share of the pot."),
                QuizQuestion("Blinds 1/2. A player raises to 6. The next raise must be at least…", ["8", "10", "12"], correct: 1, why: "The raise increment was 4 (from 2 to 6), so the next full raise is 6 + 4 = 10."),
                QuizQuestion("Calling means…", ["matching the current bet", "betting more than the current bet", "declining to play"], correct: 0, why: "A call matches the highest current bet exactly. Raising goes beyond it."),
                QuizQuestion("A raise \"to 30\" over a bet of 10 costs a fresh player…", ["20", "30", "40"], correct: 1, why: "\"Raise to 30\" states the total for the street. A player with nothing in yet pays all 30."),
                QuizQuestion("An all-in smaller than the minimum raise…", ["is illegal", "is legal but may not reopen betting", "cancels the previous bet"], correct: 1, why: "You can always shove your stack, but a short all-in doesn't necessarily let earlier players raise again.")
            ]),
            tags: ["rules", "actions"], minutes: 5),

        lesson("f.pots", .foundations, "Pots, showdowns and splits", diff: 1, prereq: ["f.actions"],
            objectives: ["Winning without showdown", "Ties split the pot"],
            intro: "Every chip bet goes into the pot. If everyone folds to a bet, the bettor wins immediately: no cards shown. At showdown the best five-card hand takes the pot. Exactly equal hands split it; when the split is uneven, the odd chip goes to the first winner left of the button.",
            drill: .winnerPick(count: 6),
            threshold: 0.75, tags: ["rules", "hand rankings"], minutes: 6),

        lesson("f.allins", .foundations, "All-ins and side pots", diff: 2, prereq: ["f.pots"],
            objectives: ["Main pot vs side pot", "Who can win what"],
            intro: "You can never lose more than your own stack. If a shorter stack goes all-in and bigger stacks keep betting, the extra chips form a side pot the all-in player cannot win. Main pot: everyone matched the shortest all-in. Side pots: only the deeper stacks who covered them. Nobody ever wins chips they didn't match.",
            drill: .quiz([
                QuizQuestion("Player A is all-in for 30; B and C each put in 100. What can A win?", ["Everything", "Only the main pot of 90", "Nothing"], correct: 1, why: "A can win 30 from each player: the 90 main pot. B and C's extra 70 each forms a side pot only they contest."),
                QuizQuestion("Who is eligible for a side pot?", ["Everyone in the hand", "Only players who contributed to it", "Only the all-in player"], correct: 1, why: "A pot belongs to the players whose chips are in it. Short all-in stacks are excluded from side pots above their level."),
                QuizQuestion("You bet 200, your only opponent has 80 and calls all-in. What happens to your extra 120?", ["It stays in the pot", "It is returned to you", "The dealer keeps it"], correct: 1, why: "An uncalled excess can't be won by anyone: it comes straight back to you."),
                QuizQuestion("Three players all-in for 20, 50 and 100. How many pots can exist?", ["1", "2", "3"], correct: 2, why: "Main pot at the 20 level, a side pot for the 20→50 layer, and an uncalled refund or heads-up layer above 50: up to three layers.")
            ]),
            tags: ["rules", "side pots"], minutes: 5),

        lesson("f.firsthand", .foundations, "Play your first hands", diff: 1, prereq: ["f.allins"],
            objectives: ["Apply the rules in live decisions"],
            intro: "Time to make real decisions. You'll face genuine preflop spots against the engine: every choice you make is graded by the same analysis the full game uses. There is rarely one perfect answer; the goal is avoiding clear mistakes like playing hopeless cards or folding monsters.",
            drill: .preflop(count: 6, scenario: .unopened, stackBB: 100),
            threshold: 0.7, tags: ["rules", "preflop range"], minutes: 8),

        lesson("f.mastery", .foundations, "Foundations mastery", diff: 2, prereq: ["f.rankings", "f.firsthand"],
            objectives: ["Prove the rules are solid"],
            intro: "A mixed check of everything so far: rankings, winners, action legality, side pots. Pass this and the strategy academies open up. If you already know poker, passing this immediately is exactly how you test out of the basics.",
            drill: .quiz([
                QuizQuestion("Which hand is strongest?", ["Flush", "Straight", "Two pair"], correct: 0, why: "Flush beats straight beats two pair. The full order climbs: pair, two pair, trips, straight, flush, full house, quads, straight flush."),
                QuizQuestion("Board: A-A-K-K-Q. You hold 2-3. Your opponent holds 5-6. Who wins?", ["You", "Opponent", "Split"], correct: 2, why: "Both of you play the board: aces and kings with a queen. Equal hands split the pot."),
                QuizQuestion("A player who folded can…", ["still win the main pot", "win nothing this hand", "win only side pots"], correct: 1, why: "Folding surrenders every claim on the hand, no matter what cards arrive next."),
                QuizQuestion("Blinds 1/2, someone raises to 8. You want to re-raise. The minimum total is…", ["10", "14", "16"], correct: 1, why: "The raise increment was 6 (2→8), so a full re-raise is at least 8 + 6 = 14."),
                QuizQuestion("A-2-3-4-5 of mixed suits is…", ["a straight", "high card only", "an illegal hand"], correct: 0, why: "The wheel: the ace plays low to complete the lowest straight, five high."),
                QuizQuestion("Preflop, who acts last if everyone calls?", ["Button", "Small blind", "Big blind"], correct: 2, why: "The big blind closes preflop action and can check or raise: the \"option\".")
            ]),
            threshold: 0.85, tags: ["rules", "hand rankings", "side pots"], minutes: 6)
    ]

    // MARK: - Academy 2: Preflop Strategy (§5)

    private static let preflop: [Lesson] = [
        lesson("p.handvalue", .preflop, "Why starting hands differ", diff: 2, prereq: ["f.mastery"],
            objectives: ["High cards, pairs, suitedness, connectivity", "Domination"],
            intro: "Starting hands differ in three ways: high-card strength (AK makes better pairs than K9), pair potential (22 already is one), and drawing power (suited and connected cards make flushes and straights). Domination is the silent killer: K9 against KQ makes the same pair with a losing kicker. Pretty-looking dominated hands lose the most money.",
            drill: .quiz([
                QuizQuestion("Why is AKs better than AKo?", ["Higher pairs", "It can make the nut flush", "It never loses"], correct: 1, why: "Same pairs, same straights: plus about 2% extra equity and nut-flush potential from suitedness."),
                QuizQuestion("K9o against KQo is…", ["dominated", "a coinflip", "ahead"], correct: 0, why: "When a king flops, K9 makes the same pair with a dead kicker. That's domination: you win small, lose big."),
                QuizQuestion("Small suited connectors like 76s are valuable because…", ["they make big pairs", "they make straights and flushes", "they beat aces preflop"], correct: 1, why: "Their value is nut potential: straights and flushes that win big pots: not pair strength."),
                QuizQuestion("The single biggest factor in raw preflop strength is…", ["suitedness", "high cards and pairs", "position"], correct: 1, why: "Big cards and big pairs dominate raw equity. Suitedness and connectivity add a few percent each.")
            ]),
            tags: ["preflop range"], minutes: 4),

        lesson("p.position", .preflop, "Position is power", diff: 2, prereq: ["p.handvalue"],
            objectives: ["Why acting later is better", "Wider late ranges"],
            intro: "Acting after your opponents means deciding with more information, betting when they show weakness, and controlling the pot. That is why every serious range chart widens from UTG to button. The blinds put money in early but play every later street first: the worst of both worlds. Play tight early, wide late.",
            drill: .quiz([
                QuizQuestion("Why can the button play the most hands?", ["It posts no blind", "It acts last on every postflop street", "It sees the flop free"], correct: 1, why: "Acting last means every decision is made with maximum information: hands gain value from position alone."),
                QuizQuestion("The small blind is difficult because…", ["it acts last preflop", "it is out of position every later street", "its cards are weaker"], correct: 1, why: "The SB pays half a bet but then acts first forever. Discount is real; position penalty is bigger."),
                QuizQuestion("A hand like K9s is best played from…", ["UTG", "the button", "any seat equally"], correct: 1, why: "Marginal hands need position to be profitable. K9s is a fine button open and a poor early open."),
                QuizQuestion("\"In position\" means…", ["having the dealer button only", "acting after your opponent postflop", "being in the blinds"], correct: 1, why: "Whoever acts later in the betting is in position: the button always is, the blinds almost never are.")
            ]),
            tags: ["position"], minutes: 4),

        lesson("p.opening", .preflop, "Open or fold: stop limping", diff: 2, prereq: ["p.position"],
            objectives: ["Raise-first-in strategy", "Position-based opens"],
            intro: "When the pot is unopened, competent players raise or fold. Limping (just calling the blind) wins nothing immediately, invites the blinds in cheaply, and announces weakness. Open around 2.2-2.5 big blinds. Tight from UTG (~15% of hands), widening to over 40% on the button. These are live spots: decide.",
            drill: .preflop(count: 8, scenario: .unopened, stackBB: 100),
            threshold: 0.75, tags: ["preflop range", "position"], minutes: 8),

        lesson("p.facingopen", .preflop, "Facing an open", diff: 3, prereq: ["p.opening"],
            objectives: ["Fold / call / three-bet trees", "Domination discipline"],
            intro: "When someone opens in front of you, folding is usually right: their range is real and you must beat it plus everyone behind. Continue with hands that dominate their range (three-bet the best), and with hands that make nut draws. Cold-calling dominated offsuit hands like KJo against early opens burns money slowly.",
            drill: .preflop(count: 8, scenario: .facingOpen, stackBB: 100),
            threshold: 0.75, tags: ["preflop range", "3-bet"], minutes: 8),

        lesson("p.blinddef", .preflop, "Defending the big blind", diff: 3, prereq: ["p.facingopen"],
            objectives: ["Price-driven defence", "Not overfolding or overcalling"],
            intro: "You already have one big blind invested, so the price to defend is discounted: against a 2.5x open you often need barely a third of the pot's equity. That justifies defending suited, connected, and decent offsuit hands. But you'll play the whole hand out of position, so hopeless offsuit junk still folds. Balance: defend wide, not blind.",
            drill: .preflop(count: 8, scenario: .blindDefense, stackBB: 100),
            threshold: 0.75, tags: ["blind defence", "pot odds"], minutes: 8),

        lesson("p.threebets", .preflop, "Three-betting", diff: 3, prereq: ["p.facingopen"],
            objectives: ["Value vs bluff three-bets", "Sizing in and out of position"],
            intro: "Three-bet your strongest hands for value: building pots while ahead. Add some bluffs from hands with good blockers (like A5s: holding an ace makes their AA/AK less likely) that play fine when called. Size around 3x the open in position, 4x out of position. A range of only premiums is honest and easy to fold against; a few bluffs make you feared.",
            drill: .quiz([
                QuizQuestion("The core value three-bet hands are…", ["small pairs", "QQ+, AK", "suited connectors"], correct: 1, why: "Big pairs and AK crush opening ranges: build pots with them immediately."),
                QuizQuestion("Why is A5s a classic three-bet bluff?", ["It flops well only", "The ace blocks AA/AK and it makes nut draws", "It dominates most opens"], correct: 1, why: "Your ace removes combos of the hands that continue against you, and suited-ace playability covers the times you're called."),
                QuizQuestion("Out of position, three-bets should be…", ["smaller", "the same", "larger"], correct: 2, why: "Playing the hand out of position is harder: charge more, deny position value, end hands earlier."),
                QuizQuestion("Against a 3x open of 6 at blinds 1/2, an in-position three-bet is around…", ["10", "18", "36"], correct: 1, why: "About three times the open: enough to deny the price without bloating your risk.")
            ]),
            tags: ["3-bet", "blockers"], minutes: 5),

        lesson("p.facing3bet", .preflop, "Facing a three-bet", diff: 4, prereq: ["p.threebets"],
            objectives: ["Continue ranges", "Four-bet trees", "Set-mine limits"],
            intro: "Getting three-bet after you open is a range test. Four-bet your monsters, call with hands that play well in big pots and in position, fold the rest: including most dominated broadways. Small pairs want to set-mine, but only when stacks are deep enough to pay off: roughly fifteen times the call or more.",
            drill: .preflop(count: 7, scenario: .facingThreeBet, stackBB: 100),
            threshold: 0.72, tags: ["3-bet", "preflop range"], minutes: 8),

        lesson("p.stackdepth", .preflop, "Stack depth changes everything", diff: 4, prereq: ["p.facing3bet"],
            objectives: ["20 vs 40 vs 100 vs 200 BB adjustments"],
            intro: "The same cards play differently at different depths. At 20 big blinds, hands are decided preflop and on flops: shove/fold charts rule and implied odds die. At 100, set-mining and suited connectors gain value. At 200+, the nuts matter enormously and dominated hands become disasters. Before acting, always know the effective stack: the smaller of yours and your opponent's.",
            drill: .pushFold(count: 8, stackBB: 10),
            threshold: 0.75, tags: ["stack depth", "push-fold"], minutes: 8)
    ]

    // MARK: - Academy 3: Flop Strategy (§6)

    private static let flop: [Lesson] = [
        lesson("fl.reading", .flop, "Reading flops", diff: 2, prereq: ["p.opening"],
            objectives: ["Dry vs wet, paired, monotone textures"],
            intro: "Flops have personalities. Dry (K♠8♦2♣): unconnected, rainbow: hands change little on later streets. Wet (9♥8♥7♠): straights and flushes live everywhere and the nuts change often. Paired boards cut everyone's chances of a pair. Monotone boards make one suit king. Texture decides how big and how often to bet: read it before acting.",
            drill: .quiz([
                QuizQuestion("Which flop is driest?", ["J♠T♠9♠", "K♦7♣2♥", "8♥7♥6♣"], correct: 1, why: "K72 rainbow has no flush draw and no connected straight draws: made hands hold their value."),
                QuizQuestion("On 9♥8♥7♥ (monotone), a bare set is…", ["the nuts", "strong but vulnerable", "worthless"], correct: 1, why: "Any single heart already beats you and a fourth heart threatens further. Sets shrink on monotone boards."),
                QuizQuestion("Paired boards like Q-Q-5…", ["hit most ranges hard", "miss most ranges", "guarantee splits"], correct: 1, why: "Two of the queens are gone, so few hands connect: small bets take these pots often."),
                QuizQuestion("\"Wet\" board means…", ["many draws are possible", "low cards only", "three of one suit exactly"], correct: 0, why: "Wet = draw-heavy: connected cards, flush draws, changing nuts. Bet larger, expect action.")
            ]),
            tags: ["board texture"], minutes: 4),

        lesson("fl.rangeadv", .flop, "Range and nut advantage", diff: 3, prereq: ["fl.reading"],
            objectives: ["Whose range hits which flops"],
            intro: "The preflop raiser holds more big cards and big pairs, so ace-high and king-high flops favour them: that is range advantage. The big-blind caller holds more small connected cards, so 6-5-4 favours them. Nut advantage asks a sharper question: who can hold the very strongest hands here? Whoever has both advantages gets to bet relentlessly.",
            drill: .quiz([
                QuizQuestion("On A-K-4 after you open UTG and the BB calls, range advantage belongs to…", ["you", "the big blind", "nobody"], correct: 0, why: "Your opening range is stuffed with aces, kings, and big pairs; the caller's range mostly missed."),
                QuizQuestion("On 6-5-4, the big-blind caller often has…", ["nothing", "more straights and two pairs than the raiser", "only overcards"], correct: 1, why: "Callers defend suited/connected low cards; raisers hold big cards. Low connected flops flip the advantage."),
                QuizQuestion("Nut advantage means…", ["hitting any pair more often", "holding the strongest possible hands more often", "having position"], correct: 1, why: "Range advantage is overall equity; nut advantage is about who can have the monsters. Overbets follow the nuts."),
                QuizQuestion("With a big range advantage on a dry flop, a common play is…", ["a small frequent continuation bet", "always checking", "an all-in"], correct: 0, why: "When your whole range out-hits theirs, a small bet with everything applies pressure cheaply.")
            ]),
            tags: ["range advantage", "board texture"], minutes: 5),

        lesson("fl.cbet", .flop, "Continuation betting", diff: 3, prereq: ["fl.rangeadv"],
            objectives: ["When to c-bet, when to check"],
            intro: "As the preflop raiser you often continue betting: but not automatically. Favour c-betting on boards that hit your range, heads-up, and in position. Check more on low connected boards, multiway, and with hands that hate a raise. These are live flop decisions: the analyzer grades your action and sizing family, not a memorized rule.",
            drill: .postflop(count: 6, street: .flop),
            threshold: 0.7, tags: ["c-bet", "board texture"], minutes: 9),

        lesson("fl.value", .flop, "Value betting", diff: 3, prereq: ["fl.cbet"],
            objectives: ["Bet because worse calls"],
            intro: "A value bet profits because worse hands call it. Before betting a made hand, name what worse actually calls: with top pair, worse top pairs and draws call; with a set, almost everything. Fear-checking strong hands leaks money every session: the pot you fail to build never comes back. Thin value: betting good-but-not-great hands: separates winners from break-even players.",
            drill: .postflop(count: 6, street: .flop),
            threshold: 0.7, tags: ["value", "c-bet"], minutes: 9),

        lesson("fl.semibluff", .flop, "Semi-bluffing draws", diff: 3, prereq: ["fl.cbet"],
            objectives: ["Fold equity plus draw equity"],
            intro: "Betting a flush draw is not really a bluff: it is two ways to win. Opponents fold now, or you hit one of your outs later. Strong draws (flush draws, open-enders, combo draws) make the best semi-bluffs because they arrive with 30-50% equity. Weak gutshots make poor aggression candidates: little fold equity plus little hit equity is just spew.",
            drill: .postflop(count: 6, street: .flop),
            threshold: 0.7, tags: ["bluff", "implied odds"], minutes: 9),

        lesson("fl.facingcbet", .flop, "Facing the c-bet", diff: 3, prereq: ["fl.value"],
            objectives: ["Fold, call, raise with a plan"],
            intro: "Facing a continuation bet, the question is never just \"do I have a pair?\" It is: what does my hand want the next two streets to look like? Call with real pairs and real draws that have a plan. Raise with strong hands and the best semi-bluffs. Fold the hopeless stuff without regret: chasing bad draws at bad prices is the classic beginner leak.",
            drill: .postflop(count: 6, street: .flop),
            threshold: 0.7, tags: ["pot odds", "c-bet"], minutes: 9),

        lesson("fl.multiway", .flop, "Multiway pots", diff: 4, prereq: ["fl.value"],
            objectives: ["Tighter value, fewer bluffs"],
            intro: "Every extra opponent makes someone holding a real hand more likely. Multiway: bluff far less, value bet only genuinely strong hands, and respect raises like they mean it: because they usually do. The nuts matter more; one pair matters less. If two players show interest, your bluff needs them BOTH to fold: the math collapses fast.",
            drill: .quiz([
                QuizQuestion("With three opponents on the flop, bluffing needs…", ["one fold", "every player to fold", "position only"], correct: 1, why: "A bluff wins only if everyone folds. Three players folding 60% each is barely a 22% success rate."),
                QuizQuestion("Multiway, top pair weak kicker is…", ["a monster", "a modest hand to keep the pot controlled with", "an easy all-in"], correct: 1, why: "One-pair hands drop in value with each caller. Keep pots medium; let monsters build big ones."),
                QuizQuestion("A raise into multiple players usually means…", ["a bluff", "genuine strength", "a misclick"], correct: 1, why: "Raising into several opponents needs to survive several ranges. Give it real respect."),
                QuizQuestion("Which hand gains the most value multiway?", ["A gutshot", "The nut flush draw", "Bottom pair"], correct: 1, why: "Nut draws win the whole pile when they hit and never make the second-best hand: multiway gold.")
            ]),
            tags: ["multiway adjustment"], minutes: 5)
    ]

    // MARK: - Academy 4: Turn Strategy (§7)

    private static let turn: [Lesson] = [
        lesson("t.changes", .turn, "How the turn changes ranges", diff: 3, prereq: ["fl.facingcbet"],
            objectives: ["Draw completion, scare cards, blanks"],
            intro: "The turn re-deals the strategic map. A completed flush card transforms betting ranges. An ace helps whoever holds more aces: usually the raiser. A blank (like an offsuit deuce) changes nothing, which itself is information: whoever was ahead is still ahead. Before every turn action, ask one question: whose range did that card improve?",
            drill: .postflop(count: 5, street: .turn),
            threshold: 0.7, tags: ["board texture", "range advantage"], minutes: 8),

        lesson("t.barrels", .turn, "Second barrels and giving up", diff: 4, prereq: ["t.changes"],
            objectives: ["Continue on good cards, quit on bad ones"],
            intro: "Your flop bet got called: now what? Barrel again when the turn improves your range or your actual equity: big cards, cards that complete your draws, cards making their calls awkward. Give up cleanly when the card smashes their range or your hand has no outs. Firing hopeless second barrels because you \"already bet\" is a top-five money leak.",
            drill: .postflop(count: 6, street: .turn),
            threshold: 0.7, tags: ["bluff", "c-bet"], minutes: 9),

        lesson("t.geometry", .turn, "Pot geometry", diff: 4, prereq: ["t.barrels"],
            objectives: ["Sizing today shapes the river"],
            intro: "Stacks are won and lost by geometry. Two-thirds pot on flop and turn sets up a natural river shove; tiny turn bets leave awkward river stacks behind. With the nuts and deep stacks, plan three growing bets. With medium hands, choose sizes that keep the river shallow. Look one street ahead before you pick a number.",
            drill: .quiz([
                QuizQuestion("With the nuts and deep stacks, you want turn sizing that…", ["keeps the pot tiny", "builds toward a full river stack", "ends the hand now"], correct: 1, why: "Geometric sizing: similar pot fractions each street: gets stacks in by the river without an absurd single bet."),
                QuizQuestion("Pot 100, stacks 300 behind on the turn. A pot-sized turn bet leaves the river at…", ["about a pot-size shove", "no possible bet", "a tiny bet"], correct: 0, why: "Bet 100: pot 300, stacks 200: a comfortable sub-pot river shove. Geometry done."),
                QuizQuestion("Small turn bets with medium hands aim to…", ["fold out everything", "control the pot and reach showdown", "trap"], correct: 1, why: "Medium hands want medium pots. Sizing down keeps rivers cheap and decisions easy."),
                QuizQuestion("Ignoring stack depth when sizing the turn causes…", ["nothing", "awkward rivers that waste value or force bad shoves", "faster play"], correct: 1, why: "The river bet you can make is decided by the turn bet you chose. Plan backwards.")
            ]),
            tags: ["stack-to-pot ratio", "bet sizing"], minutes: 5),

        lesson("t.facing", .turn, "Facing turn aggression", diff: 4, prereq: ["t.barrels"],
            objectives: ["Bluff catchers, draws and prices"],
            intro: "Turn bets are more honest than flop bets: ranges have tightened. With bluff catchers, judge whether this opponent arrives with bluffs at all. With draws, do the arithmetic: price versus outs, plus what you win when you hit (implied odds), minus the times you hit and still lose (reverse implied odds). Then commit to a river plan before calling.",
            drill: .postflop(count: 6, street: .turn),
            threshold: 0.7, tags: ["pot odds", "implied odds"], minutes: 9),

        lesson("t.overbet", .turn, "Turn overbets", diff: 5, prereq: ["t.geometry"],
            objectives: ["Leverage with nut advantage"],
            intro: "Betting more than the pot looks reckless: it is actually precision. Overbets belong to the player with nut advantage attacking a capped range: when they can't hold the monsters and you can, an oversized bet puts their whole medium range in agony. Overbet polarized: nuts and your best bluffs, nothing in between. Never overbet merged medium hands into an uncapped range.",
            drill: .quiz([
                QuizQuestion("Overbets work best when the opponent's range is…", ["uncapped", "capped below the new nuts", "full of draws"], correct: 1, why: "If their line rules out the strongest hands and yours doesn't, oversized pressure prints: they hold bluff catchers only."),
                QuizQuestion("A good overbetting range contains…", ["only medium value", "nuts and strong bluffs", "random hands"], correct: 1, why: "Polarization: monsters that want maximum value plus bluffs with blockers. Medium hands prefer smaller bets or checks."),
                QuizQuestion("Facing a turn overbet, your bluff catcher needs…", ["about 30%+ equity and an honest read", "50% equity", "the nuts"], correct: 0, why: "A 1.5x-pot bet offers about 37.5% required equity: call only if this opponent actually arrives with enough bluffs."),
                QuizQuestion("Why does leverage matter on the turn?", ["Cards are bigger", "The threat of a river shove multiplies pressure", "Position swaps"], correct: 1, why: "A turn overbet threatens your whole stack by the river: opponents must decide for everything, one street early.")
            ]),
            tags: ["nut advantage", "bet sizing"], minutes: 5)
    ]

    // MARK: - Academy 5: River Strategy (§8)

    private static let river: [Lesson] = [
        lesson("r.final", .river, "No more cards", diff: 3, prereq: ["t.facing"],
            objectives: ["River logic vs earlier streets"],
            intro: "The river is pure: no draws, no future cards, no equity to protect. Every hand is now a made hand or a busted one, and every bet is a value bet or a bluff: nothing in between. That clarity cuts both ways: your decisions simplify, but so do your opponent's reads. Ask one question before acting: if I bet, what worse calls and what better folds?",
            drill: .postflop(count: 5, street: .river),
            threshold: 0.7, tags: ["value", "bluff"], minutes: 8),

        lesson("r.value", .river, "River value betting", diff: 4, prereq: ["r.final"],
            objectives: ["Thin value, sizing by caller"],
            intro: "The most common river mistake isn't a bad bluff: it's a missed value bet. If worse hands can call, bet. Second pair against a calling station? Bet. Size by opponent: stations pay big bets with weak pairs; nits need smaller prices. Checking down \"to be safe\" with clearly-best hands throws away the easiest chips in poker.",
            drill: .postflop(count: 6, street: .river),
            threshold: 0.7, tags: ["value", "bet sizing"], minutes: 9),

        lesson("r.bluff", .river, "River bluffing", diff: 4, prereq: ["r.final"],
            objectives: ["Missed draws, blockers, credibility"],
            intro: "River bluffs need three ingredients: a hand with zero showdown value (missed draws are perfect), a credible story that you hold the value you're representing, and an opponent capable of folding. Blockers refine it: holding the ace of the flush suit when the flush missed means they can't have the nut flush: bluff. Random panic-bluffs with weak pairs fail every test at once.",
            drill: .postflop(count: 6, street: .river),
            threshold: 0.7, tags: ["bluff", "blockers"], minutes: 9),

        lesson("r.bluffcatch", .river, "Bluff catching", diff: 4, prereq: ["r.value"],
            objectives: ["Beating bluffs, losing to value"],
            intro: "A bluff catcher beats every bluff and loses to every value hand: so the entire decision is: does THIS opponent bluff here often enough for the price? A pot-sized bet needs to be a bluff a third of the time to call. Against players who never bluff rivers, fold your bluff catchers without ceremony and feel zero shame. The pot odds only matter when bluffs actually exist.",
            drill: .postflop(count: 6, street: .river),
            threshold: 0.7, tags: ["bluff catcher", "pot odds"], minutes: 9),

        lesson("r.overbets", .river, "Facing big bets and overbets", diff: 5, prereq: ["r.bluffcatch"],
            objectives: ["Polarization arithmetic"],
            intro: "Huge river bets scream polarization: monsters or air, rarely in between. The arithmetic is your anchor: a 2x-pot overbet lays you exactly 40%: they must bluff two hands in five to make calling neutral. Then adjust with blockers (do you block value or block bluffs?) and honest reads. The discipline is refusing to invent bluffs your opponent has never shown.",
            drill: .quiz([
                QuizQuestion("Facing a pot-sized river bet, calling breaks even when they bluff…", ["1 time in 3", "1 time in 2", "1 time in 10"], correct: 0, why: "Call 1 pot to win 2: you need 33% equity, so a third of their bets must be bluffs."),
                QuizQuestion("Facing a 2x-pot overbet you need about…", ["25%", "40%", "60%"], correct: 1, why: "Call 2 to win 5 total: 2/5 = 40%: overbets demand much more confidence."),
                QuizQuestion("You hold the ace of the flush suit and the flush missed. Facing a big bet, this blocker usually argues for…", ["folding: you block their missed-draw bluffs", "calling: you block their value", "raising for value"], correct: 0, why: "Blocking their missed draws means blocking their BLUFFS: the range that remains is heavier with value. Ask which side of their range your cards remove."),
                QuizQuestion("Against a player who has never shown a river bluff, your bluff catchers should…", ["always call for balance", "usually fold", "raise"], correct: 1, why: "Balance is for opponents who exploit you. Against pure value ranges, folding bluff catchers just wins.")
            ]),
            tags: ["bluff catcher", "blockers", "pot odds"], minutes: 6),

        lesson("r.discipline", .river, "Hero folds and missed value", diff: 5, prereq: ["r.overbets"],
            objectives: ["Discipline in both directions"],
            intro: "Two opposite leaks live on the river: paying off obvious value like a station, and checking down winners like a coward. The cure for both is the same habit: name their range out loud before acting. A hero fold is only heroic when the range genuinely lacks bluffs; a value bet is only thin when worse genuinely calls. Grade yourself on reasoning, never on the cards that happened to appear.",
            drill: .postflop(count: 6, street: .river),
            threshold: 0.72, tags: ["value", "bluff catcher"], minutes: 9)
    ]

    // MARK: - Academy 6: Poker Mathematics (§9)

    private static let math: [Lesson] = [
        lesson("m.outs", .mathematics, "Counting outs", diff: 2, prereq: ["f.mastery"],
            objectives: ["Clean vs dirty outs"],
            intro: "Outs are the unseen cards that improve you to the likely best hand. Flush draw: 9. Open-ended straight draw: 8. Gutshot: 4. Two overcards: about 6: but discount them, because pairing an overcard doesn't always win. Outs that complete opponents' better hands are dirty and count for less. Count honestly; the rest of poker math sits on this.",
            drill: .outs(count: 6),
            threshold: 0.8, tags: ["equity", "outs"], minutes: 6),

        lesson("m.rule24", .mathematics, "From outs to percentages", diff: 2, prereq: ["m.outs"],
            objectives: ["Rule of 2 and 4"],
            intro: "Fast conversion: with one card to come, outs × 2 ≈ your hit percentage. With two cards to come (on the flop, all-in), outs × 4. Nine-out flush draw: about 18% on one street, 36% across two. The rule drifts high above twelve outs, but at the table, close-and-fast beats exact-and-slow every time.",
            drill: .quiz([
                QuizQuestion("Flush draw (9 outs), turn to river only: your chance is about…", ["9%", "18%", "36%"], correct: 1, why: "One card to come: 9 × 2 ≈ 18%. The exact figure is 19.6%: the rule is close enough."),
                QuizQuestion("Open-ender (8 outs) on the flop, seeing both cards: about…", ["16%", "32%", "50%"], correct: 1, why: "Two cards to come: 8 × 4 ≈ 32% (exact ≈ 31.5%)."),
                QuizQuestion("A gutshot on the turn hits the river about…", ["8%", "17%", "25%"], correct: 0, why: "4 outs × 2 ≈ 8%. Gutshots are long shots on a single street."),
                QuizQuestion("15 outs with two cards to come is roughly…", ["45%", "54%", "60% by the rule, slightly high"], correct: 2, why: "The ×4 rule says 60%, but it overshoots with big draws; true value is about 54%. Still a favourite.")
            ]),
            tags: ["equity", "outs"], minutes: 4),

        lesson("m.potodds", .mathematics, "Pot odds", diff: 2, prereq: ["m.rule24"],
            objectives: ["Required equity from the price"],
            intro: "Every call has a price: required equity = call ÷ (pot after your call). Facing 50 into 100? You call 50 to make the pot 200: you need 25%. That's the whole formula. Compare it to your hand's equity and the decision often makes itself. Drill it until the arithmetic is automatic, because every future lesson leans on it.",
            drill: .potOdds(count: 8),
            threshold: 0.8, tags: ["pot odds"], minutes: 6),

        lesson("m.ev", .mathematics, "Expected value", diff: 3, prereq: ["m.potodds"],
            objectives: ["EV thinking, decisions vs results"],
            intro: "Expected value is what a decision earns on average across all futures: EV = (win% × amount won) − (lose% × amount lost). A call can be correct and lose this time; a terrible call can get lucky. Results arrive one at a time, but EV arrives forever. Train yourself to review the decision, not the river card: that is the entire mindset of a professional.",
            drill: .quiz([
                QuizQuestion("You call 100 to win a 300 final pot with 40% equity. EV?", ["+20", "0", "−20"], correct: 0, why: "0.4 × 300 = 120 gained on average, minus the 100 call = +20 per decision."),
                QuizQuestion("You call correctly with 40% equity and lose. The decision was…", ["a mistake", "still correct", "unlucky and therefore wrong"], correct: 1, why: "The 60% happened. It was still a profitable call: make it again forever."),
                QuizQuestion("A bet where opponents fold 50% and you win 30% when called is judged by…", ["one outcome", "the weighted average of all outcomes", "the biggest outcome"], correct: 1, why: "EV sums every branch: fold equity plus showdown equity minus risk. That total is the truth of the play."),
                QuizQuestion("Which loses money long-term?", ["+2 EV plays that often lose", "−5 EV plays that sometimes win", "Both equally"], correct: 1, why: "Sign of EV decides everything long-run. Frequency of winning is emotional noise.")
            ]),
            tags: ["EV"], minutes: 5),

        lesson("m.foldequity", .mathematics, "Fold equity and bluff math", diff: 3, prereq: ["m.ev"],
            objectives: ["Break-even bluff frequency"],
            intro: "A pure bluff of B into a pot of P breaks even when opponents fold B/(B+P) of the time. Half pot: folds needed one third. Full pot: half. Your bluffs don't need to always work: just often enough. Flip it as the caller: a pot-sized bet must be a bluff a third of the time before your bluff catcher calls for profit. One formula, both chairs.",
            drill: .quiz([
                QuizQuestion("A half-pot bluff needs folds…", ["1/4 of the time", "1/3 of the time", "2/3 of the time"], correct: 1, why: "50/(50+100) = 33%. Cheap bluffs need modest fold rates."),
                QuizQuestion("A pot-sized bluff breaks even at…", ["33% folds", "50% folds", "67% folds"], correct: 1, why: "100/(100+100) = 50%. Bigger bluffs need bigger fold rates: but threaten more."),
                QuizQuestion("Semi-bluffs beat pure bluffs because…", ["they're cheaper", "they still win by improving when called", "opponents fold more"], correct: 1, why: "Draw equity is a second way to win: the fold-rate you need drops sharply."),
                QuizQuestion("If a bet only needs 33% folds and this opponent folds 60%…", ["the bluff prints money", "the bluff loses", "no conclusion"], correct: 0, why: "Needing one third and getting well over half is pure profit before your hand even matters.")
            ]),
            tags: ["bluff", "EV"], minutes: 5),

        lesson("m.implied", .mathematics, "Implied and reverse-implied odds", diff: 3, prereq: ["m.potodds"],
            objectives: ["Future chips change today's price"],
            intro: "Pot odds count today's chips; implied odds add tomorrow's. A slightly-wrong call with a hidden monster draw becomes right when hitting wins their stack. Reverse implied odds are the dark twin: hands like weak flush draws or dominated pairs that cost extra precisely when they \"hit\". Deep stacks amplify both. Ask: when I make my hand, does money actually come in: or go out?",
            drill: .quiz([
                QuizQuestion("Implied odds are best with…", ["obvious draws everyone sees", "hidden hands like small sets", "top pair"], correct: 1, why: "Set over-pair collisions pay stacks because your hand is invisible. Obvious flush cards freeze the action."),
                QuizQuestion("Set-mining a small pair wants stacks of at least…", ["3x the call", "15-20x the call", "any size"], correct: 1, why: "You flop the set about 1 in 8. The reward when it hits must dwarf the price, or the mine is a money pit."),
                QuizQuestion("Reverse implied odds describe…", ["winning extra later", "losing extra when you make a second-best hand", "position"], correct: 1, why: "K-high flush draws and dominated aces \"hit\" and then pay off better hands. The cost hides in your wins."),
                QuizQuestion("Shallow stacks make implied odds…", ["bigger", "smaller", "unchanged"], correct: 1, why: "There's simply less left to win. Speculative hands lose value as stacks shrink.")
            ]),
            tags: ["implied odds", "reverse implied odds"], minutes: 5),

        lesson("m.spr", .mathematics, "Stack-to-pot ratio", diff: 4, prereq: ["m.implied"],
            objectives: ["Commitment logic"],
            intro: "SPR = stack remaining ÷ pot. It measures how committed you are. SPR under 2: one-pair hands can stack off comfortably. SPR around 5: pairs proceed carefully; big hands push. SPR above 10: stacks belong to the nuts and near-nuts. Preflop sizing sets the flop SPR: which means you choose, before the flop, which hands you'll be able to play for stacks.",
            drill: .quiz([
                QuizQuestion("Pot 100, you have 150 behind. SPR is…", ["0.7", "1.5", "15"], correct: 1, why: "150 ÷ 100 = 1.5: a committed pot where top pair happily gets it in."),
                QuizQuestion("At SPR 1.5, top pair good kicker should usually…", ["fold to pressure", "get the money in", "check down"], correct: 1, why: "With so little behind relative to the pot, one solid pair is plenty. Folding leaves too much equity behind."),
                QuizQuestion("At SPR 12, stacking off one pair is…", ["standard", "usually a serious error", "mandatory"], correct: 1, why: "Deep money that goes in wants two pair beaten. One pair for 12 pots' worth is how stacks are lost."),
                QuizQuestion("Three-betting preflop mainly does what to SPR?", ["Raises it", "Lowers it, simplifying big-pair play", "Nothing"], correct: 1, why: "Bigger preflop pots mean lower flop SPR: exactly why big pairs three-bet: they want commitment to be easy.")
            ]),
            tags: ["stack-to-pot ratio"], minutes: 5),

        lesson("m.combos", .mathematics, "Combination counting", diff: 4, prereq: ["m.ev"],
            objectives: ["Counting hands and blockers"],
            intro: "Ranges are made of countable combinations: 6 per pocket pair, 4 per suited hand, 12 per offsuit hand. Visible cards delete combos: hold one ace and only 3 combos of AA remain. This is how blockers work and how you weigh value against bluffs in a range: not vibes, arithmetic. Count a few ranges by hand and river decisions stop feeling like guesses.",
            drill: .combos(count: 6),
            threshold: 0.8, tags: ["combinatorics", "blockers"], minutes: 6)
    ]

    // MARK: - Academy 7: Exploitative Play (§10)

    private static let exploit: [Lesson] = [
        lesson("e.baseline", .exploitative, "Baseline versus exploit", diff: 3, prereq: ["fl.facingcbet"],
            objectives: ["When to deviate from balanced play"],
            intro: "Balanced strategy is your fortress: sound frequencies that no opponent exploits. Exploitation is the raiding party: deliberately unbalancing to attack a specific mistake: but every exploit opens a door back at you. The rule: play the baseline against unknowns; deviate hard only when the evidence is real. Sample size is the difference between a read and a superstition.",
            drill: .quiz([
                QuizQuestion("Against a brand-new unknown opponent, play…", ["maximum exploits", "sound baseline strategy", "randomly"], correct: 1, why: "No evidence, no exploit. Baseline strategy profits from typical mistakes without risking counter-exploits."),
                QuizQuestion("Exploiting means…", ["cheating", "unbalancing on purpose to attack a known mistake", "playing more hands"], correct: 1, why: "If they fold too much, you bluff too much: deliberately. That's the entire art."),
                QuizQuestion("Every exploit you make…", ["is free money forever", "creates a weakness an observant opponent can attack", "is invisible"], correct: 1, why: "Bluffing relentlessly beats over-folders until someone notices and starts calling you down."),
                QuizQuestion("One wild hand from an opponent proves…", ["they're a maniac", "almost nothing yet", "they're bluffing always"], correct: 1, why: "Anyone can have one strange hand. Tendencies need samples: adjust gradually as evidence grows.")
            ]),
            tags: ["opponent exploitation"], minutes: 4),

        lesson("e.nits", .exploitative, "Beating the nit", diff: 3, prereq: ["e.baseline"],
            objectives: ["Steal small pots, respect big bets"],
            intro: "Nits play few hands and hate risk. The exploit is beautifully simple: take everything they don't fight for and give them everything they do. Steal their blinds relentlessly, c-bet small and often: then when a nit raises big, believe them and fold hands you'd normally defend. Paying off a nit's river raise with one pair is charity.",
            drill: .quiz([
                QuizQuestion("Against nits, your steal frequency should…", ["drop", "rise sharply", "stay identical"], correct: 1, why: "They surrender blinds and flops constantly. Small pots nobody fights for become your salary."),
                QuizQuestion("A nit's big turn check-raise usually means…", ["a bluff", "a monster: fold your one-pair hands", "tilt"], correct: 1, why: "Underbluffed lines deserve big folds. Their aggression range is value-heavy by definition."),
                QuizQuestion("Bluffing a nit's strong range on the river is…", ["profitable", "burning money: they have it", "balanced"], correct: 1, why: "Bluff people out of weak ranges, not strong ones. When a nit bets, the weak hands already folded."),
                QuizQuestion("The nit's core mistake is…", ["playing too many hands", "folding away too much value before showdown", "calling too much"], correct: 1, why: "Excessive folding leaks constantly in small invisible amounts. You collect them by staying aggressive.")
            ]),
            tags: ["opponent exploitation"], minutes: 4),

        lesson("e.stations", .exploitative, "Beating the calling station", diff: 3, prereq: ["e.baseline"],
            objectives: ["Value thin, never bluff"],
            intro: "Stations hate folding: so stop asking them to. Retire your bluffs entirely: a bluff needs folds, and folds are the one thing they refuse to provide. Instead value bet mercilessly thin: second pair, third pair, any hand a worse hand can pay. Size up: they call big bets nearly as often as small ones. Boring, brutal, extremely profitable.",
            drill: .quiz([
                QuizQuestion("Against a station, bluffing frequency should be…", ["higher", "near zero", "unchanged"], correct: 1, why: "Bluffs profit from folds. No folds, no bluffs: the simplest exploit in poker."),
                QuizQuestion("Middle pair on the river against a station is…", ["a check", "a value bet", "a bluff"], correct: 1, why: "They call with worse pairs and ace-high. Hands you'd check against solid players become bets."),
                QuizQuestion("Your value sizing against stations should be…", ["smaller", "larger", "always all-in"], correct: 1, why: "Inelastic callers pay big and small alike: so charge big."),
                QuizQuestion("A station finally raises you. That usually means…", ["a bluff", "real strength: they don't raise light", "confusion"], correct: 1, why: "Passive players' rare aggression is heavy with value. Fold your thin hands and move on.")
            ]),
            tags: ["opponent exploitation", "value"], minutes: 4),

        lesson("e.maniacs", .exploitative, "Surviving the maniac", diff: 4, prereq: ["e.stations"],
            objectives: ["Widen calls, keep composure"],
            intro: "Maniacs bomb every pot and dare you to fight. Don't out-aggro them: under-aggro them. Widen your calling and value ranges: hands that are bluff-catchers against normal players become clear calls against constant fire. Let them bluff into your made hands instead of bluffing into their calls. Expect variance, protect your composure, and never make it personal.",
            drill: .quiz([
                QuizQuestion("Against a maniac, top pair medium kicker becomes…", ["a fold to aggression", "a confident call-down hand", "a bluff"], correct: 1, why: "Their betting range overflows with air. Hands that fear normal aggression welcome theirs."),
                QuizQuestion("The main anti-maniac plan is…", ["bluff them more", "trap and call down with real hands", "avoid every pot"], correct: 1, why: "They build your pots for you. Supply the hand; let them supply the chips."),
                QuizQuestion("Playing pots with a maniac means accepting…", ["no variance", "bigger swings for bigger profit", "certain losses"], correct: 1, why: "Wide-range wars swing hard. The edge is real but arrives loudly."),
                QuizQuestion("Getting personally competitive with a maniac leads to…", ["free chips", "spite calls and forced bluffs: their favourite food", "nothing"], correct: 1, why: "Maniacs profit from your emotions. Stay mechanical; beat them with ranges, not ego.")
            ]),
            tags: ["opponent exploitation"], minutes: 4),

        lesson("e.tells", .exploitative, "Sizing and timing tells", diff: 4, prereq: ["e.maniacs"],
            objectives: ["Careful pattern reading"],
            intro: "Bet-size patterns are real but personal: some players size small with weakness and huge with monsters: others reverse it. Timing is noisier still. Treat both as weak evidence: note the pattern, wait for confirmation at showdown, then lean on it gently. A tell you've verified twice is a hint; a tell you've imagined once is a trap. Never override range logic on a hunch.",
            drill: .quiz([
                QuizQuestion("A reliable read requires…", ["one observation", "repeated confirmations, ideally at showdown", "intuition"], correct: 1, why: "Patterns must repeat and be verified against revealed cards before they earn your chips."),
                QuizQuestion("A specific player has shown huge bets as bluffs twice at showdown. Their next huge bet…", ["is certainly a bluff", "slightly shifts your call threshold", "means nothing"], correct: 1, why: "Two confirmations justify leaning: not certainty. Update by degrees, like the arithmetic does."),
                QuizQuestion("Instant snap-calls postflop often indicate…", ["the nuts", "draws or medium hands that found the decision easy", "always weakness"], correct: 1, why: "Monsters usually pause to consider raising. But 'often' is not 'always': timing stays noisy evidence."),
                QuizQuestion("When a tell conflicts with clear range logic…", ["trust the tell", "trust the range logic", "flip a coin"], correct: 1, why: "Ranges are built on every hand they've played; a tell is built on a handful. Weight accordingly.")
            ]),
            tags: ["opponent exploitation"], minutes: 4)
    ]

    // MARK: - Academy 8: Tournament Poker (§11)

    private static let tournament: [Lesson] = [
        lesson("tn.structure", .tournament, "How tournaments work", diff: 2, prereq: ["f.mastery"],
            objectives: ["Levels, antes, eliminations, payouts"],
            intro: "Everyone buys in for the same stack; blinds rise on a schedule until the chips concentrate and players bust. Prizes go to the top finishers: in our six-max Sit-and-Go, the top two. Antes join later levels, taxing every hand and rewarding aggression. The one metric to watch permanently: your stack measured in big blinds, because the blinds never stop climbing.",
            drill: .quiz([
                QuizQuestion("Your 3,000-chip stack at blinds 100/200 is…", ["deep", "15 big blinds: getting short", "unplayable"], correct: 1, why: "Chips mean nothing without the blind level; 15 BB is decision territory: steal, resteal, shove."),
                QuizQuestion("Rising blinds mean waiting passively…", ["is free", "quietly destroys your stack", "is optimal"], correct: 1, why: "Every orbit costs blinds and antes. In tournaments, doing nothing is a slow all-in."),
                QuizQuestion("In a 6-player SNG paying two places, third place wins…", ["a small prize", "nothing", "their buy-in back"], correct: 1, why: "Bubble finishes pay zero: which is exactly why bubble strategy becomes its own science."),
                QuizQuestion("Antes make ranges…", ["tighter", "wider: more dead money per pot", "irrelevant"], correct: 1, why: "Extra dead chips in each pot raise the reward for taking it. Everyone should fight more.")
            ]),
            tags: ["tournament risk"], minutes: 4),

        lesson("tn.chipvalue", .tournament, "Chips are not cash", diff: 3, prereq: ["tn.structure"],
            objectives: ["Nonlinear chip value"],
            intro: "In cash games a chip is a chip. In tournaments, doubling your stack less than doubles your prize equity, and busting loses everything at once: so the chips you might lose are worth more than the chips you might win. That asymmetry is why correct tournament play declines thin edges a cash player would snap-take. It sharpens brutally near the bubble.",
            drill: .quiz([
                QuizQuestion("Doubling your tournament stack…", ["doubles your prize equity", "less than doubles it", "more than doubles it"], correct: 1, why: "Prize pools are shared: each added chip adds a bit less equity. The last chip you lose costs the most."),
                QuizQuestion("A 51/49 all-in early in a tournament is…", ["mandatory", "often correctly declined", "illegal"], correct: 1, why: "The 49% includes total elimination. Thin coin-flips price in a risk premium in tournaments."),
                QuizQuestion("The chips you already have versus chips you could win are…", ["equal value", "yours are worth more per chip", "worth less"], correct: 1, why: "Survival has value. Losing your stack ends every future opportunity; winning the same amount doesn't double it."),
                QuizQuestion("This survival asymmetry is strongest…", ["at the first hand", "near the bubble and pay jumps", "never"], correct: 1, why: "When a pay jump is close, busting costs real prize equity: folds that look weak become correct.")
            ]),
            tags: ["tournament risk", "ICM"], minutes: 4),

        lesson("tn.pushfold", .tournament, "Push-fold play", diff: 3, prereq: ["tn.chipvalue"],
            objectives: ["Short-stack shoving discipline"],
            intro: "Under about twelve big blinds, tiny raises just glue you to the pot: so the short stack's real options are shove or fold. Shoving first-in is powerful: you take blinds and antes uncontested or race with fold equity already banked. Position rules the width: tight early, wide on the button, wildly wide in the small blind. These are live shove decisions: drill them to reflex.",
            drill: .pushFold(count: 8, stackBB: 8),
            threshold: 0.75, tags: ["push-fold", "stack depth"], minutes: 8),

        lesson("tn.bubble", .tournament, "Bubble pressure", diff: 4, prereq: ["tn.pushfold"],
            objectives: ["Risk premium, cover pressure"],
            intro: "On the bubble one elimination means everyone left gets paid: so busting now is catastrophic while folding is merely annoying. Big stacks weaponize this: they shove relentlessly because nobody covered can call thin. Calling ranges tighten far more than shoving ranges. Know your cover status every hand: attack the stacks that fear you, avoid wars with the one stack that doesn't.",
            drill: .quiz([
                QuizQuestion("On the bubble, calling an all-in requires…", ["the same range as shoving", "a much tighter range than shoving", "any pair"], correct: 1, why: "The shover wins folds; the caller risks elimination with no fold equity. Calling carries the full risk premium."),
                QuizQuestion("The big stack's correct bubble strategy is…", ["patience", "relentless pressure on medium stacks", "calling everything"], correct: 1, why: "Medium stacks can't defend without risking everything. The chip leader taxes them mercilessly."),
                QuizQuestion("As a medium stack on the bubble, confrontations with the cover stack are…", ["great spots", "to be avoided without monsters", "mandatory"], correct: 1, why: "They can bust you; you can't bust them. That asymmetry poisons every marginal spot."),
                QuizQuestion("The shortest stack at the bubble should…", ["fold to the money", "pick aggressive shoves before blinding out", "call wide"], correct: 1, why: "Blinding away guarantees the bubble. First-in shoves with fold equity are the escape route.")
            ]),
            tags: ["tournament risk", "ICM", "push-fold"], minutes: 5),

        lesson("tn.icm", .tournament, "ICM in plain language", diff: 4, prereq: ["tn.bubble"],
            objectives: ["Prize equity thinking"],
            intro: "The Independent Chip Model converts stacks into prize equity: your share of each payout, weighted by finishing chances. Its practical output is the risk premium: the extra equity a call must clear beyond cash-game pot odds. A flip worth calling for chips can be a clear fold for money. RIVER computes exact six-player ICM in reviews; your job is the instinct: calls tighten near pay jumps.",
            drill: .quiz([
                QuizQuestion("ICM converts chip stacks into…", ["blinds", "expected prize money", "rankings"], correct: 1, why: "It weighs every finishing order by probability to price your stack in prize terms."),
                QuizQuestion("Risk premium means tournament calls need…", ["less equity than pot odds say", "more equity than pot odds say", "exactly pot odds"], correct: 1, why: "Elimination costs future equity that pot odds ignore. The premium is largest at the bubble and final pay jumps."),
                QuizQuestion("ICM pressure applies most to…", ["the chip leader", "stacks that others cover", "nobody"], correct: 1, why: "If losing the pot busts you, every marginal chip risked carries prize-equity downside."),
                QuizQuestion("Two equal stacks remain, prizes 60/40. Each stack's ICM equity is…", ["50% of the pool", "60%", "whoever won more pots gets more"], correct: 0, why: "Equal stacks, equal chances: each holds half the remaining prize pool's value.")
            ]),
            tags: ["ICM", "tournament risk"], minutes: 5),

        lesson("tn.headsup", .tournament, "Heads-up endgame", diff: 4, prereq: ["tn.icm"],
            objectives: ["Wide ranges, relentless pressure"],
            intro: "Heads-up, every hand posts a blind and average holdings are garbage: so garbage becomes playable. The button (small blind) should raise well over half of all hands; king-high can be a value hand; second pair is often strong. Tight heads-up play doesn't lose slowly, it loses certainly: the blinds devour anyone waiting for premiums. Re-calibrate everything wider and keep the pressure permanent.",
            drill: .quiz([
                QuizQuestion("Heads-up on the button you should raise…", ["about 20% of hands", "60-80% of hands", "only pairs and aces"], correct: 1, why: "With one random hand to beat and blinds every hand, most holdings profit as raises."),
                QuizQuestion("Heads-up, ace-high at showdown is…", ["weak", "frequently the best hand", "a fold preflop"], correct: 1, why: "Average hands collapse in value heads-up. Ace-high wins showdowns it never would six-max."),
                QuizQuestion("Waiting for premium hands heads-up…", ["is disciplined", "is fatal: blinds arrive every hand", "wins slowly"], correct: 1, why: "You post half the blinds every single hand. Patience is a strategy for full tables, not duels."),
                QuizQuestion("Heads-up preflop, the button acts…", ["last", "first", "simultaneously"], correct: 1, why: "Special heads-up rule: the button posts the small blind and acts first preflop, then last postflop.")
            ]),
            tags: ["heads-up", "preflop range"], minutes: 4)
    ]

    // MARK: - Academy 9: Advanced Range Strategy (§12)

    private static let advanced: [Lesson] = [
        lesson("a.ranges", .advancedRanges, "Thinking in ranges", diff: 4, prereq: ["r.bluffcatch", "m.combos"],
            objectives: ["Distributions, not guesses"],
            intro: "Amateurs put opponents on a hand; professionals put them on a weighted distribution and update it with every action. A UTG open isn't 'ace-king': it's roughly the top 15% of hands, some combos now more likely than others. Each check, bet, and size then prunes and reweights. You never need to know their hand; you need to price your decision against the whole distribution.",
            drill: .quiz([
                QuizQuestion("\"Putting someone on a range\" means…", ["guessing one hand", "tracking a weighted set of possible hands", "reading their face"], correct: 1, why: "One-hand guesses are coin flips. Distributions turn every decision into arithmetic."),
                QuizQuestion("Each opponent action should…", ["reset your read", "narrow and reweight their range", "be ignored"], correct: 1, why: "Actions filter ranges: hands that would have acted differently shrink in weight: rarely to zero."),
                QuizQuestion("An opponent checks the flop and turn. Their range is now…", ["stronger", "weighted toward medium and weak hands", "unchanged"], correct: 1, why: "Strong hands usually bet somewhere. Two checks cap the range: and capped ranges invite pressure."),
                QuizQuestion("Range thinking beats hand-guessing because…", ["it feels smarter", "decisions are priced against every possibility at once", "it's faster"], correct: 1, why: "You'll never see their cards in time. Averaging over the distribution is the only honest math available.")
            ]),
            tags: ["range advantage", "combinatorics"], minutes: 5),

        lesson("a.capped", .advancedRanges, "Capped and uncapped ranges", diff: 4, prereq: ["a.ranges"],
            objectives: ["Attacking limited strength"],
            intro: "A range is capped when prior actions rule out the strongest hands: the player who just called preflop rarely holds aces; the player who checked twice rarely holds the flopped set. Uncapped ranges keep their monsters. The strategic law: uncapped attacks capped. When the river card crowns hands only YOUR line can contain, that's your licence for maximum pressure.",
            drill: .quiz([
                QuizQuestion("A preflop caller's range is usually capped because…", ["they're weak players", "their strongest hands would have re-raised", "they have fewer chips"], correct: 1, why: "AA/KK three-bet almost always. Flat-calls carry a ceiling: remember it on ace-high rivers."),
                QuizQuestion("Your opponent's range is capped and yours isn't. You should…", ["check for safety", "apply heavy pressure, even overbets", "fold"], correct: 1, why: "They hold bluff catchers at best; you credibly hold the ceiling. That asymmetry is where overbets print."),
                QuizQuestion("Checking every street does what to your range?", ["Strengthens it", "Caps it and invites bluffs", "Hides it"], correct: 1, why: "Lines leak information. All-check lines advertise a ceiling: protect key checking ranges with some slowplays."),
                QuizQuestion("A board runout that helps only the aggressor's range is called…", ["a blank", "a range-shifting card favouring the uncapped side", "unfair"], correct: 1, why: "Cards that complete hands only one line can hold shift the whole strategic burden onto the capped player.")
            ]),
            tags: ["range advantage", "nut advantage"], minutes: 5),

        lesson("a.polar", .advancedRanges, "Polarized versus merged", diff: 5, prereq: ["a.capped"],
            objectives: ["Two shapes of betting ranges"],
            intro: "Betting ranges come in two shapes. Polarized: monsters plus bluffs, no middle: pairs with big sizes, because middling hands would rather showdown cheap. Merged: a continuous run of good-but-not-nutted value: pairs with modest sizes, aimed at worse calls. Reading the shape from the size, and choosing your own shape deliberately, is the heart of advanced betting.",
            drill: .quiz([
                QuizQuestion("A 2x-pot river bet typically represents…", ["a merged range", "nuts or air", "medium pairs"], correct: 1, why: "Middle-strength hands gain nothing betting huge. Massive sizes speak the polarized language."),
                QuizQuestion("A merged betting range contains…", ["only bluffs", "layers of decent value hands", "only the nuts"], correct: 1, why: "Merged bets charge worse hands across a smooth strength band: sized so they can actually call."),
                QuizQuestion("Against a polarized bet, medium bluff catchers should…", ["always fold", "call at a frequency based on his bluff count", "always call"], correct: 1, why: "Every catcher beats the bluffs and loses to the value: the bluff-to-value ratio decides how often to pay."),
                QuizQuestion("Betting small with your whole strong-plus-medium range is…", ["polarized", "merged", "random"], correct: 1, why: "Small merged bets tax worse hands broadly. Shape and size travel together.")
            ]),
            tags: ["bet sizing", "range advantage"], minutes: 5),

        lesson("a.blockers", .advancedRanges, "Blocker warfare", diff: 5, prereq: ["a.polar"],
            objectives: ["Card removal as a weapon"],
            intro: "Your own cards edit your opponent's range. Holding the ace of the missed flush suit deletes their nut-flush bluffs: a fold cue. Holding the king of a made-flush board deletes their nut flush: a bluff cue, because you block value and can credibly represent it. The discipline: ask which HALF of their range your cards remove. Blocking bluffs argues fold; blocking value argues call or bluff.",
            drill: .quiz([
                QuizQuestion("Bluffing while holding their nut-flush card is powerful because…", ["you might hit", "they can't hold the hand you're representing", "it's tricky"], correct: 1, why: "You block the value they'd continue with AND can represent it yourself: the classic blocker bluff."),
                QuizQuestion("Your cards block their likely bluffs. Calling gets…", ["better", "worse: the remaining range is value-heavy", "unchanged"], correct: 1, why: "Removing bluff combos tilts what's left toward value. Unblocking bluffs is what good calls want."),
                QuizQuestion("Holding one ace changes AA combos from 6 to…", ["5", "3", "1"], correct: 1, why: "AA needs two of the remaining three aces: 3 combos. Card removal is always concrete arithmetic."),
                QuizQuestion("Blocker logic matters most on…", ["the flop", "the river, where ranges are narrow", "preflop only"], correct: 1, why: "In narrow river ranges, one removed combo can swing the bluff-to-value ratio past your decision threshold.")
            ]),
            tags: ["blockers", "combinatorics"], minutes: 5),

        lesson("a.mixed", .advancedRanges, "Mixed strategies and balance", diff: 5, prereq: ["a.blockers"],
            objectives: ["Frequencies over certainties"],
            intro: "In genuinely close spots, strong players mix: raising a hand sometimes and calling it otherwise: so no single read unlocks them. Mixing only matters where EVs are near-equal and opponents are paying attention; against players who never adjust, pick the plainly best exploit every time. Balance is armour you wear against observant enemies, not a costume for every table.",
            drill: .quiz([
                QuizQuestion("Mixing actions makes sense when…", ["every decision", "candidate actions are close in EV against observant opponents", "you're bored"], correct: 1, why: "When EVs tie, frequencies deny information. When one action clearly wins, mixing burns money."),
                QuizQuestion("Against a player who never adapts, balance is…", ["essential", "unnecessary: take the pure exploit", "rude"], correct: 1, why: "Protection from adaptation matters only when adaptation exists. Exploit the oblivious relentlessly."),
                QuizQuestion("A balanced river betting range means…", ["all value", "value and bluffs in a ratio matched to the bet size", "random hands"], correct: 1, why: "Pot-size bets want 2:1 value-to-bluff; the size sets the honest ratio that makes opponents indifferent."),
                QuizQuestion("The purpose of balance is…", ["beauty", "making your opponent's counter-strategy unprofitable", "variance"], correct: 1, why: "Balance removes their good options. It's defensive equity against players sharp enough to exploit patterns.")
            ]),
            tags: ["range advantage", "bet sizing"], minutes: 5),

        lesson("a.mastery", .advancedRanges, "Advanced application", diff: 5, prereq: ["a.mixed"],
            objectives: ["Full-stack river reasoning under uncertainty"],
            intro: "The graduation exercise: live river decisions where nothing is obvious: thin value against uncertain ranges, blocker-driven bluff spots, close bluff-catches. The analyzer grades honestly and will call many of these spots close, because they are. What's being tested isn't chart recall; it's whether your reasoning survives ambiguity. Expect 'Mixed' verdicts and be suspicious of certainty.",
            drill: .postflop(count: 8, street: .river),
            threshold: 0.68, tags: ["value", "bluff catcher", "blockers"], minutes: 12)
    ]
}
