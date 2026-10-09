package com.august.noirpoker.platform

import android.content.Context
import android.content.SharedPreferences
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import com.august.noirpoker.core.review.ExecutorReviewRunner
import com.august.noirpoker.core.session.Cancellable
import com.august.noirpoker.core.session.KeyValueStorage
import com.august.noirpoker.core.session.ReviewRunner
import com.august.noirpoker.core.session.Scheduler
import com.august.noirpoker.core.session.SoundKind
import com.august.noirpoker.ui.table.SoundPlayer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.sin

/**
 * The session timer on the main looper, with a monotonic clock that keeps running
 * in deep sleep. A [timeScale] above 1 runs the session clock faster for UI tests:
 * the clock and every delay are scaled together, so deadlines stay consistent,
 * and changing the scale keeps the clock continuous. Main thread only.
 */
class HandlerScheduler(
    private val handler: Handler = Handler(Looper.getMainLooper()),
    timeScale: Double = 1.0,
) : Scheduler {
    private var anchorRealMs = SystemClock.elapsedRealtime()
    private var anchorVirtualMs = anchorRealMs.toDouble()

    var timeScale: Double = timeScale
        set(value) {
            require(value > 0.0)
            val now = virtualNow()
            anchorRealMs = SystemClock.elapsedRealtime()
            anchorVirtualMs = now
            field = value
        }

    private fun virtualNow(): Double = anchorVirtualMs + (SystemClock.elapsedRealtime() - anchorRealMs) * timeScale

    override val nowMs: Long get() = virtualNow().toLong()

    override fun schedule(delayMs: Long, action: () -> Unit): Cancellable {
        val runnable = Runnable(action)
        handler.postDelayed(runnable, (maxOf(0L, delayMs) / timeScale).toLong())
        return Cancellable { handler.removeCallbacks(runnable) }
    }
}

/** Preferences in `SharedPreferences`, under the reference's keys (`noir-table-v1`, …). */
class SharedPreferencesStorage(private val prefs: SharedPreferences) : KeyValueStorage {
    constructor(context: Context, name: String = LaunchOptions.DEFAULT_PREFERENCES) :
        this(context.getSharedPreferences(name, Context.MODE_PRIVATE))

    override fun getString(key: String): String? = prefs.getString(key, null)

    override fun putString(key: String, value: String) {
        prefs.edit().putString(key, value).apply()
    }
}

/**
 * The review analysis on a background thread. Results and progress are posted to
 * the main looper; a cancelled job stops at its next checkpoint.
 */
class BackgroundReviewRunner private constructor(
    private val executor: ExecutorService,
    handler: Handler,
) : ReviewRunner by ExecutorReviewRunner(executor, { block -> handler.post(block) }) {
    constructor() : this(
        Executors.newSingleThreadExecutor { r ->
            Thread({
                Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
                r.run()
            }, "noir-review").apply { isDaemon = true }
        },
        Handler(Looper.getMainLooper()),
    )

    fun shutdown() {
        executor.shutdownNow()
    }
}

/**
 * Synthesizes the reference's WebAudio cues: notes start every 80 ms; each note's
 * gain ramps exponentially 0.0001 → peak at 15 ms → 0.0001 at 160 ms and stops at
 * 200 ms. CHIP is a 310 Hz sine, DEAL 820/570 Hz triangle, WIN 440/554/659 Hz sine.
 */
class ToneSoundPlayer : SoundPlayer {
    private val executor = Executors.newSingleThreadExecutor { r -> Thread(r, "noir-sound").apply { isDaemon = true } }
    private val cache = HashMap<SoundKind, ShortArray>()

    override fun play(kind: SoundKind) {
        executor.execute {
            val samples = synchronized(cache) { cache.getOrPut(kind) { render(kind) } }
            runCatching {
                val track = AudioTrack.Builder()
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_GAME)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build(),
                    )
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(RATE)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                            .build(),
                    )
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .setBufferSizeInBytes(samples.size * 2)
                    .build()
                try {
                    track.write(samples, 0, samples.size)
                    track.play()
                    Thread.sleep(samples.size * 1000L / RATE + 40)
                } finally {
                    track.release()
                }
            }
        }
    }

    fun shutdown() {
        executor.shutdownNow()
    }

    private fun render(kind: SoundKind): ShortArray {
        val notes = kind.notesHz
        val total = ((notes.size - 1) * 0.08 + 0.2) * RATE
        val out = FloatArray(total.toInt() + 1)
        notes.forEachIndexed { i, hz ->
            val start = (i * 0.08 * RATE).toInt()
            val length = (0.2 * RATE).toInt()
            for (n in 0 until length) {
                val t = n.toDouble() / RATE
                val phase = (hz * t) % 1.0
                val wave = if (kind.wave == "triangle") 1.0 - 4.0 * abs(phase - 0.5) else sin(2 * PI * phase)
                if (start + n < out.size) out[start + n] += (wave * envelope(t)).toFloat()
            }
        }
        return ShortArray(out.size) { (out[it].coerceIn(-1f, 1f) * Short.MAX_VALUE).toInt().toShort() }
    }

    /** Exponential ramps as in `exponentialRampToValueAtTime`, scaled for phone speakers. */
    private fun envelope(t: Double): Double {
        val floor = 0.0001
        val gain = when {
            t <= 0.015 -> floor * exp(ln(PEAK / floor) * t / 0.015)
            t <= 0.16 -> PEAK * exp(ln(floor / PEAK) * (t - 0.015) / 0.145)
            else -> floor
        }
        return gain * LOUDNESS
    }

    private companion object {
        const val RATE = 44_100
        const val PEAK = 0.025

        /** WebAudio's 0.025 peak is very quiet on a phone speaker; lift it while keeping the shape. */
        const val LOUDNESS = 6.0
    }
}
