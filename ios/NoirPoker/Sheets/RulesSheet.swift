import SwiftUI

/// How to Play (reference `rules-dialog`), with the English copy catalog text.
struct RulesSheet: View {
    let onClose: () -> Void

    private let actions: [(String, String)] = [
        ("Fold", "Give up the hand; chips already bet stay in the pot."),
        ("Check / Call", "Check when there's nothing to call; otherwise match the current bet."),
        ("Bet / Raise", "Choose your total for this betting round; it must be at least the minimum raise."),
        ("All-In", "Put in all your remaining chips; side pots are calculated automatically when stacks differ."),
    ]

    var body: some View {
        NoirSheet(eyebrow: "QUICK GUIDE", title: "Five minutes to a seat at the table.", onClose: onClose) {
            SheetParagraph("Each player gets two hole cards and combines them with five community cards to make the best five-card hand. The table defaults to 6 players, with 5–9 available, and every game uses virtual chips.")
            flow
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .topLeading)], alignment: .leading, spacing: 12) {
                ForEach(actions.indices, id: \.self) { index in
                    let item = actions[index]
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.0).noirFont(14, .semibold, relativeTo: .headline).foregroundStyle(Noir.text)
                        Text(item.1).noirFont(13, relativeTo: .body).foregroundStyle(Noir.dialogBody)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(Color(hex: "#182630"), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityElement(children: .combine)
                }
            }
            Group {
                SheetHeading("Positions and Action Order")
                SheetParagraph("This table plays No-Limit Hold'em with 5–9 players and 25 / 50 blinds. The seat after the button is the SB and the next is the BB; the other positions depend on table size. At a 6-player table, clockwise order is BTN, SB, BB, UTG, HJ, CO. The button moves one seat clockwise after every hand.")
                SheetParagraph("Preflop action starts with the player after the BB; if nobody raises, the big blind can still check or raise last. After a raise, action continues until every player who hasn't folded or gone all-in has matched the bet and acted. On the flop, turn, and river, action starts with the first player left of the button who hasn't folded or gone all-in, and moves clockwise.")
                SheetParagraph("The minimum bet is 50. A raise must increase the bet by at least the size of the last full bet or raise in this round. Less than the minimum is only possible as an all-in, and an all-in short of a full raise does not reopen raising for players who already acted and haven't faced a full raise.")
                SheetHeading("Replaying a Hand")
                SheetParagraph("After a hand ends, tap \u{201C}Replay Hand\u{201D} to keep everyone's hole cards, the button, starting stacks, and the upcoming deal order, and make your decisions again from preflop. The original settlement and this hand's stats are reversed and replaced by the latest result. The computer responds to your new choices, so winning more is not guaranteed; this is strategy practice on a known hand.")
            }
            SheetHeading("Hand Rankings, Strongest First")
            Text("Straight Flush · Four of a Kind · Full House · Flush · Straight · Three of a Kind · Two Pair · One Pair · High Card")
                .noirFont(13, relativeTo: .body)
                .foregroundStyle(Noir.dialogBody)
                .lineSpacing(8)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Rectangle().fill(Noir.selectBorder).frame(height: 1)
                Group {
                    Text("BTN = Button · SB = Small Blind · BB = Big Blind")
                    Text("Use any five of your hole cards and the community cards, including playing the board. Identical hands and kickers split the pot; suits never break ties. Each side pot is settled separately, and any uncalled excess is returned.")
                    Text("Computer players decide using only their own hole cards and public information. Tips are a basic practice aid.")
                }
                .noirFont(12, relativeTo: .footnote)
                .foregroundStyle(Noir.subtle)
                .fixedSize(horizontal: false, vertical: true)
            }
            Button("Back to Table", action: onClose)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)
        }
    }

    private var flow: some View {
        HStack(spacing: 6) {
            ForEach(Array(["Hole cards", "Flop: 3 cards", "Turn: 1 card", "River: 1 card"].enumerated()), id: \.offset) { i, step in
                if i > 0 { Text("·").foregroundStyle(Color(hex: "#557366")) }
                Text(step).foregroundStyle(Noir.mint)
            }
        }
        .noirFont(12, relativeTo: .caption)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
    }
}
