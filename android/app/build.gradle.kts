import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties =
    Properties().apply {
        val keystorePropertiesFile = rootProject.file("key.properties")
        if (keystorePropertiesFile.exists()) {
            keystorePropertiesFile.inputStream().use { load(it) }
        }
    }

fun keystoreProperty(name: String): String? =
    (keystoreProperties[name] as String?)?.trim()?.takeIf { it.isNotEmpty() }

val configuredStoreFile: File? =
    keystoreProperty("storeFile")?.let { rawPath ->
        // JDK/Gradle 同时接受 Windows 正斜杠与反斜杠绝对路径；相对路径从 android/ 目录解析
        val candidate = File(rawPath)
        if (candidate.isAbsolute) candidate else rootProject.file(rawPath)
    }

val hasReleaseKeystore =
    keystoreProperty("keyAlias") != null &&
        keystoreProperty("keyPassword") != null &&
        configuredStoreFile != null &&
        configuredStoreFile.exists() &&
        keystoreProperty("storePassword") != null

val releaseKeystoreDiagnostic: String =
    listOfNotNull(
        "keyAlias=${keystoreProperty("keyAlias")?.let { "SET" } ?: "MISSING"}",
        "keyPassword=${keystoreProperty("keyPassword")?.let { "SET" } ?: "MISSING"}",
        "storePassword=${keystoreProperty("storePassword")?.let { "SET" } ?: "MISSING"}",
        configuredStoreFile?.let {
            "storeFile=$it (exists=${it.exists()}, size=${if (it.exists()) it.length() else "-"})"
        } ?: "storeFile=MISSING",
        "storeType=${keystoreProperty("storeType") ?: "PKCS12 (default)"}",
    ).joinToString("; ")

fun isReleaseBuildTask(taskName: String): Boolean {
    return taskName.equals("assembleRelease", ignoreCase = true) ||
        taskName.equals("bundleRelease", ignoreCase = true)
}

android {
    namespace = "com.theohowie.linkstudy"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications 需要 core library desugaring
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.theohowie.linkstudy"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // 显式启用 debug 签名配置的 v1/v2/v3 三种签名。
        // HyperOS/MIUI 的 adb 安装校验（assertCallerAndPackage）要求 v1(JAR) 签名，
        // 仅 v2/v3 签名的 APK 通过 adb 安装会被拒绝并报 "Invalid apk"。
        getByName("debug") {
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
        }
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperty("keyAlias")
                keyPassword = keystoreProperty("keyPassword")
                storeFile = configuredStoreFile
                storePassword = keystoreProperty("storePassword")
                storeType = keystoreProperty("storeType") ?: "PKCS12"
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        getByName("debug") {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

tasks.matching { isReleaseBuildTask(it.name) }.configureEach {
    doFirst {
        if (!hasReleaseKeystore) {
            throw GradleException(
                "Release builds require android/key.properties with keyAlias, " +
                    "keyPassword, storePassword, and a valid (existing) storeFile.\n" +
                    "Diagnostics: $releaseKeystoreDiagnostic",
            )
        }
    }
}

pluginManager.withPlugin("org.jetbrains.kotlin.android") {
    extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension>("kotlin") {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
