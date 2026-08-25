import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// v1.5.0-T2 (P4): real release signing — provide key.properties (or KEY_*
// env vars) with keystorePath/keystorePassword/keyAlias/keyPassword.
// Without a keystore the build FALLS BACK TO THE DEBUG KEY and prints a loud
// warning, so a store-bound APK can never be signed invisibly.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun signingValue(key: String): String? =
    System.getenv(key.uppercase()) ?: keystoreProperties.getProperty(key)

android {
    namespace = "com.ghita.ghita_edit"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ghita.ghita_edit"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val storeFilePath = signingValue("keystorePath")
            if (storeFilePath != null) {
                storeFile = file(storeFilePath)
                storePassword = signingValue("keystorePassword")
                keyAlias = signingValue("keyAlias")
                keyPassword = signingValue("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (signingConfigs.getByName("release").storeFile != null) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "!!! Ghita Edit: release APK signed with the DEBUG key — " +
                    "provide android/key.properties (keystorePath/keystorePassword/" +
                    "keyAlias/keyPassword) for a shippable build !!!"
                )
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("../../native_engine/CMakeLists.txt")
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
