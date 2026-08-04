# ProGuard rules for OpenAgent
# ========================================

# Flutter engine classes (keep all)
-keep class io.flutter.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }

# MNN-LLM native library (keep JNI methods)
-keep class com.openagent.mnn_llm.** { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}

# Kotlin coroutines (keep internal classes)
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}

# Keep all MethodChannel handlers
-keep class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Keep Parcelable implementations
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Keep serialization
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Avoid obfuscation of enum classes
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}