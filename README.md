# RIVER

A serious, offline No-Limit Texas Hold'em simulator and training system for iPhone,
disguised as a fast, tense mobile game. Fictional chips only — nothing to buy,
no ads, no accounts, no network.

## Current status — Phase 1 (first playable milestone)

- Six-max cash game: you + five AI opponents, blinds 1/2, 200-chip (100 BB) stacks
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
- Deterministic seeded shuffling — inspect any hand's deck seed after the fact
- Synthesized sound, haptics, four-color deck option, speed controls

## Project layout

```
River.xcodeproj/        Xcode 16 project (file-system-synchronized groups)
River/                  SwiftUI app target (UI, view model, audio, haptics)
Packages/RiverKit/      Pure-Swift engine package (no UI dependencies)
  Sources/RiverKit/
    Models/             Cards, deck, deterministic RNG
    Evaluator/          7-card hand evaluator
    Rules/              Betting engine and hand state machine
    Pots/               Exact side-pot construction
    AI/                 Bot profiles, observations, decision logic, equity
    Analysis/           Advisor and session statistics
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
persistence round-trips.

## Design principles

- The engine is authoritative and deterministic; the UI renders snapshots.
- Chips are integers everywhere. Every chip is accounted for at all times.
- Bots never see hole cards, deck order or future cards.
- Cards are never rigged for drama, comebacks or progression.
- Post-hand analysis judges decisions with the information available at the
  time, not by results.

## Roadmap

Phase 2: interactive tutorial, guided beginner drills, richer post-hand review.
Phase 3: weighted ranges, stronger postflop AI, more archetypes and difficulties.
Phase 4: six-player sit-and-go tournaments with push/fold training and ICM.
Phase 5: stakes ladder, skill rating, leak detection, focused trainers.
Phase 6: elite AI, opponent adaptation, customization, accessibility, export.
