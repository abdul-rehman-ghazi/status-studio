package com.hotmail.arehmananis.statusstudio.youtube

/**
 * `-J` prints everything yt-dlp knows about one video as JSON, downloading nothing. The cache
 * keeps YouTube's player script and solved challenges between runs, which roughly halves the
 * time; HLS and DASH manifests are skipped because the app can't fetch them in byte ranges.
 */
fun videoInfoOptions(cacheDir: String): List<String> =
    listOf(
        "-J",
        "--no-playlist",
        "--no-warnings",
        "--cache-dir",
        cacheDir,
        "--extractor-args",
        "youtube:skip=hls,dash",
    )

/**
 * [videoInfoOptions] without a JavaScript runtime: yt-dlp then only asks YouTube clients that
 * need no challenge solving, which on a mid-range phone takes about half the time of QuickJS.
 * Some videos may need the slower run.
 */
fun quickVideoInfoOptions(cacheDir: String): List<String> =
    videoInfoOptions(cacheDir) + "--no-js-runtimes"

/**
 * The audio only, for Groq to write the script when the video has no captions (spec FR-36).
 * yt-dlp writes `<outputPath>.part` and renames it when whole, so a file at [outputPath] is
 * complete.
 */
fun audioDownloadOptions(cacheDir: String, outputPath: String): List<String> =
    listOf(
        "-f",
        "bestaudio[ext=m4a]/bestaudio",
        "--no-playlist",
        "--no-warnings",
        "--no-mtime",
        "--cache-dir",
        cacheDir,
        "-o",
        outputPath,
    )

fun videoUrl(videoId: String): String = "https://www.youtube.com/watch?v=$videoId"
