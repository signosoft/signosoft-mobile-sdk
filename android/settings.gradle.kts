// Standalone build for the Swift core's Android counterpart: `./gradlew test`
// and CI run against this.
//
// A native Android host does NOT use this file. It points its own
// settings.gradle at `signosoft-signer/` and inherits its own AGP and Kotlin
// versions — see docs/INTEGRATION.md.
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

// Versions match what Flutter 3.44.8 generates for an app, so a Flutter host
// and this build agree.
plugins {
    id("com.android.library") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

rootProject.name = "SignosoftSigner"

include(":signosoft-signer")
