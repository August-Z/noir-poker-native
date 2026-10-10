import XCTest
@testable import PokerCore

/// A table session on a virtual clock with in-memory storage.
final class Harness {
    let scheduler = ManualScheduler()
    let random: CountingRandom
    let storage: InMemoryStorage
    let session: TableSession
    var effects: [SessionEffect] = []

    init(seed: Int = 42, storage: InMemoryStorage = InMemoryStorage(), runner: ReviewRunner? = nil) {
        random = CountingRandom(SeededRandom(seed: seed))
        self.storage = storage
        session = TableSession(scheduler: scheduler, storage: storage, random: random, reviewRunner: runner)
        session.effectListener = { [unowned self] in self.effects.append($0) }
    }

    var hooks: TableSession.TestHooks { session.testHooks }
    var game: Game { session.testHooks.game }
    var state: TableRenderState { session.state }

    func tableWealth() -> Int {
        game.players.reduce(0) { $0 + $1.stack } + (game.phase == .done ? 0 : potSize(game))
    }

    /// Advances virtual time until the hero must act or the hand is over.
    func runBots(maxMs: Int = 120_000) {
        let limit = scheduler.nowMs + maxMs
        while scheduler.nowMs < limit {
            if game.phase == .done { return }
            if game.phase == .playing && game.actor == 0 { return }
            guard let next = scheduler.nextDueAt else { return }
            scheduler.advance(to: next)
        }
    }

    // The reference QA fixtures (`tests/fixtures/table-fixtures.js`), driving the real session.

    func heroTurn(_ count: Int = 6, unequal: Bool = false) throws {
        try hooks.fixture(count: count, heroFirst: true) { g in
            if unequal { for i in 1..<g.players.count { g.players[i].stack = 100 + i * 100 } }
            try startHand(g, random: random)
        }
    }

    func bettingTurn(_ level: Int = 2, _ street: Int = 0, short: Bool = false) throws {
        try hooks.fixture(count: 6) { g in
            g.dealer = 5
            if short { g.players[0].stack = 175 }
            try startHand(g, random: random)
            if street == 0 {
                if level >= 3 { try act(g, 3, .raise, 150) }
                if level >= 4 { try act(g, 4, .raise, 350) }
                while g.actor != 0 { try act(g, g.actor, .fold) }
            } else {
                while g.street < street {
                    while g.phase == .playing { try act(g, g.actor, .call) }
                    try advanceStreet(g)
                }
                if level >= 2 { try act(g, 1, .raise, 100) }
                if level >= 3 { try act(g, 2, .raise, 300) }
                while g.actor != 0 { try act(g, g.actor, level == 1 ? .check : .fold) }
            }
        }
    }

    func foldFinished(_ street: Int = 0) throws {
        try hooks.fixture(count: 6, heroFirst: true) { g in
            try startHand(g, random: random)
            while g.street < street {
                while g.phase == .playing { try act(g, g.actor, .call) }
                try advanceStreet(g)
            }
            if street > 0 { try act(g, g.actor, .raise, 100) }
            while g.actor != 0 { try act(g, g.actor, .fold) }
            try act(g, 0, .fold)
            while g.phase == .playing { try act(g, g.actor, .fold) }
        }
    }

    func allinRest() throws {
        hooks.stop()
        try hooks.mutate { g in
            while g.phase == .playing {
                let legal = legalActions(g)
                try act(g, g.actor, legal.canRaise ? .raise : .call, legal.maxRaiseTo)
            }
        }
    }

    func respondToHero(_ raiseTo: Int = 0, nextStreet: Bool = false) throws {
        hooks.stop()
        try hooks.mutate { g in
            var amount = raiseTo
            func callUntilHero() throws {
                while g.phase == .playing && g.actor != 0 {
                    try act(g, g.actor, amount != 0 ? .raise : .call, amount != 0 ? amount : nil)
                    amount = 0
                }
            }
            try callUntilHero()
            if nextStreet && g.phase == .between {
                try advanceStreet(g)
                try callUntilHero()
            }
        }
    }

