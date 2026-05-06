# R8 / ProGuard rules for CropCare AI release builds.
#
# tflite_flutter pulls in TensorFlow Lite Java bindings that reference
# the optional GPU delegate (org.tensorflow.lite.gpu.*). We do not ship
# the GPU native libs, so those references resolve to "missing class"
# warnings under R8. Keep the TFLite classes and silence the warnings
# for the GPU delegate package — the missing classes are never reached
# at runtime on devices we target (CPU-only inference).

-keep class org.tensorflow.lite.** { *; }
-keep interface org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.gpu.**
-dontwarn org.tensorflow.lite.nnapi.**

# Keep Flutter's embedding (defensive — usually preserved automatically).
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }

# Flutter references the Play Core split-install API to support
# Play-Store-delivered deferred components. We don't use that feature
# (the app ships as a single APK), so silence the missing-class
# warnings. The references are dead at runtime in this build.
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

# Supabase / GoTrue clients use reflection on Kotlin metadata.
-keep class kotlinx.serialization.** { *; }
-keep class kotlin.Metadata { *; }
-keepclassmembers class kotlin.Metadata { *; }
