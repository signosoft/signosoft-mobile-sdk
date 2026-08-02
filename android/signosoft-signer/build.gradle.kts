// Versions match what Flutter 3.44.8 generates, so this module compiles the
// same way whether Gradle reaches it from the standalone build next door, from
// a Flutter app through the plugin, or from a native Android host.
buildscript {
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.3.20")
    }
}

repositories {
    google()
    mavenCentral()
}

plugins {
    id("com.android.library")
}

group = "com.signosoft.signer"
version = "0.4.0-alpha"

android {
    namespace = "com.signosoft.signer"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }

    testOptions {
        unitTests {
            all {
                it.useJUnitPlatform()
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // ActivityResultContract, OnBackPressedDispatcher, and the launchers the
    // WebView needs for the file chooser and runtime permissions.
    implementation("androidx.activity:activity:1.11.0")
    // Window insets: from Android 15 the ceremony draws under the system bars
    // unless it says otherwise.
    implementation("androidx.core:core:1.17.0")

    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.junit.jupiter:junit-jupiter:5.14.4")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher:1.14.4")
    // org.json is a stub that throws in unit tests; the real implementation on
    // the test classpath shadows it.
    testImplementation("org.json:json:20260719")
}
