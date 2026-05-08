import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// V1 release signing — android/key.properties 가 있으면 release 키, 없으면 debug 키 fallback (CI 안정성)
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.snowchat.snowchat"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.snowchat.snowchat"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // ABI 제한은 scripts/build_release.sh 의 `flutter build apk
        // --split-per-abi` 옵션에서 처리 — Gradle defaultConfig.ndk.abiFilters
        // 는 Flutter plugin 이 빌드 중 재설정해서 override 불가.

        // 2026-05-08 i18n locale lock (Phase 0). Companion to iOS
        // CFBundleLocalizations=['en'] — strips every locale except
        // English from the APK so the system Resources.getConfiguration
        // for our package falls back to English even on Korean-locale
        // devices. Companion runtime guard (AppCompatDelegate
        // .setApplicationLocales) sits in MainActivity. Together they
        // force ConnectionService's incoming-call UI to render in
        // English, matching the rest of the app and the iOS side.
        // Documented in Documentation/TO-DO/2026-05-07-app-locale-and-i18n.md.
        resourceConfigurations.add("en")
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    // org.signal:libsignal-client 제거 (2026-04-21) — Pure Dart Signal Protocol
    // 전환(Phase 6.x) 으로 Java binding 완전 폐기. SignalStore.kt / SignalBridge.kt
    // 도 함께 삭제. JAR 에 번들된 모든 플랫폼 native lib (.dylib .dll 등) 이
    // APK 에 딸려가던 ~30 MB dead weight 제거.
    implementation("com.google.ai.edge.litertlm:litertlm-android:0.10.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
