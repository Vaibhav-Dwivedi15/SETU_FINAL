import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// BLOCK 3 -- RELEASE SIGNING (supersedes the Sep 2026 note that used to be here):
//
// A release build can NEVER silently use the debug key. Signing material comes from either
//   1. android/key.properties (gitignored; see key.properties.example), or
//   2. environment variables (for CI secrets): SETU_RELEASE_STORE_FILE, SETU_RELEASE_STORE_PASSWORD,
//      SETU_RELEASE_KEY_ALIAS, SETU_RELEASE_KEY_PASSWORD.
// If neither is complete, any task that produces a signed release artifact (assembleRelease,
// packageRelease, bundleRelease, signReleaseBundle -- i.e. `flutter build apk|appbundle --release`)
// FAILS with an explicit message. Debug builds, unit tests and `assembleDebug` are unaffected.
// No keystore or password is committed; the real production keystore must be generated and
// held by the release owner (keytool command in key.properties.example).
val keystorePropertiesFile = rootProject.file("key.properties")
val fileProps = Properties()
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { fileProps.load(it) }
}

fun signingValue(propKey: String, envKey: String): String? =
    (fileProps.getProperty(propKey) ?: System.getenv(envKey))?.trim()?.takeIf { it.isNotEmpty() && it != "REPLACE_ME" }

val releaseStoreFile = signingValue("storeFile", "SETU_RELEASE_STORE_FILE")
val releaseStorePassword = signingValue("storePassword", "SETU_RELEASE_STORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "SETU_RELEASE_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "SETU_RELEASE_KEY_PASSWORD")

val releaseSigningProblem: String? = when {
    releaseStoreFile == null || releaseStorePassword == null || releaseKeyAlias == null || releaseKeyPassword == null ->
        "Release signing is not configured (android/key.properties or SETU_RELEASE_* environment variables are missing or incomplete)."
    !file(releaseStoreFile).isFile ->
        "Release keystore file not found: the configured storeFile does not exist."
    else -> null
}

gradle.taskGraph.whenReady {
    val signedReleaseTasks = setOf("assembleRelease", "packageRelease", "bundleRelease", "signReleaseBundle", "packageReleaseBundle")
    val requested = allTasks.filter { it.project == project && it.name in signedReleaseTasks }
    if (requested.isNotEmpty() && releaseSigningProblem != null) {
        throw GradleException(
            "\n\nSETU RELEASE BUILD REFUSED: " + releaseSigningProblem + "\n" +
            "A release build is never signed with the debug key. Create a production keystore and\n" +
            "android/key.properties (see android/key.properties.example), or export the SETU_RELEASE_*\n" +
            "variables, then re-run. Debug builds are unaffected.\n"
        )
    }
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
        if (releaseSigningProblem == null) {
            create("release") {
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
            }
        }
    }

    buildTypes {
        release {
            // null when signing is not configured -- and the task-graph check above then refuses
            // to build. There is deliberately NO fallback to signingConfigs["debug"].
            signingConfig = signingConfigs.findByName("release")

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

    // Sep 21 2026 (Vib, Bulk Sprint 4): native Ed25519 signature
    // verification (see com.setu.mesh.SignatureVerifier). Declared as the
    // standard Maven Central coordinate, NOT the sandbox-local file path
    // used to validate the verification logic offline (see
    // docs/security/NATIVE_SIGNATURE_TEST_VECTOR.md and
    // docs/security/NATIVE_SIGNATURE_VERIFICATION_DESIGN.md) -- that
    // local jar (/usr/share/java/bcprov-1.77.jar) was only ever a
    // standalone javac/java test harness outside Gradle, and hardcoding
    // its sandbox-specific path here would silently break on a real
    // developer machine or CI, where this must resolve from Maven
    // Central (or a mirror) normally. This exact build has NOT been
    // compiled with the real Android/Gradle toolchain in this sandbox
    // (no Flutter/Android SDK present, and Maven Central itself is
    // network-blocked here -- see docs/BUILD_AND_VALIDATION.md) --
    // flagged explicitly rather than claimed as a working build.
    implementation("org.bouncycastle:bcprov-jdk18on:1.78.1")

    // Sep 21 2026 (Vib, Bulk Sprint 4): local JVM unit tests for
    // src/test/kotlin (see PacketRelayEngineTest.kt). org.json:json is
    // needed here specifically because Android's REAL bundled org.json
    // implementation is a stub that throws UnsupportedOperationException
    // outside an actual device/emulator -- this standalone Maven artifact
    // provides a real, working implementation for local (non-instrumented)
    // unit tests, which is the standard, well-known workaround for this
    // exact situation (not something invented for this project). Neither
    // of these two test dependencies has been resolved/verified in this
    // sandbox -- Maven Central remains network-blocked here (see
    // docs/BUILD_AND_VALIDATION.md) -- so this is a documented-intent
    // addition, not a confirmed-working one.
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20231013")
}

flutter {
    source = "../.."
}
