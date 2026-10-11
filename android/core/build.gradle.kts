import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.kotlin.jvm)
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
}

dependencies {
    api(libs.coroutines.core)
    api(libs.serialization.json)
    testImplementation(libs.junit)
    testImplementation(libs.kotlin.test.junit)
}

tasks.test {
    // the texts and the app sources (for the "every key used exists" check)
    systemProperty("mybib.strings", rootProject.file("../shared/strings.json").absolutePath)
    systemProperty("mybib.sources", rootProject.projectDir.absolutePath)
    inputs.file(rootProject.file("../shared/strings.json"))
    inputs.dir(rootProject.file("app/src/main"))
    testLogging { events("failed"); exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL }
}
