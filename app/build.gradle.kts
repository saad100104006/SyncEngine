plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.ksp)
  //  id("kotlin-kapt")
}


android {
    namespace = "com.android.surveysyncengine"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.android.surveysyncengine"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = "11"
    }
}

dependencies {

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.core.ktx)
    implementation(libs.androidx.glance)
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)

    // -----------------------------------------------------------------------
    // Kotlin
    // -----------------------------------------------------------------------
    implementation(libs.kotlin.stdlib)

    // -----------------------------------------------------------------------
    // Coroutines
    // -----------------------------------------------------------------------
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.coroutines.core)
    testImplementation(libs.kotlinx.coroutines.test.v173)

    // -----------------------------------------------------------------------
    // Room
    // -----------------------------------------------------------------------
    val roomVersion = "2.6.1"
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)           // coroutine extensions
    ksp(libs.androidx.room.compiler)
    testImplementation(libs.androidx.room.testing)   // in-memory Room for integration tests

    // -----------------------------------------------------------------------
    // WorkManager
    // -----------------------------------------------------------------------
    val workVersion = "2.9.0"
    implementation(libs.androidx.work.runtime.ktx)
    testImplementation(libs.androidx.work.testing)

  /*  // -----------------------------------------------------------------------
    // Testing — unit
    // -----------------------------------------------------------------------
    testImplementation(libs.junit)
    testImplementation(libs.mockk)

    // Turbine — Flow testing (progress stream assertions)
    testImplementation(libs.turbine)

    // Robolectric — needed only if tests use Android Context; Room can use in-memory
    testImplementation(libs.robolectric)

    // -----------------------------------------------------------------------
    // Testing — Android instrumentation (optional, Room integration tests)
    // -----------------------------------------------------------------------
    androidTestImplementation(libs.androidx.junit.v115)
    androidTestImplementation(libs.androidx.runner)
    androidTestImplementation(libs.core.ktx)
    androidTestImplementation(libs.androidx.room.testing)
    androidTestImplementation(libs.jetbrains.kotlinx.coroutines.test)*/


    testImplementation(libs.junit)
    testImplementation(libs.mockk.v1139)

// Turbine — Flow testing (progress stream assertions)
    testImplementation(libs.turbine.v110)

// Robolectric — needed only if tests use Android Context; Room can use in-memory
    testImplementation(libs.robolectric.v4111)

// -----------------------------------------------------------------------
// Testing — Android instrumentation (optional, Room integration tests)
// -----------------------------------------------------------------------
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation(libs.androidx.runner.v152)
    androidTestImplementation(libs.androidx.core.ktx.v150)
    androidTestImplementation(libs.androidx.room.testing)
    androidTestImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.7.3")
    testImplementation(kotlin("test"))
}
