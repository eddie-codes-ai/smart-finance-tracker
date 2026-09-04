// Imports must come before the plugins block in a .kts build script.
// `java.util.Properties()` cannot be written inline here: inside a Gradle
// Kotlin DSL script, `java` resolves to the Java plugin extension rather than
// the package, so the reference fails to compile.
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing, read from android/key.properties (gitignored, so the
// keystore password never enters the repository). Absent that file the build
// falls back to the debug key, exactly as before, so a fresh clone still
// builds — it just cannot produce a distributable APK.
//
// To create one:
//   keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA \
//           -keysize 2048 -validity 10000 -alias upload
// then write android/key.properties:
//   storeFile=C:/Users/you/upload-keystore.jks
//   storePassword=...
//   keyAlias=upload
//   keyPassword=...
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.smartfinance.smart_finance_tracker"
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
        applicationId = "com.smartfinance.smart_finance_tracker"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                // getProperty returns String?, so no casts are needed - the
                // map-style accessor returns Any? and forced the awkward casts
                // that failed to compile.
                val storePath = keystoreProperties.getProperty("storeFile")
                if (storePath != null) storeFile = file(storePath)
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // A real key when key.properties is present, the debug key when it
            // is not. Play Store will reject a debug-signed upload, so this has
            // to be configured before distribution — but leaving the fallback
            // means nothing breaks for anyone just running the app.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:1.2.2")
}
