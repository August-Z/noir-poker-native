package com.august.noirpoker.core.session

import com.august.noirpoker.core.Difficulty
import com.august.noirpoker.core.EmotionMode
import com.august.noirpoker.core.defaultBotSettings
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PreferencesTest {
    private fun table(raw: String?): TablePreferences {
        val storage = InMemoryStorage()
        if (raw != null) storage.values[PreferencesStore.TABLE_KEY] = raw
        return PreferencesStore(storage).loadTable()
    }

    @Test
    fun `table preferences default to six seats at standard difficulty`() {
        assertEquals(TablePreferences(6, Difficulty.NORMAL), table(null))
    }

    @Test
    fun `corrupt or invalid table preferences fall back per field`() {
        for (raw in listOf("{", "null", "[]", "true", "\"9\"", "{broken", "")) {
            assertEquals(TablePreferences(6, Difficulty.NORMAL), table(raw), raw)
        }
        assertEquals(TablePreferences(6, Difficulty.HARD), table("""{"playerCount":"9","difficulty":"hard"}"""))
        assertEquals(TablePreferences(6, Difficulty.EASY), table("""{"playerCount":6.5,"difficulty":"easy"}"""))
        assertEquals(TablePreferences(6, Difficulty.NORMAL), table("""{"playerCount":4,"difficulty":"brutal"}"""))
        assertEquals(TablePreferences(6, Difficulty.NORMAL), table("""{"playerCount":10}"""))
        assertEquals(TablePreferences(6, Difficulty.NORMAL), table("""{"playerCount":null}"""))
        assertEquals(TablePreferences(9, Difficulty.NORMAL), table("""{"playerCount":9.0}"""))
        assertEquals(TablePreferences(5, Difficulty.HARD), table("""{"playerCount":5,"difficulty":"hard","extra":1}"""))
    }

    @Test
    fun `saving writes only player count and difficulty`() {
        val storage = InMemoryStorage(mapOf("other" to "kept"))
        PreferencesStore(storage).saveTable(TablePreferences(9, Difficulty.HARD))
        assertEquals("""{"playerCount":9,"difficulty":"hard"}""", storage.values[PreferencesStore.TABLE_KEY])
        assertEquals("kept", storage.values["other"])
    }

    @Test
    fun `sound is on only for true and hints are off only for false`() {
        val storage = InMemoryStorage()
        val store = PreferencesStore(storage)
        assertFalse(store.loadSound())
        assertTrue(store.loadHints())
        storage.values[PreferencesStore.SOUND_KEY] = "TRUE"
        storage.values[PreferencesStore.HINTS_KEY] = "no"
        assertFalse(store.loadSound())
        assertTrue(store.loadHints())
        store.saveSound(true)
        store.saveHints(false)
        assertEquals("true", storage.values[PreferencesStore.SOUND_KEY])
        assertEquals("false", storage.values[PreferencesStore.HINTS_KEY])
        assertTrue(store.loadSound())
        assertFalse(store.loadHints())
    }

    @Test
    fun `opponent settings round-trip for all eight seats and sanitize bad values`() {
        val storage = InMemoryStorage()
        val store = PreferencesStore(storage)
        assertEquals(defaultBotSettings(), store.loadBotSettings())
        val mixed = com.august.noirpoker.core.BotSettings(EmotionMode.LIVELY, MIXED_LINEUP)
        store.saveBotSettings(mixed)
        assertEquals(
            """{"emotionMode":"lively","assignments":{"1":"tan","2":"st","3":"zang","4":"peter","5":"abao","6":"viktor","7":"jungleman","8":"dwan"}}""",
            storage.values[PreferencesStore.OPPONENTS_KEY],
        )
        assertEquals(mixed, store.loadBotSettings())
        storage.values[PreferencesStore.OPPONENTS_KEY] = """{"emotionMode":"wild","assignments":{"1":"dwan","2":"nobody","9":"tan"}}"""
        val loaded = store.loadBotSettings()
        assertEquals(EmotionMode.SUBTLE, loaded.emotionMode)
        assertEquals("dwan", loaded.assignments[1])
        assertEquals("balanced", loaded.assignments[2])
        assertEquals((1..8).toList(), loaded.assignments.keys.toList())
        storage.values[PreferencesStore.OPPONENTS_KEY] = "{not json"
        assertEquals(defaultBotSettings(), store.loadBotSettings())
    }

    @Test
    fun `failing storage never throws and falls back to defaults`() {
        val broken = object : KeyValueStorage {
            override fun getString(key: String): String? = throw IllegalStateException("unavailable")
            override fun putString(key: String, value: String) = throw IllegalStateException("full")
        }
        val store = PreferencesStore(broken)
        assertEquals(TablePreferences(), store.loadTable())
        assertEquals(defaultBotSettings(), store.loadBotSettings())
        assertFalse(store.loadSound())
        assertTrue(store.loadHints())
        store.saveTable(TablePreferences(9, Difficulty.HARD))
        store.saveSound(true)
        val session = TableSession(ManualScheduler(), broken, CountingRandom(1))
        session.start()
        assertEquals(6, session.state.playerCount)
        assertEquals(1, session.state.hand)
    }

    @Test
    fun `mini json parses and writes the stored shapes`() {
        assertEquals(mapOf("a" to listOf(1.0, true, null, "x\"y")), MiniJson.parse("""{"a":[1,true,null,"x\"y"]}"""))
        assertEquals(-2.5e3, MiniJson.parse("-2.5e3"))
        assertEquals("""{"k":[1,"é\n"]}""", MiniJson.stringify(mapOf("k" to listOf(1, "é\n"))))
        for (bad in listOf("{", "[1,]", "01", "\"\\x\"", "tru", "1 2")) {
            assertTrue(runCatching { MiniJson.parse(bad) }.isFailure, bad)
        }
    }
}
