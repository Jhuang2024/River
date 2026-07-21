# RIVER

A serious, offline No-Limit Texas Hold'em simulator and training system for iPhone,
disguised as a fast, tense mobile game. Fictional chips only: nothing to buy,
no ads, no accounts, no network.

## Current status: feature complete

- Six-max and heads-up cash games: you + AI opponents, blinds 1/2, 200-chip (100 BB) stacks
- Complete No-Limit Hold'em rules: correct action order, blinds, min-raises,
  incomplete all-in raises (action re-opening handled exactly), multiple all-ins,
  main/side pots, split pots and odd-chip distribution, heads-up rules
- Fully tested 7-card hand evaluator with readable hand descriptions
- Three bot archetypes (Nit, Calling Station, Loose-Aggressive) at Beginner and
  Intermediate difficulty, driven by seeded, deterministic decision logic that
  can only see legally available information
- Monte Carlo equity estimation (off the main thread, deterministic per seed)
- Assistance modes: Guided / Hints / Pure presets plus individual toggles
  (hand strength, pot odds, on-request advice with reasoned explanations)
- Sessions of 5/10/20/50/unlimited hands with autosave and resume
- Complete hand histories with step-by-step replay and per-decision analysis
- Session results with chip graph and basic stats (VPIP, PFR, showdowns)
- Deterministic seeded shuffling: inspect any hand's deck seed after the fact
- Synthesized sound, haptics, four-color deck option, speed controls

## Interface

The UI follows the RIVER design specification: a token-driven dark visual
system (near-black backgrounds, graphite surfaces, muted felt, one
player-selected accent colour), monospaced digits for every number that
changes, and a portrait table built in three regions: thin status bar, the
six-max table, and a thumb-reach hero region.

- Tab shell: **Play**, **Train**, **Progress**, **Review**, **Profile**. The
  live table is a full-screen destination outside the tabs.
- Contextual action bar (Fold separated; labels carry amounts), bet-sizing
  sheet with adaptive presets (BB multiples preflop, pot fractions postflop),
  integer-snapping slider and exact entry.
- Central animation sequencing: staged board reveals, chip sweeps into the
  pot, ordered showdown reveals, winner banners; speed presets multiply the
  shared motion durations; Reduce Motion is respected.
- Layered assistance: Glance (hand, draws, price), Hint (reasoned
  recommendation with honest confidence), plus action history, opponent
  reads from observed stats only, and tap-to-inspect pot breakdowns.
- Safety: Protect Strong Hands fold confirmation, all-in confirmations,
  optional swipe-to-fold, optional decision timers, left-handed layout.
- First launch asks three questions (experience, help level, first goal) and
  configures the starting experience: no accounts, no tour.
- Four deck styles including a colourblind-friendly four-colour deck; six
  accent colours; four cosmetic felt themes and chip styles (visual only);
  VoiceOver labels on cards and seats.

## Training system

- **Nine academies, 61 lessons**: Poker Foundations, Preflop Strategy, Flop,
  Turn, River, Poker Mathematics, Exploitative Play, Tournament & Short Stack,
  and Advanced Ranges. Lessons are short by design, gated by prerequisites
  (validated acyclic graph), and each ends in a drill with a mastery
  threshold.
- **Real-engine drills.** Live-decision drills (preflop spots, blind defence,
  push/fold, postflop streets) are generated as genuine `PokerHand` states and
  every answer choice is graded by the same result-independent analyzer that
  grades your recorded play: no parallel mock logic. Knowledge drills
  (hand reading, showdown winners, pot odds, outs, combos) are computed by the
  real evaluator and pot math.
- **Spaced review.** Concept-level review states stretch on success and reset
  on lapses (no punishment for missed days); due concepts surface in the Train
  tab and in recommendations.
- **Daily challenge** (same seeded five-question set for everyone each day,
  first attempt counts, streak tracking) and **endless practice** with focus
  filters (preflop / postflop / river / mathematics / full mix biased toward
  weak concepts).
- **Adaptive recommendations**: confident statistical leaks first, then due
  reviews, then the next unlocked lesson.

## Casino Floor

Three additional offline modes live under Play → Casino Floor, sharing the
design system, audio, haptics, statistics, achievements, save system and
deterministic RNG: never the poker engine itself. Fictional chips only: no
purchases, no ads, no timers, and a free bankroll rebuild whenever a career
bankroll hits zero.

