package com.hotmail.arehmananis.statusstudio.render

import android.content.Context
import android.os.Looper
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
import androidx.media3.transformer.EditedMediaItem
import java.util.Collections
import java.util.IdentityHashMap

/**
 * Decoders for the join's two layers (spec FR-37). A mid-range phone has one hardware decoder's
 * worth of 1080p60 (the Redmi Note 11 failed the second with NO_MEMORY, M46 task 13), so the lower
 * layer, which only decodes around each join, prefers software decoders, and the upper layer falls
 * back to software when the hardware one is still busy as one cut hands over to the next.
 */
@OptIn(markerClass = [UnstableApi::class])
class LayeredAssetLoaderFactory(context: Context) : AssetLoader.Factory {
    private val upper = assetLoaderFactory(context, MediaCodecSelector.DEFAULT)
    private val lower = assetLoaderFactory(context, softwareFirst)

    /** Items are told apart by identity: equal-looking items can sit in both layers. */
    private val lowerItems: MutableSet<EditedMediaItem> =
            Collections.newSetFromMap(IdentityHashMap())

    /** Marks [item] as the lower layer's, to be decoded in software first. */
    fun inLowerLayer(item: EditedMediaItem): EditedMediaItem {
        lowerItems.add(item)
        return item
    }

    override fun createAssetLoader(
            editedMediaItem: EditedMediaItem,
            looper: Looper,
            listener: AssetLoader.Listener,
            compositionSettings: AssetLoader.CompositionSettings,
    ): AssetLoader {
        val factory = if (editedMediaItem in lowerItems) lower else upper
        return factory.createAssetLoader(editedMediaItem, looper, listener, compositionSettings)
    }
}

/** The phone's decoders with software ones first, keeping each group's own order. */
@OptIn(markerClass = [UnstableApi::class])
private val softwareFirst = MediaCodecSelector { mimeType, requiresSecure, requiresTunneling ->
    MediaCodecSelector.DEFAULT.getDecoderInfos(mimeType, requiresSecure, requiresTunneling)
            .sortedBy { info: MediaCodecInfo -> if (info.softwareOnly) 0 else 1 }
}

@OptIn(markerClass = [UnstableApi::class])
private fun assetLoaderFactory(
        context: Context,
        selector: MediaCodecSelector
): AssetLoader.Factory {
    val decoders =
            DefaultDecoderFactory.Builder(context)
                    .setMediaCodecSelector(selector)
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
