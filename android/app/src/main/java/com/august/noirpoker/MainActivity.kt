package com.august.noirpoker

import android.database.ContentObserver
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.august.noirpoker.platform.HandlerScheduler
import com.august.noirpoker.platform.LaunchOptions
import com.august.noirpoker.platform.TableViewModel
import com.august.noirpoker.ui.table.TableModel
import com.august.noirpoker.ui.table.NoirTableScreen
import com.august.noirpoker.ui.theme.ManropeFamily
import com.august.noirpoker.ui.theme.NoirTheme
import com.august.noirpoker.ui.theme.NoirType

class MainActivity : ComponentActivity() {
    private val table: TableViewModel by viewModels {
        viewModelFactory {
            initializer { TableViewModel(application, LaunchOptions.from(this@MainActivity, intent)) }
        }
    }

    /** The table model, for instrumented UI tests (main thread only). */
    val tableModel: TableModel get() = table.model

    /** The session clock, for instrumented UI tests (main thread only). */
    val tableScheduler: HandlerScheduler get() = table.scheduler

    /**
     * Reduced motion follows the system "Remove animations" setting (animator
     * duration scale 0). It is observed while the activity is started, and read
     * again on every start, so a change made in Settings while the app was in the
     * background or open in split screen applies without recreating the activity.
     */
    private var reducedMotion by mutableStateOf(false)

    private val animatorScaleObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            reducedMotion = readReducedMotion()
        }
    }

    private fun readReducedMotion(): Boolean =
        Settings.Global.getFloat(contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f

    override fun onStart() {
        super.onStart()
        reducedMotion = readReducedMotion()
        contentResolver.registerContentObserver(
            Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE),
            false,
            animatorScaleObserver,
        )
    }

    override fun onStop() {
        contentResolver.unregisterContentObserver(animatorScaleObserver)
        super.onStop()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        NoirType.install(ManropeFamily)
        // NOIR is dark-only: light status and navigation icons on the navy page.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
        reducedMotion = readReducedMotion()
        setContent {
            NoirTheme(reducedMotion = reducedMotion) {
                NoirTableScreen(table.model)
            }
        }
    }
}
