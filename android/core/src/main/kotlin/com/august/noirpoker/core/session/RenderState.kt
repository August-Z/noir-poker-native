package com.august.noirpoker.core.session

import com.august.noirpoker.core.BotStats
import com.august.noirpoker.core.Card
import com.august.noirpoker.core.Difficulty
import com.august.noirpoker.core.EmotionMode
import com.august.noirpoker.core.LastAction
import com.august.noirpoker.core.LegalActions
import com.august.noirpoker.core.LogType
import com.august.noirpoker.core.MoodKind
import com.august.noirpoker.core.Phase

// The immutable projection of the live game and session state that the UI
// layers bind to. Every string is final English copy; amounts are also given
// as numbers so the UI can format or announce them differently.

/** A face-up card. [animate] and [delayMs] drive the deal and flip animations. (Same name as Swift; avoids Compose and SwiftUI `CardView`s.) */
data class CardFace(val card: Card, val best: Boolean = false, val animate: Boolean = false, val delayMs: Int = 0) {
    /** `A♠`, `10♥`. */
    val text: String get() = card.toString()
}

/** One of the five board positions; [card] is null for an undealt slot. */
data class BoardSlot(val index: Int, val card: CardFace?, val placeholderGlyph: String, val a11y: String)

data class PositionBadge(val code: String, val name: String)

/** The hand-rank / winner badge on a seat or the hero. */
data class RankBadge(val text: String, val isWinner: Boolean, val a11y: String?, val title: String?)

/** The post-settlement eye toggle on an opponent seat. */
data class PeekToggle(val pressed: Boolean, val title: String, val a11y: String)

data class SeatState(
    val id: Int,
    val name: String,
    /** Reference layout: seat center as a percentage of the arena (left, top). */
    val layoutX: Double,
    val layoutY: Double,
    val position: PositionBadge,
    val folded: Boolean,
    /** This seat is the current actor (shows the deciding state). */
    val isActor: Boolean,
    val isWinner: Boolean,
    /** Hole cards are face up (showdown, all-in runout, or the eye toggle). */
    val revealed: Boolean,
    /** Face-up cards when [revealed]; empty otherwise. */
    val cards: List<CardFace>,
    /** Number of card backs when not revealed. */
    val cardBacks: Int,
    /** Card backs play the deal animation (new hand); delays per card. */
    val dealAnimation: Boolean,
    val cardBackDelaysMs: List<Int>,
    val cardBackA11y: String,
    val badge: RankBadge?,
    val avatar: String,
    val avatarTitle: String,
    val profileId: String,
    val styleShort: String,
    val styleTitle: String,
    val styleA11y: String,
    /** `steady` whenever emotion simulation is off. */
    val mood: MoodKind,
    val moodLabel: String,
    val stack: Int,
    val stackText: String,
    /** Present only after settlement. */
    val peek: PeekToggle?,
    val action: ActionChip,
    val actionA11y: String,
)

data class HeroState(
    val name: String,
    val cards: List<CardFace>,
    val rankBadge: RankBadge?,
    val folded: Boolean,
    val isActive: Boolean,
    val stack: Int,
    val stackText: String,
    val position: PositionBadge,
    /** `null` when the hand is over (the line is hidden). */
    val turnText: String?,
    /** The retained last action with its street; `null` hides the row. */
    val lastAction: ActionChip?,
    val lastActionA11y: String,
)

data class SessionStatsState(
    val stack: Int,
    val stackText: String,
    val chipsUnit: String,
    val changeText: String,
    val negative: Boolean,
    val hands: Int,
    val wins: Int,
    val winRateText: String,
)

data class ActivityEntryState(
    /** 1-based, chronological. */
    val number: Int,
    val text: String,
    /** [text] split into plain runs and persona suffixes. */
    val segments: List<TextSegment>,
    val type: LogType,
    val playerId: Int?,
    val isHero: Boolean,
    val street: Int,
)

data class ActivityState(val entries: List<ActivityEntryState>, val badge: String)

