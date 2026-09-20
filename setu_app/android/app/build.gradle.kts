import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// SEP 2026 SECURITY HARDENING: real release signing, wired but not
// hardcoded.
//
// FOUND (not fixed silently -- documented here and in
// docs/SECURITY_SCORECARD.md): the release buildType previously did
// `signingConfig = signingConfigs.getByName("debug")` unconditionally
// -- every release build was signed with the shared, well-known Flutter
// debug key, not a real release key. That is a genuine problem for
// anything beyond local testing (Google Play itself rejects a
// debug-signed release AAB/APK; app signing is also what proves updates
// come from the same publisher).
//
// NOT FIXED BY INVENTING A KEYSTORE: this sandbox has no real signing
// key, and creating a throwaway one to "close" this finding would be a
// fake control (`android/key.properties.example` documents the exact
// shape a real one needs, but never a working keystore). Instead:
// - android/.gitignore and the repo root .gitignore already excluded
//   key.properties and *.keystore/*.jks (confirmed unchanged, not
//   newly added this pass) -- the mechanism to keep a real key out of
//   git was already in place, just never wired into this file.
// - If android/key.properties exists (gitignored, developer-provided,
//   see key.properties.example), it's now actually used to sign
//   release builds.
// - If it does NOT exist, release still falls back to the debug key
//   (so `flutter build apk` keeps working for local/demo builds without
//   extra setup) but now prints a loud, impossible-to-miss warning at
//   build time instead of silently shipping a debug-signed release.
// android/key.properties -- matches the location .gitignore already
// excludes (both android/.gitignore's `key.properties` and the repo
// root .gitignore's `android/key.properties` point here).
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} else {
    logger.warn(
        "\n" +
        "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n" +
        "  WARNING: android/key.properties not found.\n" +
        "  Release build will be signed with the DEBUG key -- this is NOT a\n" +
        "  real release signature and must not be distributed/uploaded to\n" +
        "  Google Play. See android/key.properties.example.\n" +
        "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n"
    )
}

android {
    namespace = "com.setu.setu_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.setu.setu_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // Not enabled before this pass. Shrinking + obfuscation on
            // release is real, low-risk hardening (harder to
            // decompile/re-skin the app, smaller attack surface for
            // reverse engineering the mesh protocol implementation) --
            // proguard-rules.pro below keeps Flutter's own required
            // classes plus Play Services Nearby (this app's one
            // dependency that talks to native code / uses reflection
            // internally) so this does not risk breaking the mesh
            // layer at runtime. NOT verified by an actual release build
            // in this sandbox (no Android SDK/Gradle available) -- flag
            // this explicitly rather than claim it was tested.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("com.google.android.gms:play-services-nearby:19.3.0")
}

flutter {
    source = "../.."
}
