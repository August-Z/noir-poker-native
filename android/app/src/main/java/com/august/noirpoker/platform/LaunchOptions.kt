package com.august.noirpoker.platform

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo

/**
 * Launch options for deterministic UI tests, the counterpart of the iOS UI-test
 * launch arguments. They are read from intent extras and honored only by a
 * debuggable build; a release build always gets [DEFAULT].
 *
 * - [seed]: seeds the session's single random stream (shuffle, bots, thinking time).
 * - [preferencesName]: the `SharedPreferences` file, so a test does not touch real preferences.
 * - [clearPreferences]: wipes that file before the session reads it.
 * - [timeScale]: runs the session clock faster (bot thinking and street delays
 *   shrink by this factor; the random draws and their order are unchanged).
 */
data class LaunchOptions(
    val seed: Long? = null,
    val preferencesName: String = DEFAULT_PREFERENCES,
    val clearPreferences: Boolean = false,
    val timeScale: Double = 1.0,
) {
    companion object {
        const val DEFAULT_PREFERENCES = "noir-preferences"
        const val EXTRA_SEED = "com.august.noirpoker.test.SEED"
        const val EXTRA_PREFERENCES = "com.august.noirpoker.test.PREFERENCES"
        const val EXTRA_CLEAR_PREFERENCES = "com.august.noirpoker.test.CLEAR_PREFERENCES"
        const val EXTRA_TIME_SCALE = "com.august.noirpoker.test.TIME_SCALE"

        val DEFAULT = LaunchOptions()

        fun from(context: Context, intent: Intent?): LaunchOptions {
            val debuggable = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            if (!debuggable || intent == null) return DEFAULT
            return LaunchOptions(
                seed = if (intent.hasExtra(EXTRA_SEED)) intent.getLongExtra(EXTRA_SEED, 0L) else null,
                preferencesName = intent.getStringExtra(EXTRA_PREFERENCES)?.takeIf { it.isNotBlank() } ?: DEFAULT_PREFERENCES,
                clearPreferences = intent.getBooleanExtra(EXTRA_CLEAR_PREFERENCES, false),
                timeScale = intent.getDoubleExtra(EXTRA_TIME_SCALE, 1.0).coerceIn(1.0, 100.0),
            )
        }
    }
}
