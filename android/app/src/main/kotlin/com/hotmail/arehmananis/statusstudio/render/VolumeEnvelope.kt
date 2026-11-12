package com.hotmail.arehmananis.statusstudio.render

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Scales one item's sound by [volumeAtMs], given the time into the item (spec FR-37). Time is
 * counted in frames from the item's first sample, which for a clipped item is its clip start.
 * Each item gets its own envelope, so the count never carries over to the next item.
 */
@OptIn(markerClass = [UnstableApi::class])
class VolumeEnvelope(private val volumeAtMs: (Long) -> Float) : BaseAudioProcessor() {
    private var framesDone = 0L

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        val encoding = inputAudioFormat.encoding
        if (encoding != C.ENCODING_PCM_16BIT && encoding != C.ENCODING_PCM_FLOAT) {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }
        return inputAudioFormat
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val format = inputAudioFormat
        val frames = inputBuffer.remaining() / format.bytesPerFrame
        val output = replaceOutputBuffer(inputBuffer.remaining()).order(ByteOrder.nativeOrder())
        val input = inputBuffer.order(ByteOrder.nativeOrder())
        repeat(frames) {
            val volume = volumeAtMs(framesDone * 1000 / format.sampleRate)
            repeat(format.channelCount) { scaleSample(input, output, volume) }
            framesDone++
        }
        output.flip()
    }

    private fun scaleSample(input: ByteBuffer, output: ByteBuffer, volume: Float) {
        if (inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT) {
            output.putFloat(input.getFloat() * volume)
            return
        }
        output.putShort((input.getShort() * volume).toInt().toShort())
    }

    // Both flush paths reset: which one Media3 calls at an item's start differs by version.
    override fun onFlush() {
        framesDone = 0
    }

    override fun onFlush(streamMetadata: AudioProcessor.StreamMetadata) {
        framesDone = 0
    }

    override fun onReset() {
        framesDone = 0
    }
}
