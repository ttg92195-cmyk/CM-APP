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

# --- Google Play Core (optional — Flutter references but not always included) ---
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
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
