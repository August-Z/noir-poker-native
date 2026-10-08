package com.august.noirpoker.platform

// android-only: Application context, the process lifecycle and platform adapters.

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.august.noirpoker.ui.table.TableModel

/**
 * Owns the table model for the activity's lifetime (it survives rotation) and
 * forwards process background / foreground transitions to the session, which
 * cancels bot timers, Finish Hand and the review job and resumes them on return.
 */
class TableViewModel(application: Application) : AndroidViewModel(application) {
    private val reviewRunner = BackgroundReviewRunner()
    private val sounds = ToneSoundPlayer()

    val model = TableModel(
        scheduler = HandlerScheduler(),
        storage = SharedPreferencesStorage(application),
        reviewRunner = reviewRunner,
        sounds = sounds,
    )

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
