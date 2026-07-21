import SwiftUI
import RiverKit

/// Plain-language glossary. Every abbreviation and piece of jargon used
/// anywhere in the app is defined here in ordinary words, searchable, with
/// no assumed knowledge.
struct GlossaryView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var searchText = ""

    struct Term: Identifiable {
        let id = UUID()
        let name: String
        let definition: String
    }

    struct Group: Identifiable {
        let id = UUID()
        let title: String
        let terms: [Term]
    }

    static let groups: [Group] = [
        Group(title: "The absolute basics", terms: [
            Term(name: "Pot", definition: "The pile of chips in the middle of the table that everyone is trying to win. Every bet anyone makes goes into the pot, and the winner of the hand takes it all."),
            Term(name: "Chips", definition: "The play money used to bet. In this app chips are always fictional. You can never buy them and they are never worth real money."),
            Term(name: "Hand", definition: "Two meanings: (1) one full round of play from dealing cards to someone winning the pot, and (2) the cards you personally hold."),
            Term(name: "Hole cards", definition: "Your two private cards that only you can see."),
            Term(name: "Community cards / the board", definition: "Up to five shared cards dealt face up in the middle. Everyone combines them with their own two cards to make their best five-card hand."),
            Term(name: "Showdown", definition: "The end of a hand when the remaining players reveal their cards. The best five-card hand wins the pot."),
            Term(name: "Bluff", definition: "Betting with a weak hand to pressure opponents with better hands into folding. A normal, legal part of poker."),
            Term(name: "Stack", definition: "All the chips a player has at the table. \"A 200-chip stack\" means that player has 200 chips to play with.")
        ]),
        Group(title: "The forced bets (blinds)", terms: [
            Term(name: "Blinds", definition: "Two forced bets posted before any cards are looked at, so there is always something in the pot worth fighting for. They rotate around the table every hand."),
            Term(name: "Small blind (SB)", definition: "The smaller forced bet, posted by the player just left of the dealer button."),
            Term(name: "Big blind (BB)", definition: "The larger forced bet, posted by the player two seats left of the dealer button. Also used as a unit of measurement: \"a 100 BB stack\" means a stack worth 100 big blinds."),
            Term(name: "Ante", definition: "A small extra forced bet everyone posts in some tournament levels, making pots bigger.")
        ]),
        Group(title: "Seats and positions", terms: [
            Term(name: "Button (BTN)", definition: "The dealer position, marked with a \"D\" disc. The button acts LAST after the flop, which is the biggest advantage at the table. It moves one seat left every hand so everyone takes turns."),
            Term(name: "Position", definition: "Where you sit relative to the button. \"Good position\" means acting after your opponents, so you see what they do before deciding."),
            Term(name: "UTG (under the gun)", definition: "The first player to act before the flop. The hardest seat, because everyone else still gets to react to you."),
            Term(name: "HJ (hijack)", definition: "The seat two to the right of the button."),
            Term(name: "CO (cutoff)", definition: "The seat directly right of the button. Second-best seat at the table.")
        ]),
        Group(title: "The four betting rounds (streets)", terms: [
            Term(name: "Street", definition: "Poker slang for one betting round. There are four: preflop, flop, turn and river."),
            Term(name: "Preflop", definition: "The first betting round, right after you get your two private cards and before any shared cards appear."),
            Term(name: "Flop", definition: "The first three shared cards, dealt together, and the betting round that follows them."),
            Term(name: "Turn", definition: "The fourth shared card and its betting round."),
            Term(name: "River", definition: "The fifth and final shared card and the last betting round. This app is named after it.")
        ]),
        Group(title: "Actions you can take", terms: [
            Term(name: "Fold", definition: "Give up the hand. You lose any chips you already put in, but nothing more."),
            Term(name: "Check", definition: "Pass the action to the next player without betting. Only allowed when nobody has bet yet this round."),
            Term(name: "Bet", definition: "Put chips into the pot when nobody else has this round. Opponents must at least match it to continue."),
            Term(name: "Call", definition: "Match the current bet to stay in the hand."),
            Term(name: "Raise", definition: "Increase the current bet. Everyone else must match the new amount, raise again, or fold."),
            Term(name: "All-in", definition: "Bet every chip you have. You can never lose more than your stack, and you stay in the hand even if others keep betting more."),
            Term(name: "Limp", definition: "Just calling the big blind before the flop instead of raising. Usually a weak play, and one of the first habits the training tries to fix."),
            Term(name: "Open / open-raise", definition: "Being the first player to raise before the flop.")
        ]),
        Group(title: "Common strategy words", terms: [
            Term(name: "3-bet", definition: "The second raise before the flop. The big blind counts as the first bet, an open-raise is the second, so re-raising it is the \"3-bet\"."),
            Term(name: "C-bet (continuation bet)", definition: "When the player who raised before the flop also bets on the flop, \"continuing\" their aggression."),
            Term(name: "Value bet", definition: "Betting a strong hand because you want worse hands to call and pay you."),
            Term(name: "Bluff catcher", definition: "A medium hand that only wins if your opponent is bluffing."),
            Term(name: "Kicker", definition: "The side card that breaks ties. With A-K versus A-Q on an ace flop, both have a pair of aces, but the K kicker wins."),
            Term(name: "Draw", definition: "A hand that is not strong yet but could become strong: for example four cards to a flush waiting on the fifth."),
            Term(name: "Outs", definition: "The number of unseen cards that would improve your hand. Four cards to a flush have nine outs (nine remaining cards of that suit)."),
            Term(name: "Pot odds", definition: "The price of calling compared to the size of the pot. If the pot is 90 and the call costs 10, you pay 10 to win 100, so you only need to win 1 time in 10 for calling to break even."),
            Term(name: "Equity", definition: "Your percentage chance of winning the pot if the rest of the cards were dealt out with no more betting."),
            Term(name: "Range", definition: "All the different hands an opponent could realistically have, instead of guessing one exact hand.")
        ]),
        Group(title: "Statistics in this app", terms: [
            Term(name: "Pots entered (VPIP)", definition: "The percentage of hands where you chose to put chips in voluntarily. Around 20-30% is typical for solid six-player poker. Much higher usually means playing too many weak hands."),
            Term(name: "Raised first (PFR)", definition: "The percentage of hands where you came in raising rather than calling. Good players raise most of the hands they play."),
            Term(name: "Net chips", definition: "Total chips won minus total chips lost. Positive means you are up."),
            Term(name: "Leak", definition: "A repeated, measurable mistake in your play, like folding too often to bets. The app detects leaks from your real hands and points you to the lesson that fixes each one."),
            Term(name: "Skill rating", definition: "A score from 800 to 1500 based on the quality of your decisions, not your luck. Winning a hand you misplayed does not raise it."),
            Term(name: "Six-max", definition: "A table with at most six players, the format used here. Fewer players means you play more hands."),
            Term(name: "Heads-up", definition: "Poker with exactly two players.")
        ]),
        Group(title: "Tournament words", terms: [
            Term(name: "Sit & Go", definition: "A small tournament that starts as soon as the seats are full. Everyone pays the same entry, blinds rise over time, and you play until one player has all the chips."),
            Term(name: "Blind levels", definition: "In tournaments the forced bets increase on a schedule, forcing action as stacks get shorter relative to the blinds."),
            Term(name: "Bubble", definition: "The moment when one more elimination means everyone left wins a prize. Play tightens up because busting now is the worst possible time."),
            Term(name: "ICM", definition: "A standard formula for what a tournament stack is worth in prize money. It explains why risking all your chips is worth less in a tournament than the same bet in a regular game."),
            Term(name: "Push/fold", definition: "Short-stack strategy: when your stack is small (about 10 big blinds or less) the correct play is usually either going all-in or folding, nothing in between.")
        ]),
        Group(title: "Blackjack", terms: [
            Term(name: "Hit", definition: "Take another card."),
            Term(name: "Stand", definition: "Take no more cards and let the dealer play."),
            Term(name: "Double (double down)", definition: "Double your bet, take exactly one more card, then stand automatically."),
            Term(name: "Split", definition: "When your first two cards match, you can pay a second bet and play them as two separate hands."),
            Term(name: "Bust", definition: "Going over 21. An automatic loss."),
            Term(name: "Soft hand", definition: "A hand with an ace counted as 11, like ace+6 as \"soft 17\". It cannot bust with one more card, because the ace can drop back to counting as 1."),
            Term(name: "Blackjack / natural", definition: "An ace plus a ten-value card as your first two cards. It pays 3 chips for every 2 bet, better than a normal win."),
            Term(name: "Insurance", definition: "A side bet offered when the dealer shows an ace, paying 2:1 if the dealer has blackjack. Basic strategy says to decline it."),
            Term(name: "Surrender", definition: "Give up immediately and get half your bet back. Only correct with the very worst hands, when enabled."),
            Term(name: "Basic strategy", definition: "The mathematically best decision for every blackjack situation, worked out decades ago. The app can show it to you as you play."),
            Term(name: "Shoe", definition: "The stack of several shuffled decks the dealer deals from."),
            Term(name: "Running count / true count", definition: "Card counting numbers that track whether the remaining shoe is rich in high cards. Included as an optional training exercise, off by default.")
        ]),
        Group(title: "Roulette", terms: [
            Term(name: "Straight up", definition: "A bet on one single number. Pays 35 to 1."),
            Term(name: "Split / street / corner / six line", definition: "Bets covering 2, 3, 4 or 6 neighbouring numbers on the betting table. Fewer numbers pays more per chip."),
            Term(name: "Inside / outside bets", definition: "Inside bets sit on the numbers themselves; outside bets are the big areas like Red, Odd, or 1-18 that cover many numbers at once for smaller payouts."),
            Term(name: "Zero / double zero", definition: "The green pockets. When the ball lands there, all outside bets like Red or Even lose. The American wheel adds a second green pocket (00), which makes every bet slightly worse. The app tells you this instead of hiding it."),
            Term(name: "House edge", definition: "The small built-in mathematical advantage the game has over the player. It is constant here. No streak, system or pattern changes it.")
        ]),
        Group(title: "Plinko", terms: [
            Term(name: "Multiplier", definition: "What your wager is multiplied by when the ball lands in a slot. 0.5x returns half your wager; 10x returns ten times it."),
            Term(name: "Risk level", definition: "Which multiplier table is active. Higher risk means bigger edge slots but worse middle slots. The average return is nearly identical either way."),
            Term(name: "Wager", definition: "The chips you put on one ball or one round. Same word as \"bet\".")
        ])
    ]

    private var filtered: [Group] {
        guard !searchText.isEmpty else { return Self.groups }
        return Self.groups.compactMap { group in
            let terms = group.terms.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.definition.localizedCaseInsensitiveContains(searchText)
            }
            return terms.isEmpty ? nil : Group(title: group.title, terms: terms)
        }
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Text("Every term used in the app, in plain words. No prior knowledge assumed.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textSecondary)
                    ForEach(filtered) { group in
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            Text(group.title.uppercased()).sectionHeader()
                            ForEach(group.terms) { term in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(term.name)
                                        .font(Theme.Fonts.body.weight(.bold))
                                        .foregroundStyle(settingsStore.accent)
                                    Text(term.definition)
                                        .font(Theme.Fonts.body)
                                        .foregroundStyle(Theme.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(Theme.Spacing.m)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
                            }
                        }
                    }
                    if filtered.isEmpty {
                        Text("Nothing matches \"\(searchText)\".")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .readableColumn()
        }
        .searchable(text: $searchText, prompt: "Search any term")
        .navigationTitle("Glossary")
        .navigationBarTitleDisplayMode(.inline)
    }
}
