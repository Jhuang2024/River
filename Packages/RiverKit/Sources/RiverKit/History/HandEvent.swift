import Foundation

/// Everything that happens during a hand, in order. The event log is the
/// authoritative hand history: replays, the review screen and session results
/// are all derived from it.
public enum HandEvent: Codable, Hashable, Sendable {
    case handStarted(handNumber: Int, button: Int, smallBlind: Int, bigBlind: Int, ante: Int, stacks: [Int])
    case postedAnte(seat: Int, amount: Int)
    case postedSmallBlind(seat: Int, amount: Int)
    case postedBigBlind(seat: Int, amount: Int)
    /// Hole cards are private information: observations built for bots strip
    /// every `dealtHoleCards` event that does not belong to that bot.
    case dealtHoleCards(seat: Int, cards: [Card])
    /// `added` is chips moved into the pot by this action; `toTotal` is the
    /// seat's street commitment afterwards. `isAllIn` marks any action that
    /// leaves the seat with no chips behind.
    case action(seat: Int, street: Street, kind: ActionKind, added: Int, toTotal: Int, isAllIn: Bool)
    case dealtBoard(street: Street, cards: [Card])
    case refundedUncalledBet(seat: Int, amount: Int)
    case wonWithoutShowdown(seat: Int, amount: Int)
    case showedHand(seat: Int, cards: [Card], valueDescription: String)
    /// `potIndex` 0 is the main pot; higher indices are side pots.
    case wonPot(seat: Int, amount: Int, potIndex: Int, handDescription: String)
    case handEnded(finalStacks: [Int], netChips: [Int])
}

extension HandEvent {
    /// True for events that reveal a specific seat's private hole cards.
    public var privateSeat: Int? {
        if case .dealtHoleCards(let seat, _) = self {
            return seat
        }
        return nil
    }
}
