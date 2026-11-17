# Code reached by name, which R8 can't see (spec M65, M82). A missing rule only
# shows when that code runs, so every release APK is checked on a phone.

# FFmpeg Kit's native library registers AbiDetect's methods on load and calls
# back into Java for logs and statistics.
-keep class com.antonkarpenko.ffmpegkit.** { *; }

# youtubedl-android: Jackson maps yt-dlp's JSON onto its mapper classes.
-keep class com.yausername.** { *; }

# Commons Compress makes zip extra fields by reflection while youtubedl-android
# unpacks Python.
-keep class org.apache.commons.compress.** { *; }
# Its optional XZ codec isn't bundled; python.zip doesn't use XZ.
-dontwarn org.tukaani.xz.**

-keep class com.fasterxml.jackson.** { *; }
-keepattributes Signature,InnerClasses,EnclosingMethod,*Annotation*
-dontwarn com.fasterxml.jackson.databind.ext.**

# TensorFlow Lite's native library binds its Java classes over JNI.
-keep class org.tensorflow.lite.** { *; }