enum class BetPreset(val id: String) { MIN("min"), HALF_POT("half"), POT("pot"), ALL_IN("all") }

/** A bet preset; [amount] is the raise-to total it would select (null when raising is unavailable). */
data class PresetState(val preset: BetPreset, val label: String, val amount: Int?, val enabled: Boolean)

data class ActionPanelState(
    val decisionStripVisible: Boolean,
    val decisionText: String,
    /** Bet controls and Fold / Call / Raise (hidden when the hand is over or the hero folded). */
    val controlsVisible: Boolean,
    val foldLabel: String,
    val foldEnabled: Boolean,
    val callEnabled: Boolean,
    val callLabel: String,
    val callAmount: Int?,
    val callAmountText: String?,
    val callA11y: String,
    val raiseEnabled: Boolean,
    /** `{level}-bet {verb}` for the current bet, e.g. `3-bet raise to`. */
    val raiseCaption: String,
    val bet: Int,
    val betText: String,
    val raiseA11y: String,
    val sliderLabel: String,
    val sliderA11y: String,
    val sliderMin: Int?,
    val sliderMax: Int?,
    val presets: List<PresetState>,
    val nextHandVisible: Boolean,
    val nextHandLabel: String,
    val finishHandVisible: Boolean,
    val finishHandEnabled: Boolean,
    val finishHandLabel: String,
    val finishHandTitle: String,
    val replayVisible: Boolean,
    val replayLabel: String,
    val replayTitle: String,
    val reviewVisible: Boolean,
    val reviewLabel: String,
)

data class CoachState(val visible: Boolean, val toggleOn: Boolean, val toggleLabel: String, val stage: String, val tip: String)

data class ShowdownSceneState(
    val scene: HandScene,
    /** The player's name with the persona suffix. */
    val nameSegments: List<TextSegment>,
    val isWinner: Boolean,
    val statusText: String,
    val footerText: String,
    val a11y: String,
)

/** The showdown comparison. [key] changes once per settled hand; animate only when it changes. */
data class ShowdownState(val key: String, val context: String, val scenes: List<ShowdownSceneState>)

data class PotAwardRow(val playerId: Int, val name: String, val winnerText: String, val label: String, val amountText: String, val unit: String)

data class PotContributionRow(val playerId: Int, val text: String, val amount: Int, val amountText: String)

data class PotCardState(
    val index: Int,
    val label: String,
    val amount: Int,
    val amountText: String,
    val settled: Boolean,
    val eligibilityLabel: String,
    val heroEligible: Boolean,
    val contributions: List<PotContributionRow>,
    // Settled.
    val splitTotalText: String?,
    val awards: List<PotAwardRow>,
    val distributionSummary: String,
    val distributionEligibility: String,
    val contributionsHeading: String,
    val oddChipNote: String?,
    val expanded: Boolean,
    // Live.
    val unit: String,
    val playerCountText: String,
    val participantsText: String,
    val contributionsSummary: String,
)

data class RefundRowState(val playerId: Int, val amount: Int, val amountText: String, val text: String, val a11y: String?, val returned: Boolean)

data class PotDetailsState(
    val open: Boolean,
    val settled: Boolean,
    val title: String,
    val note: String?,
    val pots: List<PotCardState>,
    val refunds: List<RefundRowState>,
)

/** A selectable option: a value and its English label. */
data class OptionItem<T>(val value: T, val label: String)

data class SettingsState(
    val requestedSeatCount: Int,
    val seatCountOptions: List<OptionItem<Int>>,
    /** Shown while a different seat count is pending for the next hand. */
    val tableChangeNote: String?,
    val difficulty: Difficulty,
    val difficultyOptions: List<OptionItem<Difficulty>>,
    val hints: Boolean,
    val sound: Boolean,
    val soundA11y: String,
    val soundTitle: String,
    val emotionOptions: List<OptionItem<EmotionMode>>,
)

