import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// SECURITY (audit DMB-020): release builds must be signed with the bank's release key.
// The key material is provided out-of-band (CI secret) through android/key.properties
// (git-ignored):  storeFile=..., storePassword=..., keyAlias=..., keyPassword=...
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    // NOTE (audit DMB-020, BLOCKED): namespace/applicationId still use the template
    // "com.example" id because the Firebase registration (google-services.json) and
    // existing installs depend on it. Changing it requires a new Firebase app and a
    // migration plan — see docs/REMEDIATION_CHANGELOG.md.
    namespace = "com.example.m_banking_bpr"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.m_banking_bpr"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Never fall back to the debug key for release artifacts.
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

// Fail release packaging explicitly when no release keystore is configured.
gradle.taskGraph.whenReady {
    val releasePackaging = allTasks.any {
        (it.name.startsWith("assemble") || it.name.startsWith("bundle") || it.name.startsWith("package")) &&
            it.name.endsWith("Release")
    }
    if (releasePackaging && !hasReleaseKeystore) {
        throw GradleException(
            "Release build membutuhkan android/key.properties dan keystore rilis bank. " +
                "Build debug/profile tetap dapat dijalankan tanpa keystore."
        )
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
