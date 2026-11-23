import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// SECURITY (audit DMB-020 / DB-H8): release builds MUST be signed with the bank's release
// key. There is no debug-key fallback for release: without a complete keystore
// configuration every release task fails. The key material is provided out-of-band
// (CI secret / bank key custodian) through a git-ignored properties file:
//   android/key.properties  or  the file named by DMB_ANDROID_KEY_PROPERTIES
//   storeFile=..., storePassword=..., keyAlias=..., keyPassword=...
// The signing certificate digest is pinned on the server for Android Key Attestation
// (DEVICE_ATTESTATION_ANDROID_CERT_SHA256), so the same key must sign every release.
val keystoreProperties = Properties()
val keystorePropertiesFile = System.getenv("DMB_ANDROID_KEY_PROPERTIES")?.takeIf { it.isNotBlank() }?.let { file(it) }
    ?: rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
val releaseSigningProblem: String? = when {
    !keystorePropertiesFile.exists() -> "file konfigurasi keystore release tidak ditemukan (" + keystorePropertiesFile.path + ")"
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword").any { keystoreProperties.getProperty(it).isNullOrBlank() } ->
        "key.properties harus berisi storeFile, storePassword, keyAlias, keyPassword"
    !file(keystoreProperties.getProperty("storeFile")).exists() -> "storeFile keystore release tidak ditemukan"
    else -> null
}
val hasReleaseKeystore = releaseSigningProblem == null

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

    // Build identity from the Flutter dart-defines (--dart-define-from-file=config/<flavor>.json).
    // HTTP (cleartext) is only permitted for local/development flavors and debug builds;
    // staging/production releases use the HTTPS-only network security config.
    val dartDefines: Map<String, String> = (project.findProperty("dart-defines") as String?)
        ?.split(",")
        ?.mapNotNull { runCatching { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }.getOrNull() }
        ?.mapNotNull { kv -> kv.split("=", limit = 2).takeIf { it.size == 2 }?.let { it[0] to it[1] } }
        ?.toMap() ?: emptyMap()
    val appFlavor = dartDefines["APP_FLAVOR"]?.trim()?.lowercase().orEmpty()
    val apiBaseUrl = dartDefines["API_BASE_URL"]?.trim().orEmpty()
    val testingFlavor = appFlavor == "local" || appFlavor == "development"
    project.extra["dmbAppFlavor"] = appFlavor
    project.extra["dmbApiBaseUrl"] = apiBaseUrl

    defaultConfig {
        applicationId = "com.example.m_banking_bpr"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        manifestPlaceholders["dmbAppFlavor"] = appFlavor.ifEmpty { "unspecified" }
        manifestPlaceholders["dmbApiHttps"] = apiBaseUrl.startsWith("https://").toString()
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
        debug {
            manifestPlaceholders["usesCleartextTraffic"] = "true"
            manifestPlaceholders["networkSecurityConfig"] = "network_security_config_cleartext"
        }
        release {
            isDebuggable = false
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            manifestPlaceholders["usesCleartextTraffic"] = testingFlavor.toString()
            manifestPlaceholders["networkSecurityConfig"] =
                if (testingFlavor) "network_security_config_cleartext" else "network_security_config"
            // Production/staging wajib release keystore; local/development boleh fallback ke debug key untuk testing.
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else if (testingFlavor) {
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

// Every release task fails without the official keystore (debug builds are unaffected).
gradle.taskGraph.whenReady {
    val releaseTask = allTasks.any { it.project == project && it.name.contains("Release") && (it.name.startsWith("assemble") || it.name.startsWith("bundle") || it.name.startsWith("package")) }
    val flavor = project.extra["dmbAppFlavor"] as String
    val apiUrl = project.extra["dmbApiBaseUrl"] as String
    if (releaseTask && flavor.isEmpty()) {
        throw GradleException("Build release ditolak: APP_FLAVOR tidak diset. Gunakan --dart-define-from-file=config/<flavor>.json.")
    }
    if (releaseTask && (flavor == "production" || flavor == "staging") && !apiUrl.startsWith("https://")) {
        throw GradleException("Build release " + flavor + " ditolak: API_BASE_URL wajib https:// (NEEDS BANK INPUT bila belum tersedia).")
    }
    if (releaseTask && (flavor != "local" && flavor != "development") && !hasReleaseKeystore) {
        throw GradleException("Build release ditolak: " + releaseSigningProblem + ". Release wajib ditandatangani keystore resmi bank (lihat docs/DEPLOYMENT_AND_CICD.md).")
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
