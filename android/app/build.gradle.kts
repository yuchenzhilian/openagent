plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.openagent.openagent"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.openagent.openagent"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 28  // MNN-LLM arm64-v8a kernels require API 28+
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Only build for arm64-v8a to reduce APK size.
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            // Enable R8 code shrinking and resource shrinking to reduce APK size.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
    // Coroutines: used by AutomationChannel for the non-blocking MethodChannel handler.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    // AndroidX annotations: @RequiresApi / @Keep used by helpers.
    implementation("androidx.annotation:annotation:1.8.2")

    // Optional (L2 Shizuku SDK). Commented out by default so the APK builds on
    // machines without the Shizuku maven repo cached. Uncomment when you want
    // the REAL Shizuku binder (instead of reflection + Runtime.exec fallback).
    //
    // repositories { mavenCentral() }
    // implementation("dev.rikka.shizuku:api:13.1.5")
    // implementation("dev.rikka.shizuku:provider:13.1.5")
}
