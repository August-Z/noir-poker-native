// English review copy. The reference builds this text in Chinese; the English
// templates here follow the review translation table `scripts/review-copy.mjs`,
// which is the authority (the review fixtures carry its output). Keep both in
// sync. Rules shared with that table:
//   * Chinese sentence fragments become English fragments joined with one space.
//   * Counts written as "N players / opponents" use the singular for exactly 1.
//   * Hand labels, board textures and preflop situations are lower-case catalog
//     phrases mid-sentence and capitalized at the start of a sentence, after
//     ": ", or as standalone values; engine hand names keep their engine form
//     ("Two Pair") when standalone.
//   * Numbers keep the reference formatters (see ReviewFormat).
// Every caveat of the source survives: candidate lines are practice plans, not
// a GTO solution; equities are estimates under assumed ranges; completion cards
// are not guaranteed winners; outcomes never grade decisions; bot explanations
// describe the simulator, not real player psychology.

public enum ReviewCopy {
    typealias F = ReviewFormat

    // MARK: Lookups

    /// `STREET_NAMES`.
    public static let streetNames = ["Preflop", "Flop", "Turn", "River"]

    static let rankPlurals: [Int: String] = [
        2: "Twos", 3: "Threes", 4: "Fours", 5: "Fives", 6: "Sixes", 7: "Sevens", 8: "Eights", 9: "Nines",
        10: "Tens", 11: "Jacks", 12: "Queens", 13: "Kings", 14: "Aces",
    ]
    static func ranks(_ r: Int) -> String { rankPlurals[r] ?? rankText(r) }
    static func article(_ r: Int) -> String { r == 8 || r == 14 ? "an" : "a" }

    static func errorMessage(_ code: ReviewError.Code) -> String {
        switch code {
        case .reviewNotReady: return "You can review a hand only after it ends."
        case .invalidReviewTrials: return "The sample count must be a positive integer."
        case .invalidSimulationTrials: return "The simulation needs at least 2 trials."
        case .simulationRunaway: return "The candidate-action simulation did not finish."
        }
    }

    // MARK: Context

    static func textureTag(_ tag: TextureTag) -> String {
        switch tag {
        case .trips: return "trips on board"
        case .paired: return "paired"
        case .fourFlush: return "four to a flush"
        case .threeFlush: return "three to a flush"
        case .twoTone: return "two-tone"
        case .fourConnected: return "four to a straight"
        case .threeConnected: return "clearly straight-connected"
        }
    }
    static let textureDry = "rainbow and disconnected"

    static func preflopSituation(_ s: PreflopSituation) -> String {
        switch s {
        case .limped: return "unraised, with limpers"
        case .unopened: return "unopened pot"
        case .openWithCallers: return "open with callers"
        case .facingOpen: return "facing an open"
        case .facingThreeBet: return "facing a 3-bet"
        case .facingFourBetPlus: return "facing a 4-bet or more"
        }
    }

    private static let engineHandPhrases: [String: String] = [
        "High Card": "high card", "One Pair": "one pair", "Two Pair": "two pair",
        "Three of a Kind": "three of a kind", "Straight": "a straight", "Flush": "a flush",
        "Full House": "a full house", "Four of a Kind": "four of a kind", "Straight Flush": "a straight flush",
        "Royal Flush": "a royal flush", "Pocket Pair": "a pocket pair",
    ]
    /// An engine hand name: lower-case mid-sentence, engine form standalone.
    static func engineHand(_ label: String) -> HandLabel {
        HandLabel(phrase: engineHandPhrases[label] ?? label.lowercased(), label: label)
    }
    static func pocket(_ r: Int) -> HandLabel { HandLabel(phrase: "pocket \(ranks(r))") }
    static func unpaired(_ ranks: [Int], suited: Bool) -> HandLabel {
        HandLabel(phrase: ranks.map(rankText).joined(separator: "/") + (suited ? " suited" : " offsuit"))
    }
    static let playsBoard = HandLabel(phrase: "a hand that plays the board (hole cards add nothing)")
    static func set(_ r: Int) -> HandLabel { HandLabel(phrase: "a set of \(ranks(r))") }
    static func overpair(_ r: Int, pairedBoard: Bool) -> HandLabel {
        HandLabel(phrase: "an overpair (\(ranks(r)))" + (pairedBoard ? ", on a paired board" : ""))
    }
    static func underpair(_ r: Int) -> HandLabel { HandLabel(phrase: "pocket \(ranks(r)) with an overcard on board") }
    static func boardPair(_ r: Int) -> HandLabel { HandLabel(phrase: "a board pair of \(ranks(r)), hole cards as kickers") }
    static func pair(top: Bool, rank: Int, kicker: Int) -> HandLabel {
        HandLabel(phrase: "\(top ? "top pair" : "second-or-lower pair") (\(rankText(rank))) with \(article(kicker)) \(rankText(kicker)) kicker")
    }

    // MARK: Plurals

    static func players(_ n: Int) -> String { F.count(n, "player", "players") }
    static func opponents(_ n: Int) -> String { F.count(n, "opponent", "opponents") }
    static func cards(_ n: Int) -> String { F.count(n, "direct completion card", "direct completion cards") }

    // MARK: Analysis: shared sentences

    static func priced(_ price: CallPrice) -> String {
        "Effective call cost \(F.number(price.cost)); after calling you can win \(F.number(price.contestable)); break-even equity is about \(F.percent(price.required))."
    }
    static func estimated(_ random: Double, _ weighted: Double) -> String {
        "Pot equity is about \(F.percent(random)) against a random range and \(F.percent(weighted)) against an action-weighted range."
    }

