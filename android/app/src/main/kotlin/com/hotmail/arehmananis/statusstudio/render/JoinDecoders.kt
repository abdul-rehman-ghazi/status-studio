package com.hotmail.arehmananis.statusstudio.render

import android.content.Context
import androidx.annotation.OptIn
import androidx.media3.common.util.Clock
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSourceBitmapLoader
import androidx.media3.exoplayer.mediacodec.MediaCodecInfo
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.transformer.AssetLoader
import androidx.media3.transformer.DefaultAssetLoaderFactory
import androidx.media3.transformer.DefaultDecoderFactory

/**
 * The join's decoders (spec FR-37): software first, hardware only when no software decoder will
 * do. On the Redmi Note 11 one hardware 1080p60 decode leaves no room for the hardware encoder:
 * a second decoder, then the encoder, failed to be created with NO_MEMORY (M46 task 13). Software
 * decoding costs time, not quality, and keeps the chip for the encoder.
 */
@OptIn(markerClass = [UnstableApi::class])
fun softwareFirstAssetLoaderFactory(context: Context): AssetLoader.Factory {
    val decoders = DefaultDecoderFactory.Builder(context)
        .setMediaCodecSelector(softwareFirst)
        .setEnableDecoderFallback(true)
        .build()
    return DefaultAssetLoaderFactory(
        context,
        decoders,
        Clock.DEFAULT,
        DefaultMediaSourceFactory(context),
        DataSourceBitmapLoader(context),
    )
}

/** The phone's decoders with software ones first, keeping each group's own order. */
@OptIn(markerClass = [UnstableApi::class])
private val softwareFirst = MediaCodecSelector { mimeType, requiresSecure, requiresTunneling ->
    MediaCodecSelector.DEFAULT.getDecoderInfos(mimeType, requiresSecure, requiresTunneling)
        .sortedBy { info: MediaCodecInfo -> if (info.softwareOnly) 0 else 1 }
}
