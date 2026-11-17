import java.io.File
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The repo is public (spec §9 Signing), so the key lives outside it. Without one a release
// build is unsigned, never debug-signed: F-Droid signs its own builds.
val keystorePropertiesFile: File? = listOfNotNull(
    System.getenv("STATUS_STUDIO_KEY_PROPERTIES")?.let { File(it) },
    File(System.getProperty("user.home"), ".status-studio/key.properties"),
    rootProject.file("key.properties"),
).firstOrNull { it.exists() }
val keystoreProperties = Properties()
keystorePropertiesFile?.let { keystoreProperties.load(FileInputStream(it)) }

// storeFile is relative to the properties file; the older android/key.properties named it
// relative to android/app, so that is tried when nothing is beside the properties file.
fun keystoreFile(storeFilePath: String): File {
    val besideProperties = keystorePropertiesFile!!.parentFile.resolve(storeFilePath)
    return if (besideProperties.exists()) besideProperties else file(storeFilePath)
}

android {
    namespace = "com.hotmail.arehmananis.statusstudio"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications needs java.time on older Android.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.hotmail.arehmananis.statusstudio"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile != null) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = (keystoreProperties["storeFile"] as String?)?.let { keystoreFile(it) }
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    // Google's dependency block is encrypted with Google's key, so nobody else can check it;
    // IzzyOnDroid's scan flags it and F-Droid's reproducible builds want it gone (spec M79).
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
            // Flutter turns R8 on for release builds, but FFmpeg Kit binds JNI
            // methods by name and youtubedl-android unpacks Python with Commons
            // Compress and reads yt-dlp's JSON with Jackson, all by reflection,
            // and none ships keep rules. Shrunk, the app crashed at start (spec
            // §15, M65). The APK is almost all native code, so R8 saved little.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // youtubedl-android ships Python as libpython.zip.so and unpacks it from the installed
    // native library folder, which only exists when native libraries are extracted.
    packaging {
        jniLibs {
            useLegacyPackaging = true
            // A zip, not an ELF library: stripping it only prints errors.
            keepDebugSymbols += "**/libpython.zip.so"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // The final render (spec §5): hardware H.264/AAC, crop, blur and overlay.
    implementation("androidx.media3:media3-transformer:1.11.1")
    implementation("androidx.media3:media3-effect:1.11.1")
    implementation("androidx.media3:media3-common:1.11.1")
    // IntentCompat: the typed getParcelableExtra is broken on API 33.
    implementation("androidx.core:core:1.13.1")
    // yt-dlp with Python and QuickJS (spec FR-35): reads video links, updates itself.
    implementation("io.github.junkfood02.youtubedl-android:library:0.18.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    testImplementation("junit:junit:4.13.2")
}
