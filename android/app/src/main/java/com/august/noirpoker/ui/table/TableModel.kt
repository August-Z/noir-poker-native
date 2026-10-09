package com.august.noirpoker.ui.table

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.august.noirpoker.core.RandomSource
import com.august.noirpoker.core.SystemRandom
import com.august.noirpoker.core.session.Cancellable
import com.august.noirpoker.core.session.KeyValueStorage
import com.august.noirpoker.core.session.ReviewRunner
import com.august.noirpoker.core.session.Scheduler
import com.august.noirpoker.core.session.SessionEffect
import com.august.noirpoker.core.session.SoundKind
import com.august.noirpoker.core.session.TableRenderState
import com.august.noirpoker.core.session.TableSession
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/** Plays a synthesized table sound. */
fun interface SoundPlayer {
    fun play(kind: SoundKind)
}

/**
 * The observable table model: it owns the [TableSession], republishes its render
 * state as Compose state, routes sounds to the [SoundPlayer], and exposes the
 * visual effects (chip flights, reveal focus) as a flow. All game logic,
 * scheduling and copy stay in the session; this class adds no rules.
 *
 * Main thread only, like the session.
 */
class TableModel(
    scheduler: Scheduler,
    storage: KeyValueStorage,
    reviewRunner: ReviewRunner?,
    private val sounds: SoundPlayer? = null,
    random: RandomSource = SystemRandom,
) {
    val session = TableSession(scheduler, storage, random, reviewRunner)

    var state: TableRenderState by mutableStateOf(session.state)
        private set

    private val effectFlow = MutableSharedFlow<SessionEffect>(extraBufferCapacity = 32)

    /** Chip flights, chip-flight cancellation and reveal toggles, for the table view. */
    val effects: SharedFlow<SessionEffect> = effectFlow.asSharedFlow()

    private val subscription: Cancellable
    private var closed = false

    init {
        session.effectListener = { effect ->
            if (effect is SessionEffect.Sound) sounds?.play(effect.kind) else effectFlow.tryEmit(effect)
        }
        subscription = session.addListener { state = it }
        session.start()
    }

    /** App moved to the background: the session cancels timers, Finish Hand and the review job. */
    fun onBackground() {
        if (!closed) session.onBackground()
    }

    /** App returned: a thinking bot restarts its delay, an open review restarts. */
    fun onForeground() {
        if (!closed) session.onForeground()
    }

    /** Stops all scheduled and background work for good (the owner is destroyed). */
    fun close() {
        if (closed) return
        session.onBackground()
        closed = true
        subscription.cancel()
        session.effectListener = null
    }
}
