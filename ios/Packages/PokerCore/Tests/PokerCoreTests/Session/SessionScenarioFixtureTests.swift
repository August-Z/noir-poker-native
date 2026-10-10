import Foundation
import XCTest
@testable import PokerCore

/// Replays `fixtures/session-scenarios.json`: scripted session commands on a
/// virtual clock with a seeded stream, checking render-state excerpts after
/// each `expect` step. The Kotlin `SessionScenarioFixtureTest` consumes the same
/// file with the same projection (`fixtures/README.md` → `session-scenarios.json`).
final class SessionScenarioFixtureTests: XCTestCase {
    func testSessionScenariosMatchTheSharedFixture() throws {
        let fixture = try loadFixture("session-scenarios.json")
        let scenarios = try XCTUnwrap(fixture["scenarios"] as? [[String: Any]])
        XCTAssertFalse(scenarios.isEmpty)
        var failures: [String] = []
        for scenario in scenarios {
            let name = scenario["name"] as! String
            let runner = ScenarioRunner(scenario)
            for (index, step) in (scenario["steps"] as! [[String: Any]]).enumerated() {
                let label = "\(name) · step \(index)"
                guard let expect = step["expect"] else {
                    try runner.run(step, label)
                    continue
                }
                let actual = runner.project()
                runner.h.effects.removeAll()
                var diffs: [String] = []
                matchPartial(expect, actual, "", &diffs)
                if !diffs.isEmpty { failures.append("\(label):\n  " + diffs.prefix(20).joined(separator: "\n  ")) }
            }
        }
        if !failures.isEmpty { XCTFail(failures.joined(separator: "\n")) }
    }
}

/// Expected values are partial: objects check only their keys, arrays check
/// length and each element; numbers compare numerically.
func matchPartial(_ expected: Any, _ actual: Any?, _ path: String, _ out: inout [String]) {
    func show(_ v: Any?) -> String {
        guard let v else { return "<absent>" }
        if v is NSNull { return "null" }
        if let s = v as? String { return "\"\(s)\"" }
        return "\(v)"
    }
    switch expected {
    case let e as [String: Any]:
        guard let a = actual as? [String: Any] else { out.append("\(path): expected an object, got \(show(actual))"); return }
        for key in e.keys.sorted() {
            if let v = a[key] { matchPartial(e[key]!, v, "\(path).\(key)", &out) } else { out.append("\(path).\(key): missing") }
        }
    case let e as [Any]:
        guard let a = actual as? [Any], a.count == e.count else {
            out.append("\(path): expected \(e.count) elements, got \(show(actual))")
            return
        }
        for i in e.indices { matchPartial(e[i], a[i], "\(path)[\(i)]", &out) }
    case is NSNull:
        if !(actual is NSNull) { out.append("\(path): expected null, got \(show(actual))") }
    case let e as String:
        if (actual as? String) != e { out.append("\(path): expected \(show(e)), got \(show(actual))") }
    case let e as Bool:
        if !(actual is Bool) || (actual as? Bool) != e { out.append("\(path): expected \(e), got \(show(actual))") }
    default:
        let en = (expected as? Int).map(Double.init) ?? (expected as? Double)
        let an = actual is Bool ? nil : ((actual as? Int).map(Double.init) ?? (actual as? Double))
        if en == nil || an != en { out.append("\(path): expected \(show(expected)), got \(show(actual))") }
    }
}

/// Runs one scenario's commands against a `Harness` and projects its state.
final class ScenarioRunner {
    let h: Harness
    let storage: InMemoryStorage
    let reviewRunner: FakeReviewRunner?

    init(_ scenario: [String: Any]) {
        storage = InMemoryStorage((scenario["storage"] as? [String: Any])?.mapValues { $0 as! String } ?? [:])
        reviewRunner = (scenario["reviewRunner"] as? Bool) == true ? FakeReviewRunner() : nil
        h = Harness(seed: fixtureInt(scenario["seed"]), storage: storage, runner: reviewRunner)
    }

