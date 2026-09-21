# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Google Play Services
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Multidex
-keep class androidx.multidex.** { *; }

# Google Play Core (deferred components / split install)
# Flutter'in embedding'i bu siniflara referans veriyor, ama uygulama deferred
# component kullanmiyor ve kutuphane bagimlilik olarak eklenmiyor. Kural
# olmayinca R8 "Missing class com.google.android.play.core..." diyip
# minifyReleaseWithR8 asamasinda build'i durduruyordu.
-dontwarn com.google.android.play.core.**

# flutter_local_notifications: zamanlanmis bildirimleri Gson ile
# serilestiriyor. Eklenti kendi consumer proguard kurallarini gondermedigi
# icin R8 bu siniflari kirpinca zamanlanmis bildirimler calismiyor.
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-dontwarn com.google.gson.**

# Keep annotations
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses,EnclosingMethod
-keepattributes SourceFile,LineNumberTable

# OkHttp / networking (used by Firebase)
-dontwarn okhttp3.**
-dontwarn okio.**

# Prevent stripping of native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