    // Confidence.
    static let confidenceRange = "Depends on range assumptions"
    static let confidenceRules = "Clear by rules and cost"
    static let confidenceSensitive = "Sensitive to ranges and later strategy; no single best line shown"
    static let confidenceSimulated = "Both range samples agree, but later play is still a model"

    // free-fold
    static let freeFoldTitle = "Folding when checking was free gave up a free chance"
    static func freeFoldReason(_ position: String, _ pendingOthers: Int) -> String {
        "You were in \(position) and it cost 0 to continue. Checking keeps your equity in the hand without adding chips; " +
            (pendingOthers != 0 ? "\(players(pendingOthers)) behind can still act." : "there's no bet to match this round.")
    }
    static let freeFoldLesson = "Take the free check first; evaluate the price if someone bets later."
    static let freeFoldPlan = "If someone bets next, recalculate with the new amount and player count; don't commit in advance to calling down."

    // late-open / late-isolation
    static let lateIsolationTitle = "Late-position isolation raise: account for the number of limpers and how often they call"
    static let lateOpenTitle = "Late-position open is backed by position and fold equity"
    static func lateReason(_ hand: HandLabel, _ position: String, limpers: Int, amount: Int, ace: Bool, weakAce: Bool,
                           kicker: Int) -> String {
        F.sentences(
            "\(hand.label) in \(position), \(limpers != 0 ? "facing \(F.count(limpers, "limper", "limpers"))" : "folded to you with no open in front"); you raised to \(F.number(amount)) (\(jsToFixed(Double(amount) / 50, 1)) BB).",
            ace
                ? "Your ace blocks some AA, AK, and AQ combos, and late position allows a wider opening range than early position."
                : "Late position can attack the blinds with a wider range and have position postflop.",
            "Raising folds out some weak connectors and high cards, and the payoff includes fold equity; once called, the remaining range may be stronger" +
                (weakAce ? ", and A\(kicker) that makes top pair is still easily dominated by a better ace kicker" : "") + ".",
            limpers != 0
                ? "This is an isolation raise; it's only a squeeze when there's an open plus a caller."
                : "This is an open / steal, not a squeeze.")
    }
    static let lateLesson = "Judge whether a hand can open separately from whether it can call a re-raise; ace-high is neither a reason to fold nor a reason to call down."
    static func latePlan(limpers: Bool) -> String {
        F.sentences(
            limpers
                ? "When limpers call a lot, size up your isolation raises and tighten your range; after a multiway call, cut back on pressure with no clear reason."
                : "Compare 2–3 BB opens: a smaller size makes stealing cheaper and a larger size adds immediate pressure, depending on how the blinds continue.",
            "Consider defending in position only against small, wide-range 3-bets; tighten up first against large sizes or 4-bets. Postflop, play top pair with a weak kicker mainly for pot control, and when you miss, decide whether to continuation-bet based on the board and the opponent's range.")
    }

    // weak-threebet-defense / weak-fourbet-defense
    static let weakFourBetTitle = "Defending a weak hand against multiple re-raises lacks support"
    static let weakThreeBetTitle = "A hand you can open isn't automatically a hand that can call a 3-bet"
    static func weakDefenseReason(_ hand: HandLabel, _ position: String, _ situation: PreflopSituation, currentBet: Int,
                                  ratio: Double, priced: String, estimated: String, ownOpen: Bool, weakAce: Bool,
                                  pendingOthers: Int) -> String {
        F.sentences(
            "\(hand.label) in \(position), \(situation.phrase); the latest bet is \(F.number(currentBet)), about \(jsToFixed(ratio, 1))× the previous one.",
            priced, estimated,
            ownOpen ? "Your earlier open was reasonable, but this call is a new, separate decision." : nil,
            weakAce
                ? "Stronger Ax dominates your kicker, and the ace blocker alone isn't enough to justify a large call."
                : "A weak hand is dominated by strong ranges and has no reliable way to realize its equity postflop.",
            pendingOthers != 0 ? "\(players(pendingOthers)) behind can still act again." : nil)
    }
    static let weakFourBetLesson = "Chips already put in with your open and call are not a reason to call a 4-bet."
    static let weakThreeBetLesson = "Separate your stealing range from your range for defending against re-raises; check sizing, position, flush potential, and how wide the opponent is."
    static let weakFourBetPlan = "Facing multiple raises without evidence of a wide range, stop adding chips first; revisit defending only with clear evidence of an extremely wide range and a good price."
    static func weakThreeBetPlan(suited: Bool) -> String {
        "The alternative is a small in-position call, but it needs a wide enough 3-bet range and a margin on price" +
            (suited ? "; flush potential helps you realize equity" : "; an offsuit weak ace needs stricter conditions to defend") +
            ". At low SPR or under large sizing, don't continue just to see a flop."
    }

    // late-passive-entry
    static let latePassiveTitle = "From late position, compare opening rather than going by hand tier alone"
    static func latePassiveReason(_ hand: HandLabel, _ position: String, ace: Bool, limped: Bool) -> String {
        F.sentences(
            "\(hand.label) in \(position), with no one in the pot yet.",
            ace
                ? "Your ace blocks some strong Ax, and late position allows attacking the blinds more widely."
                : "Postflop position and room for opponents to fold support comparing an open.",
            limped
                ? "A plain limp lets the blinds see a cheap flop and gives up fold equity."
                : "Folding avoids putting chips in, but also gives up the chance to attack the blinds from late position.",
            "This doesn't mean you should continue if raised; adjust separately when the blinds are sticky or effective stacks are short.")
    }
    static let latePassiveLesson = "Treat opening and calling a re-raise as two separate sets of conditions to continue."
    static let latePassivePlan = "Compare a 2–3 BB open with your conservative line; against a large 3-bet or a 4-bet, tighten up first with a weak ace. With top pair and a weak kicker, don't automatically get all your chips in."

