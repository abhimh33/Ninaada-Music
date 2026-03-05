# ════════════════════════════════════════════════════════════════
#  PROGUARD/R8 RULES — Ninaada Music (Phase 8, Step 4)
# ════════════════════════════════════════════════════════════════
#
#  Flutter release builds use R8 (Google's replacement for ProGuard).
#  These rules prevent R8 from stripping classes used via reflection,
#  JNI, or serialization by our plugin dependencies.
#
# ════════════════════════════════════════════════════════════════

# ── Flutter Engine ──
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# ── just_audio (ExoPlayer internals) ──
-keep class com.google.android.exoplayer2.** { *; }
-keep class androidx.media3.** { *; }
-dontwarn com.google.android.exoplayer2.**
-dontwarn androidx.media3.**

# ── audio_service (MediaBrowserServiceCompat) ──
-keep class com.ryanheise.audioservice.** { *; }
-keep class androidx.media.** { *; }
-dontwarn com.ryanheise.audioservice.**

# ── audio_session ──
-keep class com.ryanheise.audio_session.** { *; }

# ── Hive (reflection-free, but keep TypeAdapters if added) ──
-keep class com.hivedb.** { *; }
-dontwarn com.hivedb.**

# ── Dio / OkHttp (network layer) ──
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# ── connectivity_plus ──
-keep class dev.fluttercommunity.plus.connectivity.** { *; }

# ── cached_network_image (Glide internals) ──
-keep class com.bumptech.glide.** { *; }
-dontwarn com.bumptech.glide.**

# ── permission_handler ──
-keep class com.baseflow.permissionhandler.** { *; }

# ── share_plus ──
-keep class dev.fluttercommunity.plus.share.** { *; }

# ── url_launcher ──
-keep class io.flutter.plugins.urllauncher.** { *; }

# ── path_provider ──
-keep class io.flutter.plugins.pathprovider.** { *; }

# ── shared_preferences ──
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# ── Android Framework ──
-keep class androidx.core.app.** { *; }
-keep class androidx.lifecycle.** { *; }
-dontwarn androidx.lifecycle.**

# ── Kotlin ──
-keep class kotlin.** { *; }
-dontwarn kotlin.**
-keep class kotlinx.** { *; }
-dontwarn kotlinx.**

# ── General safety ──
# Keep annotations (used by many libraries)
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep enums (used by audio_service, just_audio)
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep Parcelables
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}

# Keep Serializable
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    !static !transient <fields>;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}