    func river(_ count: Int = 6) throws {
        try hooks.fixture(count: count) { g in
            try startHand(g, random: random)
            while g.street < 3 || g.phase == .playing {
                if g.phase == .between { try advanceStreet(g) } else { try act(g, g.actor, .call) }
            }
        }
    }

    func retainedRiver(_ count: Int = 6) throws {
        try hooks.fixture(count: count, heroFirst: true) { g in
            try startHand(g, random: random)
            while g.street < 3 {
                if g.phase == .between { try advanceStreet(g) } else { try act(g, g.actor, .call) }
            }
            try act(g, g.actor, .raise, 100)
            try act(g, g.actor, .call)
            try act(g, g.actor, .raise, 300)
            try act(g, g.actor, .fold)
            while g.phase == .playing { try act(g, g.actor, .call) }
        }
    }

    func finish() throws {
        hooks.stop()
        try hooks.mutate { g in if g.phase == .between { try advanceStreet(g) } }
    }

    func foldWin(_ count: Int = 6, winner: Int? = nil) throws {
        let w = winner ?? count - 1
        try hooks.fixture(count: count, heroFirst: true) { g in
            try startHand(g, random: random)
            while g.phase == .playing { try act(g, g.actor, g.actor == w ? .call : .fold) }
        }
    }

    func foldRest() throws {
        hooks.stop()
        try hooks.mutate { g in while g.phase == .playing { try act(g, g.actor, .fold) } }
    }

    func foldPotRefund(_ count: Int = 6) throws {
        try hooks.fixture(count: count, heroFirst: true) { g in
            try startHand(g, random: random)
            while g.actor != 2 { try act(g, g.actor, .fold) }
            try act(g, 2, .raise, 125)
            while g.phase == .playing { try act(g, g.actor, .fold) }
        }
    }

    func scene(_ hole: String, _ board: String, count: Int = 6, totals: [Int]? = nil,
               folded: [Int] = [], otherHoles: [Int: String] = [:]) throws {
        try hooks.fixture(count: count) { g in
            try startHand(g, random: random)
            g.board = parseCards(board)
            g.players[0].hole = parseCards(hole)
            var used = Set((g.board + g.players[0].hole).map(\.key))
            for (id, h) in otherHoles {
                g.players[id].hole = parseCards(h)
                g.players[id].hole.forEach { used.insert($0.key) }
            }
            var rest = deckOfCards().filter { !used.contains($0.key) }
            for i in g.players.indices {
                if i != 0 && otherHoles[i] == nil {
                    g.players[i].hole = [rest.removeFirst(), rest.removeFirst()]
                }
                let total = totals.flatMap { i < $0.count ? $0[i] : nil } ?? 100
                g.players[i].total = total
                g.players[i].bet = total
                g.players[i].stack = 5000 - total
                g.players[i].folded = folded.contains(i)
                g.players[i].allin = false
                g.players[i].action = g.players[i].folded ? "Fold" : "Check"
                g.players[i].lastAction = LastAction(text: g.players[i].action, street: 3, bet: total)
            }
            g.street = 3
            g.phase = .between
            g.revealed = true
            try settle(g, showdown: true)
        }
    }
}

/// A review runner that completes only when the test says so.
final class FakeReviewRunner: ReviewRunner {
    final class Started {
        let job: ReviewJob
        let sink: ReviewSink
        var cancelled = false
        init(job: ReviewJob, sink: ReviewSink) {
            self.job = job
            self.sink = sink
        }
    }

    var started: [Started] = []

    func start(_ job: ReviewJob, _ sink: ReviewSink) -> SessionCancellable {
        let s = Started(job: job, sink: sink)
        started.append(s)
        return CancelHandle { s.cancelled = true }
    }
}

struct FakeAnalysis: HandReviewAnalysis {
    let priorityIndex: Int
}

struct TestFailure: Error {}

extension Array where Element == SeatState {
    func seat(_ id: Int) -> SeatState { first { $0.id == id }! }
}