    // squeeze-candidate
    static let squeezeTitle = "A squeeze needs a range that will fold; the ace blocker is only one factor"
    static func squeezeReason(_ hand: HandLabel, _ position: String, callers: Int, amount: Int) -> String {
        "\(hand.label) in \(position), after an open and \(F.count(callers, "call", "calls")); re-raising to \(F.number(amount)) is a squeeze. The ace blocks some strong ace combos, which helps when choosing bluffs, but an offsuit weak ace can still be dominated by stronger Ax once called. Whether to squeeze depends on whether the opener is wide enough, whether the callers will fold, and whether you can stop in time when facing a 4-bet."
    }
    static let squeezeLesson = "Thinning the field doesn't prove a profit; evaluate immediate fold equity separately from hand strength once someone continues."
    static let squeezePlan = "Without evidence about opponent ranges and folding tendencies, tighten up first; with evidence of wide opens or callers who fold, replay the hand to compare an in-position squeeze with a fold, and don't treat holding an ace as an automatic reason to attack."

    // early-suited-entry
    static let earlySuitedTitle = "Marginal suited hand in early position: opening depends on how players behind defend"
    static func earlySuitedReason(_ hand: HandLabel, _ position: String, pendingOthers: Int, smallKicker: Bool) -> String {
        "\(hand.label) is genuinely suited and has flush potential; don't treat it like a weak offsuit hand. You're in \(position) with \(players(pendingOthers)) still to act. " +
            (smallKicker
                ? "With a small kicker, top pair is easily dominated by the same high card with a better kicker, and flush potential"
                : "Flush potential") +
            " doesn't remove the pressure of being out of position and facing re-raises. A standard tight range can fold here; if players behind are clearly too tight and rarely 3-bet, you can compare a small open to exploit their folds."
    }
    static let earlySuitedLesson = "Weigh suitedness, position, kicker, and defending tendencies together; don't enter just because a hand has \"a high card / is suited,\" and don't call it a mistake based on tier alone."
    static let earlySuitedPlan = "Put this open and a fold into the candidate-action simulation to see which line does better as opponent ranges change. Tighten up against a 3-bet, play top pair with a weak kicker for pot control, and judge flush draws on the actual price and what they'll have to pay later."

    // weak-entry
    static let weakEntryEarlyTitle = "Entering with a weak hand from early position lacks positional support"
    static let weakEntryOpenTitle = "Facing an open, check the price and the risk of domination first"
    static func weakEntryReason(_ hand: HandLabel, _ position: String, callAmount: Int, pendingOthers: Int, early: Bool,
                                suited: Bool) -> String {
        F.sentences(
            "You hold \(hand.phrase) in \(position) and need \(F.number(callAmount)) to continue; \(players(pendingOthers)) can still act.",
            early
                ? "Early position lacks a positional advantage, " +
                    (suited
                        ? "and flush potential still carries kicker, connectivity, and re-raise risk."
                        : "and marginal offsuit hands have a harder time realizing equity.")
                : "There's already a raise in front, which raises the risk of a weak hand being dominated by a better top pair or a higher kicker.")
    }
    static let weakEntryLesson = "Opening, flatting an open, and defending against a re-raise need different ranges; don't judge by starting-hand tier alone."
    static let weakEntryPlan = "If you later face a very small raise in the big blind, judge it again on price; \"weak hand\" doesn't automatically mean \"must fold.\""

    // deep-value-shove
    static let deepShoveTitle = "Shoving a strong hand deep-stacked may cut off value"
    static func deepShoveReason(_ hand: HandLabel, extra: Int, pot: Int, betRatio: Double, effective: Int) -> String {
        "\(hand.label) has value, but this put in an extra \(F.number(extra)) (about \(F.roundedInt(Double(extra) / 50)) BB), \(jsToFixed(betRatio, 1))× the pot of \(F.number(pot)) at the time; the effective stack was about \(F.roundedInt(Double(effective) / 50)) BB. That much pressure can fold out worse hands that would call a normal raise, so a strong hand alone doesn't make shoving best."
    }
    static let deepShoveLesson = "Compare a normal open or re-raise with the shove first, so weaker ranges have a chance to pay you."
    static func deepShovePlan(_ label: String) -> String {
        "Practice the line \(label) first; if an opponent re-raises, decide whether to continue based on their range and the effective stack. This size is a practice candidate and isn't guaranteed to earn more."
    }

    // expensive-call
    static let expensiveClosingTitle = "This call's price isn't supported by equity"
    static let expensiveTitle = "The call is expensive, and later pressure adds to it"
    static func expensiveReason(_ hand: HandLabel, opponents n: Int, priced: String, estimated: String,
                                draw: DrawInfo) -> String {
        F.sentences(
            "You had \(hand.phrase) against \(opponents(n)) still in the hand.", priced, estimated,
            draw.outs != 0
                ? "You have \(cards(draw.outs)), about \(F.percent(draw.nextChance)) to hit on the next card; completing can still lose to a stronger hand."
                : nil)
    }
    static let expensiveClosingLesson = "Under both assumptions the price is higher than the estimated equity, so lean toward not putting in more."
    static let expensiveLesson = "Equity measured to showdown isn't the equity you can actually realize; after calling you may have to pay again."
    static let expensiveClosingPlan = "This call ends your betting decisions, so focus on whether the opponent has enough bluffs; future winnings can't justify it."
    static func expensivePlan(pendingOthers: Int) -> String {
        "\(players(pendingOthers)) behind may still act; if you call, set your exit conditions for a re-raise or a bad turn first."
    }

