val localProperties = java.util.Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use(localProperties::load)
}

val androidSdkRoot = localProperties.getProperty("sdk.dir")
val installedNdkVersions =
    androidSdkRoot
        ?.let { rootProject.file("$it/ndk") }
        ?.listFiles()
        ?.filter { rootProject.file("${it.path}/source.properties").isFile }
        ?.map { it.name }
        ?.sorted()
        ?.joinToString(",")

allprojects {
    repositories {
        google()
        mavenCentral()
    }

    if (!androidSdkRoot.isNullOrBlank()) {
        extensions.extraProperties.set("flutter.androidSdkRoot", androidSdkRoot)
    }
    if (!installedNdkVersions.isNullOrBlank()) {
        extensions.extraProperties.set(
            "flutter.installedNdkVersions",
            installedNdkVersions,
        )
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
