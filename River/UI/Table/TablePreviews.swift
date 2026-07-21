#if DEBUG
import SwiftUI
import RiverKit

/// Deterministic mock data for design previews (§48). Never used at runtime.
@MainActor
enum PreviewData {

    static func seat(_ id: Int, name: String, symbol: String, stack: Int, committed: Int = 0,
                     folded: Bool = false, allIn: Bool = false, acting: Bool = false, button: Bool = false,
                     blind: String? = nil, position: String = "UTG", hero: Bool = false,
                     cards: [Card]? = nil, action: String? = nil, won: Int = 0) -> SeatUIState {
        return SeatUIState(
            id: id, name: name, symbolName: symbol, stack: stack, committed: committed,
            hasFolded: folded, isAllIn: allIn, isActing: acting, isButton: button,
            blindLabel: blind, position: position, isHero: hero,
            visibleCards: cards, hasCards: !folded, lastAction: action, netWon: won
        )
    }

    static func table(board: [Card], pot: Int, street: Street, heroCards: [Card], acting: Int = 0,
                      seats: [SeatUIState]? = nil) -> TableUIState {
        let defaultSeats = [
            seat(0, name: "You", symbol: "person.fill", stack: 197, button: true, blind: nil,
                 position: "BTN", hero: true, cards: heroCards),
            seat(1, name: "Marta", symbol: "eyeglasses", stack: 214, committed: 1, blind: "SB", position: "SB"),
            seat(2, name: "Gus", symbol: "cup.and.saucer.fill", stack: 180, committed: 2, blind: "BB", position: "BB"),
            seat(3, name: "Dana", symbol: "bolt.fill", stack: 305, committed: 6, position: "UTG", action: "Raises to 6"),
            seat(4, name: "Ivan", symbol: "clock.fill", stack: 92, folded: true, position: "HJ", action: "Folds"),
            seat(5, name: "Rex", symbol: "flame.fill", stack: 255, position: "CO", action: "Calls 6")
        ]
        var allSeats = seats ?? defaultSeats
        for i in allSeats.indices {
            if allSeats[i].id == acting {
                allSeats[i] = seat(allSeats[i].id, name: allSeats[i].name, symbol: allSeats[i].symbolName,
                                   stack: allSeats[i].stack, committed: allSeats[i].committed,
                                   folded: allSeats[i].hasFolded, allIn: allSeats[i].isAllIn, acting: true,
                                   button: allSeats[i].isButton, blind: allSeats[i].blindLabel,
                                   position: allSeats[i].position, hero: allSeats[i].isHero,
                                   cards: allSeats[i].visibleCards, action: allSeats[i].lastAction,
                                   won: allSeats[i].netWon)
            }
        }
        return TableUIState(
            seats: allSeats, board: board, pot: pot, street: street,
            handNumber: 7, handsTarget: 20, smallBlind: 1, bigBlind: 2, ante: 0,
            statusText: street.name, isHandComplete: false, tournamentLine: nil
        )
    }

    static func gameModel(table: TableUIState, actions: AvailableActions?, boardVisible: Int) -> GameViewModel {
        let store = PersistenceStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("river-previews-\(UUID().uuidString)", isDirectory: true))
        let model = GameViewModel(store: store, sounds: SoundPlayer(), haptics: HapticsPlayer(), settingsProvider: { AppSettings() })
        model.applyPreviewState(table: table, heroActions: actions, boardVisible: boardVisible)
        return model
    }

    static var settings: SettingsStore {
        let store = PersistenceStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("river-previews-settings-\(UUID().uuidString)", isDirectory: true))
        return SettingsStore(store: store)
    }
}

#Preview("Facing a raise · preflop") {
    let table = PreviewData.table(
        board: [], pot: 9, street: .preflop,
        heroCards: [Card(.ace, .spades), Card(.king, .spades)]
    )
    let actions = AvailableActions(
        seat: 0, canFold: true, canCheck: false, callCost: 6, fullAmountOwed: 6,
        betRaise: BetRaiseOptions(kind: .raise, minTo: 10, minFullTo: 10, maxTo: 197)
    )
    TableView(game: PreviewData.gameModel(table: table, actions: actions, boardVisible: 0))
        .environmentObject(PreviewData.settings)
}