    func run(_ step: [String: Any], _ label: String) throws {
        let s = h.session
        let op = step["do"] as! String
        func int(_ key: String) -> Int { fixtureInt(step[key]) }
        func str(_ key: String) -> String { step[key] as! String }
        var result: Bool?
        switch op {
        case "start": s.start()
        case "nextHand": result = s.nextHand()
        case "replayHand": result = s.replayHand()
        case "startNewSession": s.startNewSession()
        case "finishHand": result = s.finishHand()
        case "fold": result = s.fold()
        case "callOrCheck": result = s.callOrCheck()
        case "raise": result = step["amount"].map { s.raise(fixtureInt($0)) } ?? s.raise()
        case "setBet": s.setBet(int("value"))
        case "nudgeBet": s.nudgeBet(int("steps"))
        case "preset": result = s.preset(BetPreset(rawValue: str("preset"))!)
        case "toggleReveal": result = s.toggleReveal(int("seat"))
        case "setSeatCount": result = s.setSeatCount(int("count"))
        case "setDifficulty": s.setDifficulty(Difficulty(rawValue: str("difficulty"))!)
        case "toggleHints": s.toggleHints()
        case "toggleSound": s.toggleSound()
        case "openOpponentSettings": s.openOpponentSettings()
        case "previewProfile": s.previewProfile(str("id"))
        case "assignSeatStyle": s.assignSeatStyle(int("seat"), str("profile"))
        case "setEmotionMode": s.setEmotionMode(EmotionMode(rawValue: str("mode"))!)
        case "mixLineup": s.mixLineup()
        case "saveOpponentSettings": result = s.saveOpponentSettings()
        case "discardOpponentSettings": s.discardOpponentSettings()
        case "openPotDetails": s.openPotDetails()
        case "closePotDetails": s.closePotDetails()
        case "togglePotDistribution": s.togglePotDistribution(int("index"))
        case "openReview": s.openReview()
        case "closeReview": s.closeReview()
        case "completeReview": reviewRunner!.started.last!.sink.complete(FakeAnalysis(priorityIndex: int("priorityIndex")))
        case "background": s.onBackground()
        case "foreground": s.onForeground()
        case "advance": h.scheduler.advance(by: int("ms"))
        case "runCurrent": h.scheduler.runCurrent()
        case "runBots": h.runBots()
        case "runUntilIdle": h.scheduler.runUntilIdle()
        case "stop": h.hooks.stop()
        case "resumeBots": h.hooks.resumeBots()
        case "playOut": try playOut(str("hero"), label)
        case "qa": try qa(step)
        default: XCTFail("\(label): unknown command \(op)")
        }
        if let expected = step["returns"] as? Bool {
            XCTAssertEqual(result, expected, "\(label): \(op) return value")
        }
    }

    /// Runs bots on the virtual clock; on each hero turn takes `heroAction`
    /// (`fold` or `callOrCheck`), until the hand is over.
    private func playOut(_ heroAction: String, _ label: String) throws {
        for _ in 0..<200 {
            h.runBots()
            let g = h.game
            if g.phase == .done { return }
            if g.phase == .playing && g.actor == 0 {
                if heroAction == "fold" { h.session.fold() } else { h.session.callOrCheck() }
            } else if h.scheduler.nextDueAt == nil {
                XCTFail("\(label): playOut stalled")
                throw TestFailure()
            }
        }
        XCTFail("\(label): playOut did not finish")
        throw TestFailure()
    }

