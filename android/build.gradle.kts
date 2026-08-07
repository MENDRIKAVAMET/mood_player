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
}

// Workaround for old plugins (e.g. isar_flutter_libs 3.1.0+1) that don't
// declare an Android Gradle Plugin `namespace` in their build.gradle,
// which newer AGP versions require. This patches the namespace after the
// plugin's own build script has been evaluated, before AGP validates it.
// Uses reflection so this file doesn't need a compile-time dependency on
// AGP's DSL classes.
subprojects {
    if (project.name == "app") return@subprojects
    afterEvaluate {
        if (!plugins.hasPlugin("com.android.library")) return@afterEvaluate
        val android = extensions.findByName("android") ?: return@afterEvaluate
        val getNamespace = android.javaClass.getMethod("getNamespace")
        val currentNamespace = try {
            getNamespace.invoke(android) as String?
        } catch (e: Exception) {
            null
        }
        if (currentNamespace.isNullOrEmpty()) {
            val generatedNamespace = "com.generated.${project.name.replace("-", "_").replace(".", "_")}"
            logger.lifecycle("Patching missing Android namespace for '${project.name}' -> $generatedNamespace")
            val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
            setNamespace.invoke(android, generatedNamespace)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