#Preview("Flop decision") {
    let table = PreviewData.table(
        board: [Card(.king, .spades), Card(.eight, .diamonds), Card(.four, .clubs)],
        pot: 21, street: .flop,
        heroCards: [Card(.king, .hearts), Card(.queen, .hearts)]
    )
    let actions = AvailableActions(
        seat: 0, canFold: true, canCheck: true, callCost: 0, fullAmountOwed: 0,
        betRaise: BetRaiseOptions(kind: .bet, minTo: 2, minFullTo: 2, maxTo: 195)
    )
    TableView(game: PreviewData.gameModel(table: table, actions: actions, boardVisible: 3))
        .environmentObject(PreviewData.settings)
}

#Preview("River all-in decision") {
    let allInSeats = [
        PreviewData.seat(0, name: "You", symbol: "person.fill", stack: 150, acting: true, blind: "BB",
                         position: "BB", hero: true, cards: [Card(.queen, .clubs), Card(.queen, .diamonds)]),
        PreviewData.seat(1, name: "Marta", symbol: "eyeglasses", stack: 214, folded: true, position: "UTG"),
        PreviewData.seat(2, name: "Gus", symbol: "cup.and.saucer.fill", stack: 180, folded: true, position: "HJ"),
        PreviewData.seat(3, name: "Dana", symbol: "bolt.fill", stack: 0, committed: 96, allIn: true,
                         position: "CO", action: "All-in 96"),
        PreviewData.seat(4, name: "Ivan", symbol: "clock.fill", stack: 92, folded: true, button: true, position: "BTN"),
        PreviewData.seat(5, name: "Rex", symbol: "flame.fill", stack: 255, folded: true, blind: "SB", position: "SB")
    ]
    let table = PreviewData.table(
        board: [Card(.king, .spades), Card(.eight, .diamonds), Card(.four, .clubs), Card(.two, .hearts), Card(.nine, .spades)],
        pot: 168, street: .river,
        heroCards: [Card(.queen, .clubs), Card(.queen, .diamonds)],
        seats: allInSeats
    )
    let actions = AvailableActions(seat: 0, canFold: true, canCheck: false, callCost: 96, fullAmountOwed: 96, betRaise: nil)
    TableView(game: PreviewData.gameModel(table: table, actions: actions, boardVisible: 5))
        .environmentObject(PreviewData.settings)
}

#Preview("Bet sizing sheet") {
    BetSizingSheet(
        options: BetRaiseOptions(kind: .bet, minTo: 2, minFullTo: 2, maxTo: 195),
        pot: 21, callCost: 0, myCommitted: 0, myStack: 195, bigBlind: 2,
        currentBet: 0, street: .flop, accent: AccentChoice.amber.color,
        onConfirm: { _ in }, onCancel: {}
    )
    .padding()
    .background(Theme.background)
}

#Preview("Action bar · left-handed") {
    VStack(spacing: 20) {
        ActionBar(
            actions: AvailableActions(seat: 0, canFold: true, canCheck: false, callCost: 12, fullAmountOwed: 12,
                                      betRaise: BetRaiseOptions(kind: .raise, minTo: 24, minFullTo: 24, maxTo: 200)),
            accent: AccentChoice.electricBlue.color,
            leftHanded: false,
            onFold: {}, onCheck: {}, onCall: {}, onOpenBetSheet: {}
        )
        ActionBar(
            actions: AvailableActions(seat: 0, canFold: true, canCheck: false, callCost: 12, fullAmountOwed: 12,
                                      betRaise: BetRaiseOptions(kind: .raise, minTo: 24, minFullTo: 24, maxTo: 200)),
            accent: AccentChoice.electricBlue.color,
            leftHanded: true,
            onFold: {}, onCheck: {}, onCall: {}, onOpenBetSheet: {}
        )
    }
    .padding()
    .background(Theme.background)
}
#endif
