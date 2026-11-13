package com.hotmail.arehmananis.statusstudio.render

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.roundToInt

/** −1 dBFS: headroom for the AAC encoder, whose output can overshoot the input's peaks. */
private const val CEILING = 0.891f
private const val RELEASE_MS = 150.0
private const val SHORT_SCALE = 32768f

/**
 * Raises the sound by [gain], then holds peaks under [CEILING] (spec FR-42). The limiter has an
 * instant attack, so no sample is ever over the ceiling, and a 150 ms release, so the level comes
 * back smoothly after a loud moment instead of pumping.
 */
@OptIn(markerClass = [UnstableApi::class])
class LoudnessBoost(private val gain: Float) : BaseAudioProcessor() {
    private var limiterGain = 1f
    private var releasePerFrame = 0f
    private var frame = FloatArray(0)

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        val encoding = inputAudioFormat.encoding
        if (encoding != C.ENCODING_PCM_16BIT && encoding != C.ENCODING_PCM_FLOAT) {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }
        releasePerFrame = (1 - exp(-1000.0 / (RELEASE_MS * inputAudioFormat.sampleRate))).toFloat()
        frame = FloatArray(inputAudioFormat.channelCount)
        return inputAudioFormat
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val frames = inputBuffer.remaining() / inputAudioFormat.bytesPerFrame
        val output = replaceOutputBuffer(inputBuffer.remaining()).order(ByteOrder.nativeOrder())
        val input = inputBuffer.order(ByteOrder.nativeOrder())
        repeat(frames) {
            readFrame(input)
            val boostedPeak = frame.maxOf { abs(it) } * gain
            writeFrame(output, gain * limiterGainFor(boostedPeak))
        }
        output.flip()
    }

    private fun limiterGainFor(boostedPeak: Float): Float {
        limiterGain += (1f - limiterGain) * releasePerFrame
        if (boostedPeak * limiterGain > CEILING) limiterGain = CEILING / boostedPeak
        return limiterGain
    }

    private fun readFrame(input: ByteBuffer) {
        val isFloat = inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT
        for (channel in frame.indices) {
            frame[channel] = if (isFloat) input.getFloat() else input.getShort() / SHORT_SCALE
        }
    }

    private fun writeFrame(output: ByteBuffer, frameGain: Float) {
        val isFloat = inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT
        for (sample in frame) {
            val scaled = sample * frameGain
            if (isFloat) {
                output.putFloat(scaled)
            } else {
                output.putShort((scaled * SHORT_SCALE).roundToInt().coerceIn(-32768, 32767).toShort())
            }
        }
    }

    // Both flush paths reset: which one Media3 calls at an item's start differs by version.
    override fun onFlush() {
        limiterGain = 1f
    }

    override fun onFlush(streamMetadata: AudioProcessor.StreamMetadata) {
        limiterGain = 1f
    }

    override fun onReset() {
        limiterGain = 1f
    }
}
