# Flutter & Android core keep rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.example.m_banking_bpr.** { *; }

# Firebase / Google Play Services
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.errorprone.annotations.**

# PDFx / PdfRenderer & Biometric / SecureStorage
-keep class io.scer.pdfx.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class androidx.biometric.** { *; }

# Gson / OkHttp / Conscrypt
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.conscrypt.**

# Flutter Local Notifications (Gson reflection in release R8)
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# Flutter engine references Play Core only for deferred components, which this app does
# not use (no deferred-components in pubspec): R8 must not fail on the absent classes.
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
