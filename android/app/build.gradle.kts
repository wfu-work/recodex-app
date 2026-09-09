import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use(keystoreProperties::load)
}

fun releaseSigningValue(propertyName: String, environmentName: String): String? =
    System.getenv(environmentName)?.takeIf(String::isNotBlank)
        ?: keystoreProperties.getProperty(propertyName)?.takeIf(String::isNotBlank)

val releaseStoreFilePath = releaseSigningValue("storeFile", "ANDROID_KEYSTORE_PATH")
val releaseStoreFile = releaseStoreFilePath?.let(rootProject::file)
val releaseStorePassword = releaseSigningValue("storePassword", "ANDROID_STORE_PASSWORD")
val releaseKeyAlias = releaseSigningValue("keyAlias", "ANDROID_KEY_ALIAS")
val releaseKeyPassword = releaseSigningValue("keyPassword", "ANDROID_KEY_PASSWORD")
val releaseSigningProblems = mutableListOf<String>()
val allowUnsignedRelease = providers.gradleProperty("allowUnsignedRelease").orNull == "true"

if (releaseStoreFilePath == null) releaseSigningProblems += "storeFile / ANDROID_KEYSTORE_PATH"
if (releaseStoreFilePath != null && releaseStoreFile?.isFile != true) {
    releaseSigningProblems +=
        "keystore file not found: ${releaseStoreFile?.absolutePath ?: releaseStoreFilePath}"
}
if (releaseStorePassword == null) releaseSigningProblems += "storePassword / ANDROID_STORE_PASSWORD"
if (releaseKeyAlias == null) releaseSigningProblems += "keyAlias / ANDROID_KEY_ALIAS"
if (releaseKeyPassword == null) releaseSigningProblems += "keyPassword / ANDROID_KEY_PASSWORD"

val releaseBuildRequested =
    gradle.startParameter.taskNames.any { taskName ->
        taskName.contains("release", ignoreCase = true)
    }

if (releaseBuildRequested && !allowUnsignedRelease && releaseSigningProblems.isNotEmpty()) {
    throw GradleException(
        "Android release signing is not configured: ${releaseSigningProblems.joinToString()}. " +
            "Copy android/key.properties.example to android/key.properties, or provide the " +
            "ANDROID_KEYSTORE_PATH, ANDROID_STORE_PASSWORD, ANDROID_KEY_ALIAS and " +
            "ANDROID_KEY_PASSWORD environment variables.",
    )
}

android {
    namespace = "com.xiaoxi.recodex"
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
        applicationId = "com.xiaoxi.recodex"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningProblems.isEmpty()) {
            create("release") {
                storeFile = requireNotNull(releaseStoreFile)
                storePassword = requireNotNull(releaseStorePassword)
                keyAlias = requireNotNull(releaseKeyAlias)
                keyPassword = requireNotNull(releaseKeyPassword)
            }
        }
    }

    buildTypes {
        release {
            if (!allowUnsignedRelease) {
                signingConfigs.findByName("release")?.let { releaseSigningConfig ->
                    signingConfig = releaseSigningConfig
                }
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
