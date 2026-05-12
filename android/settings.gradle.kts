import java.io.File

pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            var searchDir: File? = settingsDir
            var localPropertiesFile: File? = null

            repeat(5) {
                val directCandidate = searchDir?.resolve("local.properties")
                if (directCandidate?.isFile == true) {
                    localPropertiesFile = directCandidate
                    return@repeat
                }

                val androidCandidate = searchDir?.resolve("android/local.properties")
                if (androidCandidate?.isFile == true) {
                    localPropertiesFile = androidCandidate
                    return@repeat
                }

                searchDir = searchDir?.parentFile
            }

            localPropertiesFile?.inputStream()?.use { properties.load(it) }

            val flutterSdkPath = properties.getProperty("flutter.sdk")
                ?: System.getenv("FLUTTER_ROOT")
                ?: System.getenv("FLUTTER_HOME")
            require(flutterSdkPath != null) {
                "Flutter SDK not found. Set flutter.sdk in android/local.properties or FLUTTER_ROOT."
            }
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
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
