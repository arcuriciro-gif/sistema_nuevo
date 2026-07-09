pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")

// Injected plugin includes to ensure plugin Android code is compiled locally.
// These point at the plugin Android projects in the local pub cache.
include(":file_picker")
project(":file_picker").projectDir = file("C:/Users/Matia/AppData/Local/Pub/Cache/hosted/pub.dev/file_picker-11.0.2/android")

include(":flutter_plugin_android_lifecycle")
project(":flutter_plugin_android_lifecycle").projectDir = file("C:/Users/Matia/AppData/Local/Pub/Cache/hosted/pub.dev/flutter_plugin_android_lifecycle-2.0.35/android")
