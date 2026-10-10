package com.august.noirpoker.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class HandRankFixtureTest {
    @Test
    fun `hand evaluation matches the shared hand-ranks fixture`() {
        val dir = System.getProperty("noir.fixtures") ?: "../../fixtures"
        val root = Json.parseToJsonElement(File(dir, "hand-ranks.json").readText()).jsonObject
        val cases = root.getValue("cases").jsonArray
        assertTrue(cases.isNotEmpty())
        for (case in cases) {
            val obj = case.jsonObject
            val input = obj.getValue("cards").jsonArray.map {
                Card(it.jsonObject.getValue("rank").jsonPrimitive.int, it.jsonObject.getValue("suit").jsonPrimitive.int)
            }
            val result = evaluate(input)
            val name = obj.getValue("name").jsonPrimitive.content
            assertEquals(obj.getValue("score").jsonArray.map { it.jsonPrimitive.int }, result.score, name)
            assertEquals(obj.getValue("bestCardKeys").jsonArray.map { it.jsonPrimitive.content }, result.cards.map { it.key }, name)
        }
    }
}
