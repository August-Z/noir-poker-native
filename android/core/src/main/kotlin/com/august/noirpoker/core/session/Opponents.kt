package com.august.noirpoker.core.session

import com.august.noirpoker.core.BOT_PROFILES
import com.august.noirpoker.core.BotProfile
import com.august.noirpoker.core.BotSettings
import com.august.noirpoker.core.EmotionMode
import com.august.noirpoker.core.EngineCopy
import com.august.noirpoker.core.Game
import com.august.noirpoker.core.getBotProfile
import com.august.noirpoker.core.jsRound
import com.august.noirpoker.core.sanitizeBotSettings

// Opponent Styles settings logic (`opponents-controller.js`), without views.

/** The Mixed Lineup preset. */
val MIXED_LINEUP: Map<Int, String> = mapOf(
    1 to "tan", 2 to "st", 3 to "zang", 4 to "peter", 5 to "abao", 6 to "viktor", 7 to "jungleman", 8 to "dwan",
)

/** The summary chip on the Opponent Styles button and the pending-change note (`refresh()`). */
data class OpponentsSummary(val text: String, val changePending: Boolean, val changeNote: String?)

fun opponentsSummary(g: Game, pending: BotSettings): OpponentsSummary {
    val bots = g.players.drop(1)
    val named = bots.count { it.botProfile != "balanced" }
    val p = sanitizeBotSettings(pending)
    val changed = g.emotionMode != p.emotionMode || bots.any { it.botProfile != p.assignments[it.id] }
    val text = when {
        changed -> SessionCopy.opponentsSummaryPending
        named > 0 -> SessionCopy.opponentsSummaryNamed(named)
        else -> SessionCopy.opponentsSummaryBalanced
    }
    return OpponentsSummary(text, changed, if (changed) SessionCopy.opponentsChangeNote else null)
}

data class ProfileCardState(val id: String, val short: String, val tag: String, val selected: Boolean)

data class ProfileAxisState(val label: String, val value: Int)

data class ProfileDetailState(
    val profile: BotProfile,
    val badge: String,
    val axes: List<ProfileAxisState>,
    val sizingText: String,
)

data class ProfileComparisonRow(val id: String, val short: String, val axes: List<Int>, val sizingText: String)

data class RosterRowState(
    val id: Int,
    val name: String,
    val offTable: Boolean,
    /** `Seat 3 · Steady` / `Not Seated · Steady`. */
    val subtitle: String,
    val selectA11y: String,
    /** The draft assignment for this seat. */
    val assignment: String,
    /** Profile ids with `"{short} · {first tag segment}"`, in catalog order. */
    val options: List<OptionItem<String>>,
    val currentStyle: String,
    val observed: String,
    val observedTitle: String,
    val moodReason: String?,
)

data class OpponentsDialogState(
    val saveNote: String,
    val emotionMode: EmotionMode,
    val emotionOptions: List<EmotionMode>,
    val selectedProfile: String,
    val profileCards: List<ProfileCardState>,
    val detail: ProfileDetailState,
    val comparison: List<ProfileComparisonRow>,
    val roster: List<RosterRowState>,
)

private fun sizingPercent(x: Double) = jsRound(x * 100).toInt()

/**
 * The opponent-settings draft. [open] copies the saved settings; edits change
 * only the draft; [save] returns sanitized settings for the caller to persist and
 * apply at the next deal; [discard] drops the draft. The previewed profile
 * persists across opens and starts as Balanced.
 */
class OpponentSettingsEditor {
    private var draftMode: EmotionMode? = null
    private val draftAssignments = LinkedHashMap<Int, String>()
    var selectedProfile: String = "balanced"
        private set

    val isOpen: Boolean get() = draftMode != null

    fun open(saved: BotSettings) {
        val clean = sanitizeBotSettings(saved)
        draftMode = clean.emotionMode
        draftAssignments.clear()
        draftAssignments.putAll(clean.assignments)
    }

    fun draft(): BotSettings? = draftMode?.let { BotSettings(it, LinkedHashMap(draftAssignments)) }

    fun previewProfile(id: String) {
        if (!isOpen) return
        selectedProfile = id
    }

    fun assignSeat(seat: Int, profile: String) {
        if (!isOpen || seat !in 1..8) return
        draftAssignments[seat] = profile
        selectedProfile = profile
    }

    fun setEmotionMode(mode: EmotionMode) {
        if (!isOpen) return
        draftMode = mode
    }

    fun mixLineup() {
        if (!isOpen) return
        draftAssignments.putAll(MIXED_LINEUP)
        selectedProfile = "tan"
    }

    /** Sanitizes and closes the draft. Returns `null` when no draft is open. */
    fun save(): BotSettings? {
        val d = draft() ?: return null
        draftMode = null
        return sanitizeBotSettings(d)
    }

    fun discard() {
        draftMode = null
    }

    fun state(g: Game, requestedCount: Int): OpponentsDialogState? {
        val mode = draftMode ?: return null
        val profile = getBotProfile(selectedProfile)
        val options = BOT_PROFILES.map { OptionItem(it.id, "${it.short} · ${it.tag.substringBefore(" · ")}") }
        val roster = EngineCopy.botNames.mapIndexed { i, name ->
            val id = i + 1
            val player = g.players.getOrNull(id)
            val stats = player?.botStats
            fun ratio(v: Int): String =
                if (stats != null && stats.hands > 0) "${jsRound(v.toDouble() / stats.hands * 100).toInt()}%" else SessionCopy.statEmpty
            val mood = if (player != null && g.emotionMode != EmotionMode.OFF) player.botMood.kind.label else SessionCopy.moodSteady
            val offTable = id >= requestedCount
            RosterRowState(
                id = id,
                name = name,
                offTable = offTable,
                subtitle = (if (offTable) SessionCopy.rosterOffTable else SessionCopy.rosterSeat(id)) + " · " + mood,
                selectA11y = SessionCopy.rosterSelectA11y(name),
                assignment = draftAssignments.getValue(id),
                options = options,
                currentStyle = if (player != null) {
                    SessionCopy.rosterCurrentStyle(getBotProfile(player.botProfile).short)
                } else {
                    SessionCopy.rosterNotSeated
                },
                observed = SessionCopy.rosterObserved(stats?.hands ?: 0, ratio(stats?.vpip ?: 0), ratio(stats?.pfr ?: 0)),
                observedTitle = SessionCopy.rosterObservedTitle,
                moodReason = player?.botMood?.reason?.takeIf { it.isNotEmpty() && g.emotionMode != EmotionMode.OFF },
            )
        }
        return OpponentsDialogState(
            saveNote = SessionCopy.opponentsSaveNote,
            emotionMode = mode,
            emotionOptions = EmotionMode.entries.toList(),
            selectedProfile = selectedProfile,
            profileCards = BOT_PROFILES.map { ProfileCardState(it.id, it.short, it.tag, it.id == selectedProfile) },
            detail = ProfileDetailState(
                profile = profile,
                badge = SessionCopy.profileBadge,
                axes = com.august.noirpoker.core.PROFILE_AXES.mapIndexed { i, label -> ProfileAxisState(label, profile.axes[i]) },
                sizingText = SessionCopy.profileSizing(sizingPercent(profile.sizing[0]), sizingPercent(profile.sizing[1])),
            ),
            comparison = BOT_PROFILES.map {
                ProfileComparisonRow(
                    it.id,
                    it.short,
                    it.axes,
                    SessionCopy.profileSizingCell(sizingPercent(it.sizing[0]), sizingPercent(it.sizing[1])),
                )
            },
            roster = roster,
        )
    }
}