data class TableRenderState(
    /** Increments with every published state. */
    val version: Long,
    val hand: Int,
    val handNumber: String,
    val handHeading: String,
    val playerCount: Int,
    val tableTag: String,
    val tableSize: String,
    /** Some opponent uses a long style name (Viktor Blom, Daniel Cates, Tom Dwan). */
    val hasFullPlayerNames: Boolean,
    val phase: Phase,
    val street: Int,
    val streetLabel: String,
    val dealer: Int,
    val replayAttempt: Int,
    val replayBadge: String?,
    val replayNote: String?,
    val pot: Int,
    val potText: String,
    /** Play the pot bump: new community cards since the last state. */
    val potPulse: Boolean,
    val potButtonLabel: String,
    val potButtonA11y: String,
    val board: List<BoardSlot>,
    val boardCaption: String,
    val practiceRunout: Boolean,
    val seats: List<SeatState>,
    val hero: HeroState,
    val session: SessionStatsState,
    val activity: ActivityState,
    val actions: ActionPanelState,
    val coach: CoachState,
    /** `null` while hidden (not settled at a five-card showdown). */
    val showdown: ShowdownState?,
    val potDetails: PotDetailsState,
    val opponents: OpponentsSummary,
    /** `null` while the Opponent Styles dialog is closed. */
    val opponentsDialog: OpponentsDialogState?,
    val review: ReviewState,
    val settings: SettingsState,
    val finishing: Boolean,
    val backgrounded: Boolean,
)

// The diagnostic public snapshot (`window.noir.getState()`), for UI tests and
// accessibility checks. It never contains hidden hole cards, plans or traces.

data class PublicAward(val name: String, val amount: Int, val label: String)

data class PublicPot(val label: String, val amount: Int, val eligible: List<String>, val awards: List<PublicAward>)

data class PublicRefund(val name: String, val amount: Int, val returned: Boolean)

data class PublicPlayer(
    val id: Int,
    val name: String,
    val position: String,
    val stack: Int,
    val folded: Boolean,
    val allin: Boolean,
    val bet: Int,
    val action: String,
    val lastAction: LastAction?,
    /** Opponents only. */
    val botProfile: String?,
    val mood: String?,
    val botStats: BotStats?,
    /** Present only while the seat's hand is visible. */
    val cards: List<String>?,
)

data class PublicTableSnapshot(
    val playerCount: Int,
    val emotionMode: String,
    val canContinue: Boolean,
    val replayAttempt: Int,
    val canRestart: Boolean,
    val hand: Int,
    val dealer: String,
    val seatOrder: String,
    val street: String?,
    val phase: String,
    val actor: String?,
    val pot: Int,
    val pots: List<PublicPot>,
    val uncalled: List<PublicRefund>,
    val board: List<String>,
    val settlementBoard: List<String>,
    val practiceRunout: Boolean,
    val hole: List<String>,
    val stack: Int,
    val legal: LegalActions,
    val players: List<PublicPlayer>,
    val result: String?,
    val totalLogs: Int,
    /** Σ stacks + (pot while the hand is live). */
    val wealth: Int,
)

/** One-shot presentation effects (sound, chip flights, focus). */
sealed interface SessionEffect {
    data class Sound(val kind: SoundKind) : SessionEffect
    /** Three chips fly from the seat (0 = hero) to the pot. */
    data class ChipFlight(val seat: Int) : SessionEffect
    /** Cancel and remove every chip in flight (Replay Hand). */
    data object CancelChipFlights : SessionEffect
    /** Keep focus on the seat's eye toggle and fade its cards in when revealed. */
    data class RevealToggled(val seat: Int, val visible: Boolean) : SessionEffect
}

/** Synthesized sounds: notes start every 80 ms; gain 0.0001 → 0.025 at 15 ms → 0.0001 at 160 ms; stop at 200 ms. */
enum class SoundKind(val notesHz: List<Int>, val wave: String) {
    CHIP(listOf(310), "sine"),
    DEAL(listOf(820, 570), "triangle"),
    WIN(listOf(440, 554, 659), "sine"),
}