    // premium-fold
    static let premiumFoldTitle = "Folding a premium hand needs the betting pressure to explain it"
    static func premiumFoldReason(_ hand: HandLabel, currentBet: Int, callAmount: Int, effective: Int,
                                  preflopRaises: Int) -> String {
        F.sentences(
            "You held \(hand.phrase); the bet was \(F.number(currentBet)) and you needed \(F.number(callAmount)) more, with about \(F.roundedInt(Double(effective) / 50)) BB effective; there had been \(F.count(preflopRaises, "preflop raise", "preflop raises")) this hand.",
            preflopRaises >= 2
                ? "Multiple re-raises narrow the opponent's range, so the \"premium hand\" label alone doesn't make the fold wrong."
                : "Under normal pressure, this hand is usually worth continuing; compare a call and a re-raise.")
    }
    static let premiumFoldLesson = "Judge a strong hand together with the actual betting strength; avoid automatic shoves or automatic folds."
    static let premiumFoldPlanReraised = "Focus on whether this is a wide-range fight or a strong range with few bluffs; without enough evidence, leave the conclusion open for discussion."
    static let premiumFoldPlan = "Replay this hand and compare raising with calling."

    // premium-flat
    static let premiumFlatTitle = "With a premium hand, compare building the pot"
    static func premiumFlatReason(_ hand: HandLabel, _ position: String, callAmount: Int, opponents n: Int,
                                  pendingOthers: Int, raised: Bool) -> String {
        F.sentences(
            "\(hand.label) called \(F.number(callAmount)) in \(position); \(opponents(n)) \(n == 1 ? "is" : "are") still in and \(pendingOthers) can still act.",
            raised
                ? "Against an existing raise, flatting keeps the opponent's range wide but may also make the pot multiway."
                : "In an unraised pot, just calling lets others in cheaply.")
    }
    static let premiumFlatLesson = "Raise for value while keeping alternatives like a trapping flat; choose based on opponent tendencies."
    static func premiumFlatPlan(_ label: String) -> String {
        "The practice candidate is \(label); if someone raises again, this suggestion doesn't automatically extend to getting all your chips in."
    }

    // large-unbacked-bet
    static let largeRiverTitle = "A big river bet needs a clear idea of which hands will fold"
    static let largeTitle = "A big investment without clear hand strength or a draw to back it"
    static func largeReason(_ hand: HandLabel, extra: Int, betRatio: Double, opponents n: Int, missedDraw: Bool,
                            nutFlushBlocker: Bool) -> String {
        F.sentences(
            "You had \(hand.phrase) and bet an extra \(F.number(extra)), about \(jsToFixed(betRatio, 1))× the pot; \(opponents(n)) hadn't folded.",
            missedDraw ? "Your earlier draw missed on the river." : nil,
            nutFlushBlocker
                ? "You hold the ace of that suit, which blocks some nut flushes, but that doesn't mean the opponent will fold."
                : "No nut-flush ace blocker was detected, so don't assume the opponent will fold often.")
    }
    static let largeLesson = "Give your bluff a clear target range instead of making up for a weak hand with a huge size."
    static let largePlan = "Without evidence of the opponent's folding tendencies, compare a check or a smaller line first; the exact value of the bluff isn't calculated here."

    // value-check
    static let valueCheckTitle = "Compare this check with a value bet"
    static func valueCheckReason(_ hand: HandLabel, _ texture: BoardTexture, opponents n: Int, inPosition: Bool,
                                 overpair: Bool) -> String {
        F.sentences(
            "You had \(hand.phrase) on a board that's \(texture.phrase), with \(opponents(n)) left.",
            inPosition ? "You have position and act last." : "You act before the remaining opponents, and checking keeps an inducing line open.",
            overpair
                ? "An overpair can get value from worse pairs and some draws, but don't ignore stronger made hands."
                : "Your made hand has value potential; whether checking is better still depends on how often opponents call and bet on their own.")
    }
    static let valueCheckWetLesson = "Weigh value against protection: make worse made hands and draws pay, while keeping a plan for facing a raise."
    static let valueCheckDryLesson = "On a dry board, consider a smaller value size that leaves room for worse hands to continue."
    static func valueCheckPlan(_ label: String) -> String {
        "Compare with \(label); if raised, reassess how many strong hands the raiser has, and don't read \"can bet\" as \"must continue.\""
    }

    // multiway-top-pair
    static let multiwayTitle = "Top pair on a wet multiway board must realize equity carefully"
    static func multiwayReason(_ hand: HandLabel, opponents n: Int, _ texture: BoardTexture, priced: String,
                               estimated: String) -> String {
        F.sentences(
            "\(hand.label) against \(opponents(n)) on a board that's \(texture.phrase).", priced, estimated,
            "In a multiway pot, one pair's showdown value is more easily caught by two pair, trips, or draws.")
    }
    static let multiwayLesson = "Keep judging by price, and lean less toward treating top pair as an all-in value hand."
    static let multiwayPlan = "If you face another big bet next street, recalculate on the new board; having called once isn't a reason to keep calling."

    // tight-fold
    static let tightFoldTitle = "This fold may be too tight; worth rechecking ranges"
    static func tightFoldReason(_ hand: HandLabel, priced: String, estimated: String) -> String {
        F.sentences(
            "You had \(hand.phrase).", priced, estimated,
            "Under both range assumptions your equity beats the price with room to spare, but that hasn't been shown for the opponent's real range.")
    }
    static let tightFoldLesson = "Separate an opponent who is actually strong from simply being afraid to lose; without enough range evidence, keep both lines in mind."
    static let tightFoldClosingPlan = "Focus on the opponent's value and bluff combinations; don't rely on implied odds from later streets."
    static let tightFoldPlan = "If you call, plan for bad cards and re-raises first, and don't treat all of your current equity as realizable."

