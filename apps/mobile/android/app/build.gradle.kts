import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ─── Keystore Configuration ──────────────────────────────────────────────────
// In CI (GitHub Actions): credentials come from environment variables.
// In local dev: credentials come from android/keystore.properties (gitignored).
// If neither is present, the debug key is used as a fallback for local dev only.
val keystorePropertiesFile = rootProject.file("keystore.properties")
val keystoreBase64 = System.getenv("KEYSTORE_BASE64")
val useReleaseKey = (!keystoreBase64.isNullOrEmpty()) ||
        (keystorePropertiesFile.exists() && keystorePropertiesFile.canRead())

android {
    namespace = "com.chatly.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.chatly.app"
        // Android 5.0+ covers 99.7% of active devices in 2024
        minSdk = 21
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ─── Release Signing ─────────────────────────────────────────────────────
    signingConfigs {
        if (useReleaseKey) {
            create("release") {
                if (!keystoreBase64.isNullOrEmpty()) {
                    // CI: keystore written to file by workflow, path in env
                    val keystorePath = System.getenv("KEYSTORE_PATH")
                    storeFile = if (keystorePath.isNullOrEmpty()) {
                        file("keystore.jks")
                    } else {
                        file(keystorePath)
                    }
                    storePassword = System.getenv("KEYSTORE_PASSWORD") ?: ""
                    keyAlias = System.getenv("KEY_ALIAS") ?: ""
                    keyPassword = System.getenv("KEY_PASSWORD") ?: ""
                } else {
                    // Local dev: read from keystore.properties file
                    val keystoreProperties = Properties()
                    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
                    storeFile = file(keystoreProperties["storeFile"] as String)
                    storePassword = keystoreProperties["storePassword"] as String
                    keyAlias = keystoreProperties["keyAlias"] as String
                    keyPassword = keystoreProperties["keyPassword"] as String
                }
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (useReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                // Local dev without keystore: use debug for local testing only
                signingConfigs.getByName("debug")
            }
            // Enable R8 minification for smaller APK
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            isDebuggable = true
        }
    }

    // ─── APK splits for smaller download size ────────────────────────────────
    splits {
        abi {
            isEnable = true
            reset()
            include("arm64-v8a", "armeabi-v7a", "x86_64")
            isUniversalApk = true  // Also produce a fat APK for sideloading
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