    private func qa(_ step: [String: Any]) throws {
        func int(_ key: String, _ fallback: Int) -> Int { step[key].map(fixtureInt) ?? fallback }
        func bool(_ key: String) -> Bool { (step[key] as? Bool) ?? false }
        switch step["fixture"] as! String {
        case "heroTurn": try h.heroTurn(int("count", 6), unequal: bool("unequal"))
        case "bettingTurn": try h.bettingTurn(int("level", 2), int("street", 0), short: bool("short"))
        case "foldFinished": try h.foldFinished(int("street", 0))
        case "allinRest": try h.allinRest()
        case "respondToHero": try h.respondToHero(int("raiseTo", 0), nextStreet: bool("nextStreet"))
        case "river": try h.river(int("count", 6))
        case "retainedRiver": try h.retainedRiver(int("count", 6))
        case "finish": try h.finish()
        case "foldWin": try h.foldWin(int("count", 6), winner: int("winner", int("count", 6) - 1))
        case "foldRest": try h.foldRest()
        case "foldPotRefund": try h.foldPotRefund(int("count", 6))
        case "scene":
            let others = (step["otherHoles"] as? [String: Any] ?? [:]).reduce(into: [Int: String]()) { $0[Int($1.key)!] = ($1.value as! String) }
            try h.scene(step["hole"] as! String, step["board"] as! String, count: int("count", 6),
                        totals: (step["totals"] as? [Any])?.map(fixtureInt),
                        folded: (step["folded"] as? [Any])?.map(fixtureInt) ?? [], otherHoles: others)
        case let name: XCTFail("unknown QA fixture \(name)")
        }
    }

    // MARK: Projection (the shape documented in fixtures/README.md)

    func project() -> [String: Any] {
        let thinking = h.hooks.thinking()
        return [
            "state": state(h.state),
            "clock": h.scheduler.nowMs,
            "pending": h.scheduler.pendingCount,
            "nextDueAt": orNull(h.scheduler.nextDueAt),
            "draws": h.random.draws,
            "thinking": thinking.map { ["actor": $0.actor, "delayMs": $0.delayMs, "startedAt": $0.startedAt, "deadline": $0.deadline] as [String: Any] } ?? jsonNull,
            "effects": h.effects.map(effect),
            "storage": storage.values,
            "wealth": h.tableWealth(),
            "epoch": h.session.epoch,
            "viewToken": h.session.viewToken,
            "canFinishHand": h.session.canFinishHand(),
        ]
    }

    private func effect(_ e: SessionEffect) -> String {
        switch e {
        case .sound(let kind): return "sound:\(kind.rawValue)"
        case .chipFlight(let seat): return "chipFlight:\(seat)"
        case .cancelChipFlights: return "cancelChipFlights"
        case .revealToggled(let seat, let visible): return "revealToggled:\(seat):\(visible)"
        }
    }