    // priced-fold
    static let pricedFoldTitle = "Recheck this fold against the price and risk at the time"
    static func pricedFoldReason(_ hand: HandLabel, _ position: String, callAmount: Int, texture: BoardTexture?,
                                 priced: String?, draw: DrawInfo) -> String {
        F.sentences(
            "You held \(hand.phrase) in \(position) and needed \(F.number(callAmount)) more.",
            texture.map { "The board is \($0.phrase)." },
            priced,
            draw.outs != 0
                ? "You have \(cards(draw.outs)), about \(F.percent(draw.nextChance)) on the next card, which doesn't guarantee a win."
                : "No direct straight or flush draw was detected.")
    }
    static let pricedFoldLesson = "Base your exit conditions on the current price, hand strength, and position; chips already in the pot are no reason you must continue."
    static let pricedFoldPlan = "When replaying, you can compare another line, but good cards that come later don't prove you should have called."

    // priced-call / multi-street-call
    static let multiStreetTitle = "After calling several streets, evaluate the current price on its own"
    static let pricedCallTitle = "This call depends on price and your ability to realize equity"
    static func pricedCallReason(_ hand: HandLabel, opponents n: Int, priced: String, estimated: String,
                                 pastCalls: Int, draw: DrawInfo) -> String {
        F.sentences(
            "You held \(hand.phrase), with \(opponents(n)) still in.", priced, estimated,
            pastCalls >= 2
                ? "You already called on \(F.count(pastCalls, "earlier street", "earlier streets")); past investment doesn't increase your equity now."
                : nil,
            draw.outs != 0 ? "\(F.cap(cards(draw.outs))), about \(F.percent(draw.nextChance)) on the next card." : nil)
    }
    static let pricedCallClosingLesson = "There are no later bets to save chips for, so focus on comparing range assumptions with the price."
    static let pricedCallLesson = "Having room on the price doesn't mean you can call down automatically; further action and equity realization are still risky."
    static let pricedCallClosingPlan = "Recalculate this call against different opponent ranges and see whether the conclusion holds."
    static func pricedCallPlan(pendingOthers: Int) -> String {
        "Watch the \(players(pendingOthers)) who can still act, and whether the next card brings a stronger straight or flush texture."
    }

    // value-bet / draw-bet / pressure-bet
    static let valueBetTitle = "This bet has value targets you can check"
    static let drawBetTitle = "Betting with a draw: also consider your equity when called"
    static let pressureBetTitle = "The payoff from applying pressure depends on what folds"
    static func betReason(_ hand: HandLabel, extra: Int, betRatio: Double, texture: BoardTexture?, opponents n: Int,
                          draw: DrawInfo, valueTarget: Bool) -> String {
        F.sentences(
            "\(hand.label): put in an extra \(F.number(extra)), about \(F.percent(betRatio)) of the pot; the board is \(texture?.phrase ?? "not dealt yet"), with \(opponents(n)) still in.",
            draw.outs != 0
                ? "You also have \(cards(draw.outs)), about \(F.percent(draw.nextChance)) on the next card."
                : valueTarget
                    ? "You can try to get value from worse hands; which hands the opponent will call with still needs judging."
                    : "No direct straight or flush draw was detected, so don't assume you have enough chances to improve when called.")
    }
    static let valueBetLesson = "List the specific worse hands that will pay; a hand's name doesn't prove the best size."
    static let pressureBetLesson = "First work out which opponent ranges will fold, then judge whether you can continue when called."
    static let shortAllInPlan = "This is an all-in for less than a full raise, so it doesn't necessarily reopen raising for players who have already acted."
    static let betPlan = "If re-raised, compare the price and ranges again; if called, plan a new value or exit line for the next street's board."

    // board-check / draw-check / pot-control
    static let boardCheckTitle = "The board makes the hand; your hole cards add nothing"
    static let drawCheckTitle = "Checking keeps the draw without growing the pot early"
    static let potControlTitle = "This check controls the pot"
    static func checkReason(_ hand: HandLabel, _ texture: BoardTexture, draw: DrawInfo, pendingOthers: Int) -> String {
        F.sentences(
            "You had \(hand.phrase) on a board that's \(texture.phrase), with nothing to call.",
            draw.outs != 0
                ? "You have \(cards(draw.outs)), about \(F.percent(draw.nextChance)) on the next card; checking means you don't pay extra for that chance."
                : pendingOthers != 0
                    ? "\(players(pendingOthers)) can still act after you, so checking doesn't guarantee a free card."
                    : "You can see the next card or go to showdown.")
    }
    static let checkLesson = "After checking, still separate a free chance from your conditions for continuing against a bet."
    static let checkPlan = "If someone bets, recalculate with the actual amount; if the board alone makes the hand, think about a split first and don't invent an edge from your hole cards."

    // Simulation override.
    static func simulationReason(_ label: String) -> String {
        "In the candidate-action simulation, \(label) showed a fairly clear chip advantage under both ranges and is worth practicing instead of the original heuristic suggestion; the edge depends on the simulated follow-up strategy and doesn't prove optimal play."
    }
    static let simulationPlan = "When replaying, compare the simulation pick with the original line first; if opponents defend very differently, analyze again."
    static func simulationSummary(_ label: String) -> String { "Simulation pick: \(label)" }
    static let simulationCondition = "When this hand's public styles, the two starting ranges, and the balanced follow-up strategy are representative of your practice games."
    static let simulationTradeoff = "The samples support comparing this first, but real continuing ranges and better follow-up play could still change the ranking."
    static let simulationPreviousCondition = "When opponent ranges or the follow-up strategy change, keep the original conservative / value line as a comparison."
    static let simulationPreviousTradeoff = "Judge using the numbers below and the specific conditions; a simulated lead doesn't mean you must take that line."

