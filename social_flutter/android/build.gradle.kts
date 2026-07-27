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
// Third-party plugins (e.g. tflite_flutter) leave Java at 11 while letting Kotlin
// default to the build JDK (20). Kotlin 2.x turns that JVM-target split into a hard
// error, so pin both to 17 for every module to keep the targets consistent. Java must
// be set on the android { compileOptions } extension — that's what AGP's consistency
// check reads, not the raw JavaCompile task properties. This block MUST come before
// the evaluationDependsOn(":app") block below: registering afterEvaluate here (before
// any subproject is evaluated) lets it run ahead of AGP's own finalizing afterEvaluate.
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.apply {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