- **Blackjack**: complete rules engine (six-deck shoe, dealer stands on
  soft 17, 3:2 blackjack with exact integer payouts via even bet steps,
  double after split, resplit to four hands, split aces one card, dealer
  peek, configurable H17/DAS/surrender/insurance/decks/penetration), an
  explicit state machine, basic strategy derived from the SAME rule config
  (Guided/Hint/Pure modes plus individual toggles), post-hand mistake
  explanations, and a Hi-Lo counting trainer (card drills, true-count
  conversion, full-shoe simulation). Counting displays are off by default and
  the dealer never reacts to the count.
- **Roulette**: European wheel by default, American optional with its
  higher house edge stated plainly. All standard inside bets (straight,
  split, street, corner, six line) validated against the real layout
  adjacency, all outside bets, exact payouts (35/17/11/8/5/2/2/1 to 1),
  undo/clear/repeat/double, previous-number strip with "each spin is
  independent", and a wheel animation that lands on the seeded authoritative
  pocket: never the other way round.
- **Plinko**: original SpriteKit board (8/12/16 rows, Low/Medium/High
  risk). Outcomes come from a seeded per-ball path model BEFORE animation;
  the ball replays that exact path, so frame rate can never change a payout.
  Multiplier tables are versioned configuration validated for symmetry and a
  small constant house edge (EV 0.989-0.999). Single drops, 5/10-ball
  batches, and auto-drop with profit/loss/bankroll stop conditions that
  halts on backgrounding.
- **Shared fairness**: every round records its seed and shows it afterwards
  with the payout arithmetic; identical seeds and actions reproduce
  identical results; bankroll, streaks and history are structurally unable
  to influence outcomes (tested).
- **Bankrolls**: Practice (unlimited, stats still tracked), Session (fixed
  stake per sitting) and Career (persistent, free rebuild), shared across
  games or independent per game. Optional session safeguards (round/loss/
  profit limits) finish the current round safely and never interrupt
  mid-hand.
- **Floor summary**: cross-game stats keep strategy games (Poker,
  Blackjack) separate from pure-chance games (Roulette, Plinko), with the
  distinction stated in the UI. Twelve casino achievements reward variety
  and skill, never losses or volume.

## Tournaments and progression

- **Sit-and-Go tournaments**: six players, three structures (Standard, Turbo,
  Hyper), hand-based blind levels with antes, correct eliminations and side
  pots, moving button, resume support, final standings with fictional payouts.
- **Exact ICM** (Malmuth-Harville) with tested invariants; bots price
  bubble risk through an ICM risk premium: tournament logic never leaks into
  cash games.
- **Stakes Ladder campaign**: seven tiers from Kitchen Table to Final Table,
  each requiring decision quality over volume (severe-mistake rate, not
  results) plus a themed boss table (The Collector, The Wall, The Flood, The
  Mirror, The Surgeon, The Finalist): strong or unusual, never cheating.
- **Skill rating** (800-1500) from confidence-weighted decision quality with
  per-street breakdowns, honest sample-size confidence and trend.
- **Leak detection**: ten statistical leak definitions (over-limping, blind
  overfolds, c-bet extremes, river overcalls, missed value, push/fold
  passivity…) with baselines, minimum samples and links to the exact lesson
  that fixes each leak.
- **Achievements** (20) for skill and variety milestones: no pure-luck
  trophies. Local only.

## AI and analysis

The bots and the coaching layer share one strategy stack, built for training
rather than theatre:

- **Strict information boundaries.** Every decision reads a `BotObservation`
  that structurally cannot contain another player's cards or the deck;
  mandatory fairness tests prove that changing the hero's hidden cards or the
  future deck order cannot change a bot's decision, and that identical
  observations and seeds decide identically.
- **Exact combination ranges.** 1,326-combo weighted ranges with canonical
  labels, dead-card removal, floors, normalization and deterministic
  sampling; a 169-hand ordering computed offline from real all-in equity.
- **Configured preflop strategy.** Versioned `StrategyConfig` with
  position-based open/call/3-bet/4-bet/defend/squeeze/shove ranges,
  contextual sizing, push/fold bands at short stacks, and bounded archetype
  and difficulty modifiers (Beginner → Elite; six archetypes including
  Maniac, Solid Regular and Trapper).