    // Evidence.
    static func evidencePosition(_ position: String, opponents n: Int, street: Int, inPosition: Bool) -> String {
        "Position \(position) · \(opponents(n)) in the hand" + (street != 0 ? " · " + (inPosition ? "In position" : "Not last to act") : "")
    }
    static func evidenceHand(_ hand: HandLabel) -> String { "Hand at the time: \(hand.label)" }
    static func evidenceBoard(_ texture: BoardTexture) -> String { "Board: \(texture.label)" }
    static func evidencePreflop(raises: Int, pendingOthers: Int) -> String {
        "Preflop raises: \(raises) · Still to act: \(pendingOthers)"
    }
    static func evidenceStack(effective: Int, spr: Double) -> String {
        "Effective stack ≈ \(F.number(effective)) · SPR \(jsToFixed(spr, 1))"
    }
    static func evidenceDraw(_ draw: DrawInfo) -> String {
        "Direct completion cards: \(draw.outs) (deduplicated) · ≈\(F.percent(draw.nextChance)) on the next card, not a win rate"
    }
    static func evidenceSituation(_ pre: PreflopContext) -> String {
        "Preflop situation: \(pre.situation.label) · Limpers: \(pre.limpers)" +
            (pre.ace ? " · An ace blocker isn't an edge once called" : "")
    }

    // MARK: Routes

    static let routeKeep = "Keep this line; adjust to opponent ranges"
    static let routeCondition = "Based on what was known at the time; reassess if ranges change."
    static let routeTradeoff = "Candidate actions don't account for the value of a full future strategy."
    static let routeIsolateSummary = "Isolate; scale the size to the number of limpers"
    static let routeOpenSummary = "Keep the late-position open; compare 2–3 BB sizes"
    static let routeIsolateCondition = "Limpers have wide ranges, and no obviously strong range has shown up behind."
    static let routeOpenCondition = "No one has opened, the blinds fold often enough to exploit, and you'll have position postflop."
    static let routeLateTradeoff = "Fights for the blinds at a controlled cost; once called, stop treating the opponent's hand as random."
    static let routeLateAltCondition = "When replaying, try the other open size and note how often the blinds continue; use a larger size to isolate sticky limpers."
    static let routeLateAltTradeoff = "A smaller size risks less when it fails but lets more hands defend; a larger size adds pressure but may leave only stronger ranges."
    static let routeEarlySummary = "Tight baseline: fold; compare a conditional small open"
    static let routeEarlyCondition = "From early position with several players still to act and no evidence that opponents overfold, avoid building a pot with marginal suited hands."
    static let routeEarlyTradeoff = "Gives up flush potential and steal value in exchange for less out-of-position and kicker risk."
    static let routeEarlyAltCondition = "When players behind defend too tightly, rarely 3-bet, and you can control the pot or get out once someone continues."
    static let routeEarlyAltTradeoff = "Attacks the blinds, but stronger Qx/Kx and re-raises make the flush potential hard to realize; the simulation only compares lines under that assumption."
    static let routeSqueezeCondition = "Without evidence that the opener is wide and the callers will fold, tighten up first."
    static let routeSqueezeTradeoff = "Keeps a weak ace from being dominated by strong continuing ranges; blocking some strong aces doesn't guarantee enough folds."
    static let routeSqueezeAltCondition = "Compare a squeeze only when the opener is wide, the callers look capped, and opponents will fold to a re-raise."
    static let routeSqueezeAltTradeoff = "Wins multiway dead money, but costs more when it fails; after a call or a 4-bet, stop applying pressure without a reason."
    static let routeWeakCondition = "Against large sizes, multiple players continuing, or strong ranges with few bluffs, put in as little new money as possible."
    static let routeWeakTradeoff = "Gives up current equity to avoid weak-kicker trouble and later pressure; chips already invested are not a reason to continue."
    static let routeWeakAltConditionFourBet = "Worth discussing only with clear evidence of an extremely wide range and a favorable price and closing action; it doesn't apply against normal strong ranges."
    static let routeWeakAltCondition = "Consider it only against a small size and wide range, with position or a big-blind discount; don't assume it by default."
    static let routeWeakAltTradeoff = "Keeps showdown equity, but the risk of domination by stronger Ax and of facing later bets remains."
    static let routeRaisePressureCondition = "Clearly better hands will fold, and the folds this size generates make up for weak equity when called."
    static let routeRaiseDrawCondition = "The draw has equity when called, and the target range folds often enough."
    static let routeRaiseValueCondition = "You can name worse hands that will pay, and you're prepared to reassess if raised."
    static let routeRaiseTradeoff = "Builds the pot and protects equity; the bigger the size, the stronger the continuing range may be."
    static let routeRaiseAltConditionInPosition = "When the opponent's range is strong or the board is unfavorable, use position to control how much you put in."
    static let routeRaiseAltCondition = "When the opponent will bet on their own or you lack position, keep an induce / pot-control line."
    static let routeRaiseAltTradeoff = "Keeps the pot smaller, but may give draws a free card or miss value."
    static let routeFoldCondition = "The current price isn't supported by equity, or the equity is hard to realize."
    static let routeFoldTradeoff = "Stops adding chips now; good cards that come later don't make the fold wrong."
    static let routeFoldAltCondition = "Only when a wider range, enough bluffs, or a better price would give an equity margin."
    static let routeFoldAltTradeoff = "Tests range sensitivity; it doesn't mean the call is already justified."
    static let routeCallCondition = "The opponent's range and the price leave enough margin, and later pressure is manageable."
    static let routeCallTradeoff = "Keeps your range wide and avoids turning thin-value hands into a raise that only gets called by stronger hands."
    static let routeCallAltCondition = "When the opponent's value range is narrower, someone behind may re-raise, or you can't afford later bets."
    static let routeCallAltTradeoff = "Gives up some equity for lower risk; having called one street isn't a reason to keep calling."
    static let routeCheckConditionInPosition = "Use last action to see what happens, control the pot with marginal made hands, or keep a free draw."
    static let routeCheckCondition = "Without the last-to-act advantage, watch the opponent's bets and how the board develops first."
    static let routeCheckTradeoff = "Saves chips; it doesn't guarantee a free card, so you still need a plan for later bets."
    static let routeCheckAltDrawCondition = "Compare a semi-bluff when the opponent folds enough and your draw can handle being called."
    static let routeCheckAltCondition = "When there are clear worse hands that call, or the opponent will fold better hands; without evidence, keep checking."
    static let routeCheckAltTradeoff = "Gains value or fold equity but is exposed to calls and raises; it hasn't been shown to earn more."

