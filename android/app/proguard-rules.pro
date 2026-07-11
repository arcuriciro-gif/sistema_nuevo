# Flutter / Play release
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Gson / JSON used by plugins
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }

# Thermal / Bluetooth plugins
-keep class com.example.printbluetooththermal.** { *; }
-dontwarn com.example.printbluetooththermal.**