- **Range-based postflop reasoning.** Opponent range tracking with
  posterior-times-likelihood updates and probability floors; made-hand
  classes, exact relative strength, extended draw detection and numeric
  board features feed candidate-action generation with street-specific
  sizing families and an inspectable score breakdown per candidate.
- **Range-aware equity.** Exact river enumeration versus one range, seeded
  Monte Carlo elsewhere, async with cancellation, plus tested pot-odds math.
- **Result-independent grading.** Every hero decision is re-analyzed after
  the hand by deterministic re-simulation: candidate EVs (noise-free),
  honest confidence levels, Blunder→Excellent/Mixed grades that never judge
  by outcome, deterministic template explanations with concept tags, all
  stored versioned in the hand history (schema v2; v1 saves still load).
- **Bounded adaptation.** Advanced/Elite bots read only observed public
  tendencies (VPIP, PFR, fold-to-c-bet with sample counts) and adjust within
  limits: never instantly, never from hidden information.

None of this claims to be a solved game: Elite is strong approximate
strategy, explicitly beatable, with no hidden-information shortcuts.

## Project layout

```
River.xcodeproj/        Xcode 16 project (file-system-synchronized groups)
River/                  SwiftUI app target (UI, view model, audio, haptics)
RiverUITests/           XCUITest suite (launch with -uitest for determinism)
Packages/RiverKit/      Pure-Swift engine package (no UI dependencies)
  Sources/RiverKit/
    Models/             Cards, deck, deterministic RNG
    Evaluator/          7-card hand evaluator
    Rules/              Betting engine and hand state machine
    Pots/               Exact side-pot construction
    AI/                 Bot profiles, observations, decision logic, equity
    Analysis/           Advisor, grading, statistics, leak detection
    Curriculum/         Lessons, drill engine, daily challenge, spaced review
    Tournament/         Sit-and-Go state machine and exact ICM
    Casino/             Blackjack, Roulette, Plinko engines + bankrolls
    Progression/        Stakes Ladder campaign, skill rating, achievements
    History/            Hand events, histories, replayer
    Session/            Cash session state
    Persistence/        Versioned local JSON store
  Tests/RiverKitTests/  Engine, evaluator, betting, side-pot, chaos tests
```

## Building

Open `River.xcodeproj` in Xcode 16+ and run the `River` scheme on an iPhone or
iPhone simulator (iOS 17+, portrait only).

## Testing

The engine is platform-independent. Run the full suite either from Xcode
(RiverKit scheme) or from the command line:

```
cd Packages/RiverKit
swift test
```

Coverage includes deck uniqueness and shuffle determinism, evaluator edge cases
(cross-checked against a brute-force reference), betting-round completion,
minimum raises, short all-in re-opening rules, heads-up order, side pots, split
pots and odd chips, chip-conservation chaos tests over hundreds of random hands,
replay determinism, hidden-information isolation for bots, session flow and
persistence round-trips, ICM invariants (conservation, monotonicity, sublinear
equity, bubble risk premiums), tournament eliminations/placings/payouts through
real rigged hands, curriculum validation (acyclic prerequisites, quiz
integrity, drill determinism), spaced-review scheduling, campaign completion
rules, leak-detector silence without samples, and achievement evidence.
Casino suites cover the blackjack shoe/totals/actions/settlement/strategy
charts, roulette wheels/bet validation/payouts/overlaps/zeros, Plinko table
validation/determinism/conservation/auto-drop stops, and shared fairness
(seed-only outcomes, wager-independence, bankroll modes, safeguards,
records, achievements).

## Design principles

- The engine is authoritative and deterministic; the UI renders snapshots.
- Chips are integers everywhere. Every chip is accounted for at all times.
- Bots never see hole cards, deck order or future cards.
- Cards are never rigged for drama, comebacks or progression.
- Post-hand analysis judges decisions with the information available at the
  time, not by results.

## Data & privacy

Everything is stored as versioned JSON on the device: settings, sessions,
tournaments, hand histories (configurable retention: 500 / 2,000 / unlimited),
training progress, campaign state and tournament records. Decoding is
field-by-field resilient, so app updates never wipe progress. Hand histories
export as JSON from Profile. Nothing ever leaves the phone.
