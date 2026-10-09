// AGP is only put on the classpath when the Android app is part of the build,
// so `MYBIB_CORE_ONLY=1 ./gradlew :core:test` works without Google's Maven repository.
buildscript {
    if (System.getenv("MYBIB_CORE_ONLY") != "1") {
        dependencies { classpath(libs.android.gradle) }
    }
}

plugins {
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.compose) apply false
}
