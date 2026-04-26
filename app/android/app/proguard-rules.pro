# libsignal-client ProGuard rules
# Keep all Signal Protocol classes (uses reflection internally)
-keep class org.signal.libsignal.** { *; }
-keep class org.whispersystems.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep SignalBridge and SignalStore (called via reflection from Flutter MethodChannel)
-keep class com.snowchat.snowchat.SignalBridge { *; }
-keep class com.snowchat.snowchat.InMemorySignalProtocolStore { *; }

# LiteRT-LM SDK (Phase 10: on-device AI)
-keep class com.google.ai.edge.litertlm.** { *; }
-keep class com.snowchat.snowchat.LiteRtLmBridge { *; }

# OkHttp (used by various dependencies — suppress R8 missing class warnings)
-dontwarn org.bouncycastle.jsse.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
-dontwarn javax.lang.model.**
