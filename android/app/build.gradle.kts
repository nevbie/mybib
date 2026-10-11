import com.android.build.api.variant.ApplicationAndroidComponentsExtension
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application") // version comes from the root buildscript classpath
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

// versionCode = number of commits (CI passes -PversionCode=$(git rev-list --count HEAD)),
// versionName = android/version.txt + "." + versionCode
val buildNumber = providers.gradleProperty("versionCode").orElse(providers.environmentVariable("BUILD_NUMBER")).orElse("1").get().toInt()
val baseVersion = rootProject.file("version.txt").readText().trim()

// Release key from the environment (same secrets as the Flutter build). Without them the
// release build is signed with the debug key, so CI on pull requests works without secrets.
val keystoreFile: String? = System.getenv("KEYSTORE_FILE")?.takeIf { it.isNotBlank() }
val keystorePassword: String? = System.getenv("KEYSTORE_PASSWORD")?.takeIf { it.isNotBlank() }

android {
    namespace = "app.mybib"
    compileSdk = 36

    defaultConfig {
        // Play Store id of the existing app – must never change
        applicationId = "app.mybib"
        minSdk = 26
        targetSdk = 36
        versionCode = buildNumber
        versionName = "$baseVersion.$buildNumber"
    }

    signingConfigs {
        if (keystoreFile != null && keystorePassword != null) {
            create("release") {
                storeFile = file(keystoreFile)
                storePassword = keystorePassword
                keyAlias = System.getenv("KEYSTORE_ALIAS")?.takeIf { it.isNotBlank() } ?: "androiddebugkey"
                keyPassword = keystorePassword
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    lint {
        abortOnError = false
        checkReleaseBuilds = false
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

kotlin {
    compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
}

/** Copies shared/strings.json (the single source of all texts) into the app's assets. */
abstract class SharedStringsTask : DefaultTask() {
    @get:InputFile
    abstract val source: RegularFileProperty

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @TaskAction
    fun copy() {
        val out = outputDir.get().asFile
        out.deleteRecursively()
        out.mkdirs()
        source.get().asFile.copyTo(out.resolve("strings.json"), overwrite = true)
    }
}

val sharedStrings = tasks.register<SharedStringsTask>("sharedStrings") {
    source.set(rootProject.layout.projectDirectory.file("../shared/strings.json"))
}

extensions.getByType<ApplicationAndroidComponentsExtension>().onVariants { variant ->
    variant.sources.assets?.addGeneratedSourceDirectory(sharedStrings, SharedStringsTask::outputDir)
}

dependencies {
    implementation(project(":core"))
    implementation(libs.coroutines.android)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.extended)
    implementation(libs.camerax.camera2)
    implementation(libs.camerax.lifecycle)
    implementation(libs.camerax.view)
    implementation(libs.mlkit.barcode)
    implementation(libs.coil.compose)
}