    private func state(_ st: TableRenderState) -> [String: Any] {
        let a = st.actions
        let r = st.review
        let se = st.settings
        let pd = st.potDetails
        return [
            "hand": st.hand, "handNumber": st.handNumber, "handHeading": st.handHeading, "playerCount": st.playerCount,
            "tableTag": st.tableTag, "tableSize": st.tableSize, "hasFullPlayerNames": st.hasFullPlayerNames,
            "phase": st.phase.rawValue, "street": st.street, "streetLabel": st.streetLabel, "dealer": st.dealer,
            "replayAttempt": st.replayAttempt, "replayBadge": orNull(st.replayBadge), "replayNote": orNull(st.replayNote),
            "pot": st.pot, "potText": st.potText, "potPulse": st.potPulse, "potButtonLabel": st.potButtonLabel,
            "potButtonA11y": st.potButtonA11y,
            "board": st.board.map { slot -> [String: Any] in
                ["card": orNull(slot.card?.card.key), "best": slot.card?.best ?? false, "animate": slot.card?.animate ?? false,
                 "delayMs": slot.card?.delayMs ?? 0, "a11y": slot.a11y]
            },
            "boardCaption": st.boardCaption, "practiceRunout": st.practiceRunout,
            "seats": st.seats.map(seat),
            "hero": [
                "name": st.hero.name, "cards": st.hero.cards.map(face), "rankBadge": badge(st.hero.rankBadge),
                "folded": st.hero.folded, "isActive": st.hero.isActive, "stack": st.hero.stack, "stackText": st.hero.stackText,
                "position": st.hero.position.code, "positionName": st.hero.position.name, "turnText": orNull(st.hero.turnText),
                "lastAction": st.hero.lastAction.map(chip) as Any? ?? jsonNull,
            ] as [String: Any],
            "session": [
                "stack": st.session.stack, "stackText": st.session.stackText, "changeText": st.session.changeText,
                "negative": st.session.negative, "hands": st.session.hands, "wins": st.session.wins, "winRateText": st.session.winRateText,
            ] as [String: Any],
            "activity": [
                "badge": st.activity.badge,
                "texts": st.activity.entries.map(\.text),
                "entries": st.activity.entries.map { e -> [String: Any] in
                    ["number": e.number, "text": e.text, "type": e.type.rawValue, "playerId": orNull(e.playerId), "isHero": e.isHero,
                     "street": e.street, "personas": e.segments.filter(\.isPersona).map(\.text)]
                },
            ] as [String: Any],
            "actions": [
                "decisionStripVisible": a.decisionStripVisible, "decisionText": a.decisionText, "controlsVisible": a.controlsVisible,
                "foldEnabled": a.foldEnabled, "callEnabled": a.callEnabled, "callLabel": a.callLabel, "callAmount": orNull(a.callAmount),
                "callA11y": a.callA11y, "raiseEnabled": a.raiseEnabled, "raiseCaption": a.raiseCaption, "bet": a.bet, "betText": a.betText,
                "raiseA11y": a.raiseA11y, "sliderMin": orNull(a.sliderMin), "sliderMax": orNull(a.sliderMax),
                "presets": a.presets.map { ["preset": $0.preset.rawValue, "label": $0.label, "amount": orNull($0.amount), "enabled": $0.enabled] as [String: Any] },
                "nextHandVisible": a.nextHandVisible, "nextHandLabel": a.nextHandLabel, "finishHandVisible": a.finishHandVisible,
                "finishHandEnabled": a.finishHandEnabled, "finishHandLabel": a.finishHandLabel, "replayVisible": a.replayVisible,
                "replayLabel": a.replayLabel, "reviewVisible": a.reviewVisible, "reviewLabel": a.reviewLabel,
            ] as [String: Any],
            "coach": ["visible": st.coach.visible, "toggleLabel": st.coach.toggleLabel, "stage": st.coach.stage, "tip": st.coach.tip] as [String: Any],
            "showdown": st.showdown.map { sd -> Any in
                ["key": sd.key, "context": sd.context, "scenes": sd.scenes.map { sc -> [String: Any] in
                    ["id": sc.scene.id, "name": sc.nameSegments.plainText, "label": sc.scene.label, "motion": sc.scene.motion.rawValue,
                     "cards": sc.scene.cards.map(\.key), "highlights": sc.scene.highlights, "explanation": sc.scene.explanation,
                     "amount": sc.scene.amount, "isWinner": sc.isWinner, "statusText": sc.statusText, "footerText": sc.footerText, "a11y": sc.a11y]
                }]
            } ?? jsonNull,
            "potDetails": [
                "open": pd.open, "settled": pd.settled, "title": pd.title, "note": orNull(pd.note),
                "pots": pd.pots.map { p -> [String: Any] in
                    ["index": p.index, "label": p.label, "amount": p.amount, "amountText": p.amountText,
                     "eligibilityLabel": p.eligibilityLabel, "heroEligible": p.heroEligible,
                     "contributions": p.contributions.map { ["playerId": $0.playerId, "text": $0.text, "amount": $0.amount] as [String: Any] },
                     "splitTotalText": orNull(p.splitTotalText),
                     "awards": p.awards.map { ["playerId": $0.playerId, "name": $0.name, "winnerText": $0.winnerText, "label": $0.label, "amountText": $0.amountText] as [String: Any] },
                     "distributionEligibility": p.distributionEligibility, "oddChipNote": orNull(p.oddChipNote), "expanded": p.expanded,
                     "playerCountText": p.playerCountText, "participantsText": p.participantsText]
                },
                "refunds": pd.refunds.map { ["playerId": $0.playerId, "amount": $0.amount, "text": $0.text, "a11y": orNull($0.a11y), "returned": $0.returned] as [String: Any] },
            ] as [String: Any],
            "opponents": ["text": st.opponents.text, "changePending": st.opponents.changePending, "changeNote": orNull(st.opponents.changeNote)] as [String: Any],
            "opponentsDialog": st.opponentsDialog.map { d -> Any in
                ["emotionMode": d.emotionMode.rawValue, "selectedProfile": d.selectedProfile, "detailName": d.detail.profile.name,
                 "sizingText": d.detail.sizingText,
                 "roster": d.roster.map { ["id": $0.id, "name": $0.name, "offTable": $0.offTable, "subtitle": $0.subtitle,
                                           "assignment": $0.assignment, "currentStyle": $0.currentStyle, "observed": $0.observed] as [String: Any] }]
            } ?? jsonNull,
            "review": [
                "buttonVisible": r.buttonVisible, "dialogOpen": r.dialogOpen, "key": orNull(r.key), "status": r.status.rawValue,
                "progress": r.progress, "selected": r.selected, "perspective": r.perspective.rawValue, "jobId": r.jobId,
                "decisions": r.input?.decisions.count ?? 0, "opponentRecords": r.opponentRecords.count,
            ] as [String: Any],
            "settings": [
                "requestedSeatCount": se.requestedSeatCount, "tableChangeNote": orNull(se.tableChangeNote),
                "difficulty": se.difficulty.rawValue, "hints": se.hints, "sound": se.sound, "soundA11y": se.soundA11y,
                "soundTitle": se.soundTitle, "seatCountOptions": se.seatCountOptions.map(\.label),
                "difficultyOptions": se.difficultyOptions.map(\.label), "emotionOptions": se.emotionOptions.map(\.label),
            ] as [String: Any],
            "finishing": st.finishing,
            "backgrounded": st.backgrounded,
        ]
    }

