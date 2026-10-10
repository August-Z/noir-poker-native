// The domain layer is a standalone build so it can be tested on any JVM
// without the Android SDK. The app consumes it as an included build.
pluginManagement { repositories { mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositories { mavenCentral() } }
rootProject.name = "core"
