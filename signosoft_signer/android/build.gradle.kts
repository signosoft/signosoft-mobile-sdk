// Versions match what Flutter 3.44.8 generates for a plugin.
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

group = "com.signosoft.signer.flutter"
version = "0.5.0-beta"

// The one copy of the Kotlin core, in the sibling directory a native Android
// host consumes directly. Gradle resolves a source directory outside the
// project root, so unlike iOS this needs no symlink — but it does mean the two
// directories must stay siblings. See docs/INTEGRATION.md.
val core = "../../android/signosoft-signer/src/main"

android {
    namespace = "com.signosoft.signer.flutter"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin", "$core/kotlin")
            // The core declares the signing activity. A source set has one
            // manifest, and the plugin needs nothing of its own in it, so it
            // uses the core's — which is why the activity is named in full there.
            manifest.srcFile("$core/AndroidManifest.xml")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("../../android/signosoft-signer/consumer-rules.pro")
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
    // Compiling the core's sources means carrying the core's dependencies.
    implementation("androidx.activity:activity:1.11.0")
    implementation("androidx.core:core:1.17.0")

    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.junit.jupiter:junit-jupiter:5.14.4")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher:1.14.4")
}
