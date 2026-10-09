package com.august.noirpoker

import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        NoirType.install(ManropeFamily)
        // NOIR is dark-only: light status and navigation icons on the navy page.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
        val reducedMotion = Settings.Global.getFloat(contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
        setContent {
            NoirTheme(reducedMotion = reducedMotion) {
                NoirTableScreen(table.model)
            }
        }
    }
}
