allprojects {
    repositories {
        google()
        mavenCentral()
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
    // Force all plugin subprojects to use SDK 35 since platform 34 download fails
    project.plugins.withId("com.android.library") {
        val android = project.extensions.getByName("android") as com.android.build.gradle.LibraryExtension
        android.compileSdk = 35
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
