package com.august.noirpoker.platform

// android-only: Application context, the process lifecycle and platform adapters.

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.august.noirpoker.core.SeededRandom
import com.august.noirpoker.core.SystemRandom
import com.august.noirpoker.ui.table.TableModel

/**
 * Owns the table model for the activity's lifetime (it survives rotation) and
 * forwards process background / foreground transitions to the session, which
 * cancels bot timers, Finish Hand and the review job and resumes them on return.
 */
class TableViewModel(
    application: Application,
    options: LaunchOptions = LaunchOptions.DEFAULT,
) : AndroidViewModel(application) {
    private val reviewRunner = BackgroundReviewRunner()
    private val sounds = ToneSoundPlayer()

    /** The session clock; UI tests change its time scale. */
    val scheduler = HandlerScheduler(timeScale = options.timeScale)

    val model: TableModel = run {
        if (options.clearPreferences) {
            application.getSharedPreferences(options.preferencesName, Context.MODE_PRIVATE).edit().clear().commit()
        }
        TableModel(
            scheduler = scheduler,
            storage = SharedPreferencesStorage(application, options.preferencesName),
            reviewRunner = reviewRunner,
            sounds = sounds,
            random = options.seed?.let { SeededRandom(it) } ?: SystemRandom,
        )
    }

    private val lifecycleBinding = SessionLifecycleBinding.attach(ProcessLifecycleOwner.get().lifecycle, model)

    override fun onCleared() {
        lifecycleBinding.detach()
        model.close()
        reviewRunner.shutdown()
        sounds.shutdown()
    }
}

/**
 * Forwards the process lifecycle to a [TableModel]: `ON_STOP` (the last
 * activity stopped, about 700 ms after it left the screen) calls
 * [TableModel.onBackground], and `ON_START` calls [TableModel.onForeground].
 *
 * The process lifecycle, not the activity's, is observed on purpose: a
 * rotation or another configuration change stops and restarts the activity
 * within that delay, so it never pauses the bots or the review. Pausing
 * (`ON_PAUSE`, for example a dialog or multi-window focus change) does not
 * background the table either, matching the reference, which reacts only to
 * the page becoming hidden.
 */
class SessionLifecycleBinding private constructor(
    private val lifecycle: Lifecycle,
    private val onForeground: () -> Unit,
    private val onBackground: () -> Unit,
) : DefaultLifecycleObserver {
    override fun onStart(owner: LifecycleOwner) = onForeground()
    override fun onStop(owner: LifecycleOwner) = onBackground()

    /** Stops forwarding (the owner is cleared). */
    fun detach() = lifecycle.removeObserver(this)

    companion object {
        /**
         * Observes [lifecycle] for [model]. An already started lifecycle replays
         * `ON_START` at once, which is harmless: the session ignores a
         * foreground call while it is not backgrounded.
         */
        fun attach(lifecycle: Lifecycle, model: TableModel): SessionLifecycleBinding =
            attach(lifecycle, onForeground = model::onForeground, onBackground = model::onBackground)

        fun attach(lifecycle: Lifecycle, onForeground: () -> Unit, onBackground: () -> Unit): SessionLifecycleBinding =
            SessionLifecycleBinding(lifecycle, onForeground, onBackground).also { lifecycle.addObserver(it) }
    }
}