    // MARK: Counterfactual

    static let scenarioRandom = "Random range"
    static let scenarioWeighted = "Public-action-weighted range"
    static let simulationNote = "Unknown cards are sampled from the position at the time, and each hand is played out with the opponents' public styles; your later decisions use the balanced bot strategy, with 8 equity samples per decision. The figures estimate net chip change under this simulated strategy, treat chips already invested as sunk, and include split pots, refunds, and later betting. The error shown is approximate sampling error and does not cover errors in the range or strategy model. This is not GTO or a real player's optimal EV."

    // MARK: Summary

    static let noDecisions = "You made no decisions this hand; forced blinds can't count as mistakes."
    static let noMistakes = "No obvious decision mistakes found"
    static func checkFirst(_ title: String) -> String { "Check first: \(title)" }
    static func worthComparing(_ title: String) -> String { "Worth comparing: \(title)" }
    static func summary(decisions: Int, extra: Int, step: Int, street: String, title: String, otherThemes: Int) -> String {
        F.sentences(
            "\(F.count(decisions, "decision", "decisions")), \(F.number(extra)) chips put in. Start with step \(step) (\(street)): \(title).",
            otherThemes > 0 ? "\(F.count(otherThemes, "other issue", "other issues")) to look through step by step." : nil)
    }

    // MARK: Opponents

    /// `BOT_REASON_NAMES`, by trace reason code.
    public static let botReasonNames: [String: String] = [
        "outside-range": "Hand outside this defending range",
        "insufficient-equity": "Estimated equity below the calling threshold",
        "stack-pressure": "Stack pressure triggered a tighter range",
        "loose-exception": "Random leeway kept a marginal action",
        "premium-continue": "Premium-hand branch kept it in",
        "affordable-entry": "Low-cost entry range kept it in",
        "affordable-open": "Small open's price and effective stack supported calling",
        "price-continue": "Passed the price and pressure checks",
        "value-raise": "Raising range triggered aggression",
        "semi-bluff": "Draw triggered a semi-bluff",
        "pure-bluff": "Bluff roll triggered pressure",
        "trap": "Strong hand on a dry board triggered a trap check",
        "free-check": "Took a free look / pot control",
    ]
    /// `BOT_CHECK_NAMES`, by roll-check code.
    public static let botCheckNames: [String: String] = botReasonNames.merging([
        "outside-range": "Leeway roll when outside range",
        "insufficient-equity": "Leeway roll when equity is short",
        "stack-pressure": "Leeway roll under high pressure",
        "attack": "Aggression frequency roll",
        "trap": "Trap-check roll",
        "rare-pocket-shove": "Rare small-pair shove roll",
    ]) { _, new in new }

    /// `BOT_REASON_NAMES[code]`; an unknown code reads `undefined`, like the reference.
    static func reasonName(_ code: String) -> String { botReasonNames[code] ?? "undefined" }
    static func reasonList(_ codes: [String]) -> String {
        codes.map { F.lowerFirst(reasonName($0)) }.joined(separator: ", ")
    }

