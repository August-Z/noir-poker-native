package com.august.noirpoker.platform

// android-only: Application context, the process lifecycle and platform adapters.

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.DefaultLifecycleObserver
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

    private val lifecycleObserver = object : DefaultLifecycleObserver {
        override fun onStart(owner: LifecycleOwner) = model.onForeground()
        override fun onStop(owner: LifecycleOwner) = model.onBackground()
    }

    init {
        ProcessLifecycleOwner.get().lifecycle.addObserver(lifecycleObserver)
    }

    override fun onCleared() {
        ProcessLifecycleOwner.get().lifecycle.removeObserver(lifecycleObserver)
        model.close()
        reviewRunner.shutdown()
        sounds.shutdown()
    }
}
