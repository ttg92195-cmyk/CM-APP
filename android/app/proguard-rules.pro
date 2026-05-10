# ============================================
# CM Movies - ProGuard / R8 Rules
# ============================================

# --- Flutter Framework ---
# Flutter uses dynamic dispatch heavily; keep all Flutter engine classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# --- Firebase ---
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**

# --- Firestore ---
-keep class com.google.cloud.firestore.** { *; }
-keepclassmembers class com.google.cloud.firestore.** { *; }

# --- Firebase Auth ---
-keep class com.google.firebase.auth.** { *; }

# --- Firebase App Check ---
-keep class com.google.firebase.appcheck.** { *; }

# --- Google Play Integrity ---
-keep class com.google.android.play.core.** { *; }
-keep class com.google.android.play.integrity.** { *; }

# --- AndroidX / Jetpack ---
-keep class androidx.** { *; }
-keep interface androidx.** { *; }
-dontwarn androidx.**

# --- Gson (used by Firebase) ---
-keepattributes Signature
-keepattributes *Annotation*
-keep class sun.misc.Unsafe { *; }
-keep class com.google.gson.** { *; }

# --- Protobuf (used by Firestore) ---
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# --- Model / Data Classes ---
# Keep all data models used for Firestore serialization/deserialization
-keep class than.pre.cm.model.** { *; }
-keepclassmembers class than.pre.cm.model.** { *; }

# --- General Rules ---
# Keep source file names & line numbers for crash reports
-keepattributes SourceFile,LineNumberTable

# Hide original source file name in stack traces for security
-renamesourcefileattribute SourceFile

# Remove all logging in release builds
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}
