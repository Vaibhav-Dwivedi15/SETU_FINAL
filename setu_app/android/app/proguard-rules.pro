# SEP 2026: added alongside enabling isMinifyEnabled/isShrinkResources
# for release builds (see build.gradle.kts's own comment for why).
# Conservative on purpose -- these are well-known, standard keep rules
# for exactly this app's dependency surface (Flutter + Play Services
# Nearby), not tuned/verified against an actual release build in this
# sandbox (no Android SDK/Gradle available here). If a real build finds
# something else needs keeping, add it here rather than disabling
# shrinking entirely.

# Flutter's own engine/plugin classes. Flutter typically ships its own
# consumer proguard rules via its AAR, but keeping this explicit avoids
# depending on that alone.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Google Play Services Nearby (com.google.android.gms:play-services-nearby)
# -- the one non-Flutter dependency this app has, and the one the whole
# mesh layer's connectivity depends on. Its internal classes use
# reflection/AIDL-generated code that R8 cannot safely reason about
# statically; stripping/renaming them risks a runtime crash in
# NearbyConnectionsManager.kt that would only surface on-device, not at
# build time. Kept wholesale rather than narrowed to specific classes,
# matching Google's own published ProGuard guidance for this library.
-keep class com.google.android.gms.nearby.** { *; }
-keep class com.google.android.gms.common.** { *; }

# This app's own mesh MethodChannel/EventChannel handlers -- referenced
# from Dart by string channel name, not by a Java/Kotlin type reference
# R8 can trace, so they must be kept explicitly rather than assumed
# reachable.
-keep class com.setu.mesh.** { *; }
-keep class com.setu.setu_app.** { *; }

# Block 1 (mesh-stability): the first real release build failed in R8 with
# "Missing class com.google.android.play.core.*". Flutter's embedding
# references Play Core for DEFERRED COMPONENTS (PlayStoreDeferredComponentManager),
# a feature this app does not use and whose library is not a dependency.
# These are the rules R8 itself generated in missing_rules.txt; the classes
# are never loaded at runtime here.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
