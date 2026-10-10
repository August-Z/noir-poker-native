import XCTest
@testable import PokerCore

final class PreferencesSessionTests: XCTestCase {
    private func table(_ raw: String?) -> TablePreferences {
        let storage = InMemoryStorage()
        if let raw { storage.values[PreferencesStore.tableKey] = raw }
        return PreferencesStore(storage).loadTable()
    }

    func testTablePreferencesDefaultToSixSeatsAtStandardDifficulty() {
        XCTAssertEqual(table(nil), TablePreferences(playerCount: 6, difficulty: .normal))
    }

    func testCorruptOrInvalidTablePreferencesFallBackPerField() {
        for raw in ["{", "null", "[]", "true", "\"9\"", "{broken", "", "{\"playerCount\":6,}"] {
            XCTAssertEqual(table(raw), TablePreferences(), raw)
        }
        XCTAssertEqual(table(#"{"playerCount":"9","difficulty":"hard"}"#), TablePreferences(playerCount: 6, difficulty: .hard))
        XCTAssertEqual(table(#"{"playerCount":6.5,"difficulty":"easy"}"#), TablePreferences(playerCount: 6, difficulty: .easy))
        XCTAssertEqual(table(#"{"playerCount":4,"difficulty":"brutal"}"#), TablePreferences())
        XCTAssertEqual(table(#"{"playerCount":10}"#), TablePreferences())
        XCTAssertEqual(table(#"{"playerCount":null}"#), TablePreferences())
        XCTAssertEqual(table(#"{"playerCount":true}"#), TablePreferences())
        XCTAssertEqual(table(#"{"playerCount":9.0}"#), TablePreferences(playerCount: 9, difficulty: .normal))
        XCTAssertEqual(table(#"{"playerCount":7e0}"#), TablePreferences(playerCount: 7, difficulty: .normal))
        XCTAssertEqual(table(#"{"playerCount":5,"difficulty":"hard","extra":1}"#), TablePreferences(playerCount: 5, difficulty: .hard))
        // JSON.parse keeps the last duplicate key.
        XCTAssertEqual(table(#"{"playerCount":8,"playerCount":"8"}"#), TablePreferences())
    }

    func testSavingWritesOnlyPlayerCountAndDifficulty() {
        let storage = InMemoryStorage(["other": "kept"])
        PreferencesStore(storage).saveTable(TablePreferences(playerCount: 9, difficulty: .hard))
        XCTAssertEqual(storage.values[PreferencesStore.tableKey], #"{"playerCount":9,"difficulty":"hard"}"#)
        XCTAssertEqual(storage.values["other"], "kept")
        XCTAssertEqual(storage.values.count, 2)
    }

    func testSoundIsOnOnlyForTrueAndHintsAreOffOnlyForFalse() {
        let storage = InMemoryStorage()
        let store = PreferencesStore(storage)
        XCTAssertFalse(store.loadSound())
        XCTAssertTrue(store.loadHints())
        storage.values[PreferencesStore.soundKey] = "TRUE"
        storage.values[PreferencesStore.hintsKey] = "no"
        XCTAssertFalse(store.loadSound())
        XCTAssertTrue(store.loadHints())
        store.saveSound(true)
        store.saveHints(false)
        XCTAssertEqual(storage.values[PreferencesStore.soundKey], "true")
        XCTAssertEqual(storage.values[PreferencesStore.hintsKey], "false")
        XCTAssertTrue(store.loadSound())
        XCTAssertFalse(store.loadHints())
    }

    func testOpponentSettingsRoundTripForAllEightSeatsAndSanitizeBadValues() {
        let storage = InMemoryStorage()
        let store = PreferencesStore(storage)
        XCTAssertEqual(store.loadBotSettings(), defaultBotSettings())
        let mixed = BotSettings(emotionMode: .lively, assignments: MIXED_LINEUP)
        store.saveBotSettings(mixed)
        XCTAssertEqual(
            storage.values[PreferencesStore.opponentsKey],
            #"{"emotionMode":"lively","assignments":{"1":"tan","2":"st","3":"zang","4":"peter","5":"abao","6":"viktor","7":"jungleman","8":"dwan"}}"#
        )
        XCTAssertEqual(store.loadBotSettings(), mixed)
        storage.values[PreferencesStore.opponentsKey] = #"{"emotionMode":"wild","assignments":{"1":"dwan","2":"nobody","3":null,"9":"tan"}}"#
        let loaded = store.loadBotSettings()
        XCTAssertEqual(loaded.emotionMode, .subtle)
        XCTAssertEqual(loaded.assignments[1], "dwan")
        XCTAssertEqual(loaded.assignments[2], "balanced")
        XCTAssertEqual(loaded.assignments[3], "balanced")
        XCTAssertEqual(loaded.assignments.keys.sorted(), Array(1...8))
        storage.values[PreferencesStore.opponentsKey] = #"{"emotionMode":"off","assignments":[null,"st",null,"tan"]}"#
        let fromArray = store.loadBotSettings()
        XCTAssertEqual(fromArray.emotionMode, .off)
        XCTAssertEqual(fromArray.assignments[1], "st")
        XCTAssertEqual(fromArray.assignments[2], "balanced")
        XCTAssertEqual(fromArray.assignments[3], "tan")
        for bad in ["{not json", "null", "42", "[]"] {
            storage.values[PreferencesStore.opponentsKey] = bad
            XCTAssertEqual(store.loadBotSettings(), defaultBotSettings(), bad)
        }
    }

    func testFailingStorageNeverThrowsAndFallsBackToDefaults() {
        final class BrokenStorage: KeyValueStorage {
            func getString(_ key: String) throws -> String? { throw TestFailure() }
            func putString(_ key: String, _ value: String) throws { throw TestFailure() }
        }
        let broken = BrokenStorage()
        let store = PreferencesStore(broken)
        XCTAssertEqual(store.loadTable(), TablePreferences())
        XCTAssertEqual(store.loadBotSettings(), defaultBotSettings())
        XCTAssertFalse(store.loadSound())
        XCTAssertTrue(store.loadHints())
        store.saveTable(TablePreferences(playerCount: 9, difficulty: .hard))
        store.saveSound(true)
        let session = TableSession(scheduler: ManualScheduler(), storage: broken, random: SeededRandom(seed: 1))
        session.start()
        XCTAssertEqual(session.state.playerCount, 6)
        XCTAssertEqual(session.state.hand, 1)
        session.setSeatCount(7)
        session.toggleSound()
        XCTAssertEqual(session.state.settings.requestedSeatCount, 7)
    }

    func testMiniJSONParsesAndWritesTheStoredShapes() throws {
        XCTAssertEqual(
            try MiniJSON.parse(#"{"a":[1,true,null,"x\"y"]}"#),
            .object([(key: "a", value: .array([.number(1), .bool(true), .null, .string("x\"y")]))])
        )
        XCTAssertEqual(try MiniJSON.parse("-2.5e3"), .number(-2500))
        XCTAssertEqual(try MiniJSON.parse(#""é😀""#), .string("é😀"))
        XCTAssertEqual(
            MiniJSON.stringify(.object([(key: "k", value: .array([.number(1), .string("é\n")]))])),
            #"{"k":[1,"é\n"]}"#
        )
        XCTAssertEqual(MiniJSON.stringify(.number(6.5)), "6.5")
        for bad in ["{", "[1,]", "01", #""\x""#, "tru", "1 2", "-", "1.", "\"a"] {
            XCTAssertThrowsError(try MiniJSON.parse(bad), bad)
        }
    }
}
