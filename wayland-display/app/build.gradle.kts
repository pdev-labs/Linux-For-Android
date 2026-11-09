plugins {
    id("com.android.application")
}

android {
    namespace = "io.github.pdevlabs.lfadisplay"
    compileSdk = 35

    defaultConfig {
        applicationId = "io.github.pdevlabs.lfadisplay"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"

        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    buildFeatures {
        buildConfig = true
        aidl = true
    }

    signingConfigs {
        // Public AOSP test key. Required by the shared-UID (standard) build so
        // it can run as com.termux; also used to sign the regular build.
        create("testkey") {
            storeFile = file("testkey_untrusted.jks")
            storePassword = "xrj45yWGLbsO7W0v"
            keyAlias = "alias"
            keyPassword = "xrj45yWGLbsO7W0v"
        }
    }

    flavorDimensions += "transport"
    productFlavors {
        create("standard") {
            dimension = "transport"
            buildConfigField("boolean", "DIRECT_SOCKET", "true")
            versionNameSuffix = "-standard"
        }
        create("compatible") {
            dimension = "transport"
            buildConfigField("boolean", "DIRECT_SOCKET", "false")
            versionNameSuffix = "-compatible"
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("testkey")
        }
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("testkey")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