    private func seat(_ p: SeatState) -> [String: Any] {
        [
            "id": p.id, "name": p.name, "layoutX": p.layoutX, "layoutY": p.layoutY, "position": p.position.code,
            "positionName": p.position.name, "folded": p.folded, "isActor": p.isActor, "isWinner": p.isWinner,
            "revealed": p.revealed, "cards": p.cards.map(face), "cardBacks": p.cardBacks, "dealAnimation": p.dealAnimation,
            "cardBackDelaysMs": p.cardBackDelaysMs, "badge": badge(p.badge), "avatar": p.avatar, "avatarTitle": p.avatarTitle,
            "profileId": p.profileId, "styleShort": p.styleShort, "styleTitle": p.styleTitle, "styleA11y": p.styleA11y,
            "mood": p.mood.rawValue, "moodLabel": p.moodLabel, "stack": p.stack, "stackText": p.stackText,
            "peek": p.peek.map { ["pressed": $0.pressed, "title": $0.title, "a11y": $0.a11y] as [String: Any] } ?? jsonNull,
            "action": chip(p.action), "actionA11y": p.actionA11y,
        ]
    }

    private func chip(_ c: ActionChip) -> [String: Any] {
        ["label": c.label, "amount": orNull(c.amount), "amountText": orNull(c.amountText), "meaning": orNull(c.meaning), "isDeciding": c.isDeciding]
    }

    private func badge(_ r: RankBadge?) -> Any {
        r.map { ["text": $0.text, "isWinner": $0.isWinner, "a11y": orNull($0.a11y), "title": orNull($0.title)] as [String: Any] } ?? jsonNull
    }

    private func face(_ c: CardFace) -> [String: Any] {
        ["card": c.card.key, "best": c.best, "animate": c.animate, "delayMs": c.delayMs]
    }
}
