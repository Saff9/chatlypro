# Flutter / Hive ProGuard Rules

# Keep Hive type adapters
-keep class * extends com.google.protobuf.GeneratedMessageLite { *; }
-keep class * implements com.hive.** { *; }

# Keep flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Keep cryptography library
-keep class at.favre.lib.crypto.** { *; }

# Dio / OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**

# Dart/Flutter essentials
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# JSON / Serialization
-keepattributes Signature
-keepattributes *Annotation*
