import groovy.json.JsonSlurper
import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // Reads android/app/google-services.json, which `flutterfire configure`
    // writes. The build FAILS with "File google-services.json is missing" until
    // it has been run — that is deliberate: the alternative is an app that
    // builds fine and silently never receives a push.
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// android/key.properties (gitignored) points at the Play upload keystore.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) load(FileInputStream(keystorePropertiesFile))
}

// Flutter hands each --dart-define to Gradle base64-encoded, comma-joined, as -Pdart-defines.
val dartDefines: Map<String, String> = (findProperty("dart-defines") as String?).orEmpty()
    .split(",").filter { it.isNotEmpty() }
    .map { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
    .associate { it.substringBefore("=") to it.substringAfter("=", "") }

// Refuse release builds that would only fail later: the old debug-key fallback
// was rejected by Play Console, and a bare `flutter build` ships localhost URLs.
gradle.taskGraph.whenReady {
    if (allTasks.none { it.name.contains("Release") }) return@whenReady
    if (!keystorePropertiesFile.exists()) {
        throw GradleException(
            "android/key.properties is missing — release builds must be signed with the upload key."
        )
    }
    if (dartDefines["API_BASE_URL"]?.startsWith("https://") != true) {
        throw GradleException(
            "No --dart-define=API_BASE_URL=https://… — this build would call localhost. Use scripts/release_android.sh."
        )
    }
    // An Android client ID here compiles fine, then fails on the phone as a bare "An error occurred".
    @Suppress("UNCHECKED_CAST")
    val webClientIds = ((JsonSlurper().parse(file("google-services.json")) as Map<String, Any?>)["client"] as List<Map<String, Any?>>)
        .flatMap { it["oauth_client"] as List<Map<String, Any?>>? ?: emptyList() }
        .filter { it["client_type"] == 3 }
        .map { it["client_id"] }
    val serverClientId = dartDefines["GOOGLE_SERVER_CLIENT_ID"]
    if (serverClientId != null && serverClientId !in webClientIds) {
        throw GradleException(
            "GOOGLE_SERVER_CLIENT_ID must be the Web OAuth client from google-services.json (${webClientIds.joinToString()}), " +
                "not an Android client — Android clients are matched by package name + SHA-1 and never go in the app."
        )
    }
}

android {
    namespace = "com.example.social_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Final published id — register THIS (+ SHA-1) on the Google OAuth Android client.
        applicationId = "com.ismailkarroud.ntripi"
        // google_sign_in (Credential Manager) requires API 21+; never go below it.
        minSdk = maxOf(21, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}
