pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositories { google(); mavenCentral() } }
rootProject.name = "NoirPokerNative"
// Pure Kotlin domain layer, testable without the Android SDK: ./gradlew -p android/core test
includeBuild("android/core")
include(":android:app")