    static func opponentRange(percentile: Double, range: Double, admitted: Bool, premium: Bool) -> String {
        "Starting-hand rank: about top \(F.pct(percentile)); this style, position, and the public raising line allow the top \(F.pct(range)). It \(admitted ? "was inside" : "was outside") that range\(premium ? ", and it also triggered the top-7% premium branch" : ""). The ranking is a starting-hand heuristic, not a win rate."
    }
    static func opponentPrice(rivals: Int, callAmount: Int, contestable: Int, odds: Double) -> String {
        "It faced \(opponents(rivals)) still in, needed \(F.number(callAmount)) to call, could win \(F.number(contestable)) in the model, and needed \(F.pct(odds)) equity to call."
    }
    static func opponentExceptions(_ codes: [String]) -> String {
        "It had triggered \(reasonList(codes)), but a leeway roll kept it in before it reached the current action branch; don't ignore this risk just because of the final value / bluff label."
    }
    static let opponentCheapEntry = "It passed the low-cost entry branch, so the normal equity fold check didn't run; the equity and threshold below are only the values computed at the time, not what triggered this action."
    static func opponentAffordableOpen(effectiveBehind: Int, openCallers: Int, playable: Bool) -> String {
        "There was only one small open this street; the effective stack behind after calling was about \(F.number(Double(effectiveBehind) / 50)) BB, with \(F.count(openCallers, "caller", "callers")) already in. \(playable ? "The postflop potential of a pair or a suitable suited hand" : "Its starting-hand rank and the current price") put it into a separate calling range, so the usual fold check on random-hand showdown equity across the table didn't run. This approximation doesn't prove the call is profitable."
    }
    static func opponentEquity(trials: Int, raw: Double, noise: Double, equity: Double, tolerance: Double,
                               comparison: Double, threshold: Double) -> String {
        "Using only its own cards and the board, it sampled random opponent ranges \(trials) times: raw estimate \(F.pct(raw)), judgment noise \(F.signedPct(noise)), equity used \(F.pct(equity)). Calling-tendency shift \(F.signedPct(tolerance)), compared value \(F.pct(comparison)); the usual threshold, including a 2-point buffer, was \(F.pct(threshold))."
    }
    static func opponentLoose(_ codes: [String], call: Bool) -> String {
        "It originally triggered \(reasonList(codes)), but a random leeway roll kept it in. So this \(call ? "call" : "action") is a deliberately loose mistake built into the model; it can't be read as the odds proving it worth continuing."
    }
    static let opponentPremium = "It classed this hand as a premium starting hand and skipped the normal equity and high-pressure fold checks preflop; this is a model approximation and doesn't mean an all-in should be called at any player count or price."
    static let opponentAffordableEntry = "This was a low-cost entry into an unraised pot, costing at most one more BB. The hand was in an entry range widened by position and style, so it didn't mechanically fold by comparing multiway showdown equity against random hands with the immediate blind odds; this is no reason to call a big raise or an all-in."
    static let opponentAffordableOpenDetail = "This was a conditional call against a single small open: the open was no more than 4 BB, the extra cost was small, the opener wasn't all-in, and the effective stack behind after calling was still deep enough. Position, style, hand playability, and the callers already in set the candidate range. Calling and re-raising are decided separately; 3-bets, large bets, and short stacks don't get this exemption."
    static let opponentPriceContinue = "No fold branch was triggered. If it didn't raise, the aggression roll missed, there was no suitable target, or raising was no longer allowed. Passing the program's checks doesn't mean the play is profitable against the real continuing range."
    static func opponentPreflopValue(reraise: Bool, range: Double) -> String {
        "The hand was in the \(reraise ? "separate value re-raise" : "open / isolation raise") candidate range (about the top \(F.pct(range))), or triggered the premium branch, and the aggression roll hit, so it built the pot. Marginal hands allowed to flat don't automatically re-raise just because the entry range widened, and the label doesn't mean the nuts."
    }
    static func opponentPostflopValue(threshold: Double) -> String {
        "Equity against a random range was above \(F.pct(threshold)), or it met \"overpair with more than 40% equity,\" and the aggression roll hit. A made hand isn't required; even ace-high can land in this branch under a wide-range estimate. If the opponent's continuing range is strong, this estimate may be too optimistic."
    }
    static let opponentSemiBluff = "It saw that it had a draw, with no more than three players in the hand, and both the semi-bluff and aggression rolls hit. The payoff includes fold equity; its completion cards may still not be clean winning outs."
    static let opponentPureBluff = "It saw pressure conditions (late position / continuing aggression / a fairly dry board), its stack pressure was under 25%, and both the bluff and aggression rolls hit. It didn't read your hole cards and doesn't prove you would fold."
    static let opponentTrap = "With a free check, a dry board, and estimated equity above 65%, it hit the trap branch, leaving room for opponents to bet."
    static let opponentFreeCheck = "It had nothing to call, didn't raise, and took a free look. A check doesn't mean it was weak; the aggression roll may simply have missed."
    static func opponentExecuted(_ code: String) -> String {
        "Actually executed: \(F.lowerFirst(reasonName(code))). Cards dealt later were not used to decide this step."
    }
    static func opponentDraw(_ draw: DrawInfo) -> String {
        "It saw \(F.count(draw.outs, "direct straight / flush completion card", "direct straight / flush completion cards")), \(F.pct(draw.nextChance)) to hit on the next card; that is not a probability of winning."
    }
    static func opponentMood(_ kind: MoodKind, reason: String, base: [Int], axes: [Double]) -> String {
        func baseAxis(_ i: Int) -> String { base.indices.contains(i) ? String(base[i]) : "undefined" }
        func axis(_ i: Int) -> String { axes.indices.contains(i) ? jsNumberString(axes[i]) : "undefined" }
        return "Simulated mood: \(kind.label). Trigger: \(reason.isEmpty ? "an event in an earlier hand" : reason). Base / actual looseness \(baseAxis(0)) / \(axis(0)), aggression \(baseAxis(1)) / \(axis(1)), calling \(baseAxis(3)) / \(axis(3)); whether this state changed the action still depends on the branches above."
    }
    static let opponentNoMood = "No mood shift this time; base style settings were used."
    static func opponentSizingBlocked(actual: Int, call: Bool) -> String {
        "It tried to raise to \(F.number(actual)), but that hit the safeguard against max-size pure-bluff shoves, so the raise wasn't made; the actual action is still the \(call ? "call" : "check") recorded above."
    }
    static func opponentSizing(_ sizing: BotSizing) -> String {
        F.sentences(
            "Sizing first produced a total of \(F.number(sizing.desired)), then was clamped to the legal range \(F.number(sizing.minimum))–\(F.number(sizing.maximum)), giving \(F.number(sizing.actual)).",
            sizing.opening
                ? "In an unraised pot, it uses the open / number-of-limpers formula."
                : "Sizing factor about \(F.pct(sizing.fraction)) × (pot at the time + call amount), plus the current total bet.")
    }
    static let opponentPreflopMade = "Preflop hand"
    static let opponentWarning = "Be especially careful with this continue: the bot estimated against a random range and didn't fully narrow it for your raising line; small samples, the premium-hand exemption, or random leeway can all produce unreasonable calls. The record explains why it happened; it doesn't prove the play was right."
    static let opponentNote = "This is the decision record the simulator actually used at the time. Equity is a small-sample estimate against a random range; it doesn't fully model the opponent's continuing range, equity realization, or future strategy. It is not a real pro's thinking and not proof of optimal play."
}
