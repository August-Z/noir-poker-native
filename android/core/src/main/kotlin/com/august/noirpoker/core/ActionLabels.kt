package com.august.noirpoker.core

/**
 * The legal-action fields the label functions read. The reference reads them
 * from any object (`legal?.maxRaiseTo`, `legal?.fullRaiseTo`, `legal.callAmount`),
 * so each one may be absent: a disabled `legalActions` result has none of them,
 * and older callers pass only `maxRaiseTo`.
 */
data class LabelLegal(val callAmount: Int? = null, val fullRaiseTo: Int? = null, val maxRaiseTo: Int? = null)

/** The label view of a `legalActions` result; a disabled result has no fields. */
fun LegalActions.forLabels(): LabelLegal =
    if (enabled) LabelLegal(callAmount, fullRaiseTo, maxRaiseTo) else LabelLegal()

/**
 * The fields the label functions read. In the reference this is any object with
 * these keys: a hero decision snapshot, or the game plus `legal`, `action` and
 * `amount`. [amount] is a JavaScript number: labels round it with `Math.round`.
 */
data class LabelStep(
    val street: Int,
    val history: List<HistoryEntry> = emptyList(),
    val currentBet: Int = 0,
    val minRaise: Int? = null,
    val legal: LabelLegal? = null,
    val stack: Int? = null,
    val action: Action? = null,
    val amount: Double? = null,
) {
    constructor(
        street: Int,
        history: List<HistoryEntry> = emptyList(),
        currentBet: Int = 0,
        minRaise: Int? = null,
        legal: LegalActions,
        stack: Int? = null,
        action: Action? = null,
        amount: Int? = null,
    ) : this(street, history, currentBet, minRaise, legal.forLabels(), stack, action, amount?.toDouble())
}

fun DecisionSnapshot.labelStep(): LabelStep =
    LabelStep(street, history, currentBet, minRaise, legal, stack, action, amount)

/** The label step for the actor's next action in a live game. */
fun labelStep(g: Game, legal: LegalActions = legalActions(g), action: Action? = null, amount: Int? = null): LabelStep =
    LabelStep(g.street, g.history.toList(), g.currentBet, g.minRaise, legal, g.players.getOrNull(g.actor)?.stack, action, amount)

// This is an action ordinal, not a test of whether betting has reopened.
// The big blind is the first bet preflop; every later street starts at zero.
fun nextBetLevel(street: Int, history: List<HistoryEntry> = emptyList()): Int =
    (if (street == 0) 1 else 0) + history.count { it.street == street && it.action == Action.RAISE } + 1

fun nextBetLevel(step: LabelStep): Int = nextBetLevel(step.street, step.history)

fun nextBetLevel(g: Game): Int = nextBetLevel(g.street, g.history)

fun raiseCaption(step: LabelStep, amount: Int): String = raiseCaption(step, amount.toDouble())

fun raiseCaption(step: LabelStep, amount: Double): String {
    val level = nextBetLevel(step)
    val maxRaiseTo = step.legal?.maxRaiseTo
    val allin = maxRaiseTo != null && amount == maxRaiseTo.toDouble()
    val fullRaiseTo = step.legal?.fullRaiseTo
        ?: if (step.currentBet == 0) 50 else step.currentBet + (step.minRaise ?: 50)
    val verb = when {
        allin && amount < fullRaiseTo -> EngineCopy.shortAllInTo
        allin -> EngineCopy.allInTo
        step.currentBet == 0 -> EngineCopy.betTo
        step.street == 0 && level == 2 -> EngineCopy.openTo
        else -> EngineCopy.raiseTo
    }
    return EngineCopy.betCaption(level, verb)
}

fun actionLabel(step: LabelStep, action: Action?, amount: Int): String = actionLabel(step, action, amount.toDouble())

fun actionLabel(step: LabelStep, action: Action? = step.action, amount: Double? = step.amount): String {
    if (action == Action.RAISE) {
        val n = requireNotNull(amount) { "A raise label needs an amount" }
        return raiseCaption(step, n) + " " + formatChips(n)
    }
    if (action == Action.CALL) {
        val callAmount = requireNotNull(step.legal?.callAmount) { "A call label needs legal actions" }
        return (if (callAmount == step.stack) EngineCopy.allInCallPrefix else EngineCopy.callPrefix) +
            formatChips(callAmount)
    }
    return if (action == Action.FOLD) EngineCopy.fold else EngineCopy.check
}

fun historyActionLabel(history: List<HistoryEntry>, index: Int): String {
    val a = history[index]
    if (a.action != Action.RAISE) {
        return when (a.action) {
            Action.CALL -> EngineCopy.callPrefix + formatChips(a.amount)
            Action.FOLD -> EngineCopy.fold
            else -> EngineCopy.check
        }
    }
    // The reference tests `if (a.betLabel)`: an empty label counts as absent.
    if (!a.betLabel.isNullOrEmpty()) return a.betLabel + " " + formatChips(a.amount)
    val before = history.subList(0, index).toList()
    val previous = before.lastOrNull { it.street == a.street && it.action == Action.RAISE }
    return actionLabel(
        LabelStep(
            street = a.street,
            history = before,
            currentBet = previous?.amount ?: (if (a.street == 0) 50 else 0),
            action = a.action,
            amount = a.amount.toDouble(),
        ),
    )
}
