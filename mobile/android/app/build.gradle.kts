plugins {
    id("com.android.application")
}

android {
    namespace = "com.keyi.xinxian.guitar"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.keyi.xinxian.guitar"
        minSdk = 26
        targetSdk = 35
        versionCode = 3
        versionName = "0.3.0"
        resValue("string", "app_name", "弦心")

        testInstrumentationRunner = "android.test.InstrumentationTestRunner"
    }

    buildTypes {
        create("jdy23") {
            initWith(getByName("debug"))
            applicationIdSuffix = ".jdy23"
            versionNameSuffix = "-jdy23"
            resValue("string", "app_name", "弦心")
            matchingFallbacks += listOf("debug")
        }
        create("scanCheck") {
            initWith(getByName("debug"))
            applicationIdSuffix = ".scancheck"
            versionNameSuffix = "-scancheck"
            resValue("string", "app_name", "弦心吉他·扫描诊断")
            matchingFallbacks += listOf("debug")
        }
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("test").java.setSrcDirs(listOf("../../../verification/mobile/android/app/src/test/java"))
        getByName("androidTest").java.setSrcDirs(listOf("../../../verification/mobile/android/app/src/androidTest/java"))
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
