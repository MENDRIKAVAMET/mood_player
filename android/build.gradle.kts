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

// Force every subproject (plugins like isar_flutter_libs that hardcode an
// old compileSdkVersion in their own build.gradle) to compile against SDK
// 36. Old plugins set compileSdkVersion too low, which makes AAPT fail to
// resolve resources introduced in newer platforms (e.g. android:attr/lStar,
// added in API 31) that get pulled in transitively via AndroidX. Forcing a
// high compileSdk everywhere is safe since Android SDKs are backward
// compatible.
subprojects {
    if (project.name == "app") return@subprojects
    afterEvaluate {
        val android = extensions.findByName("android") ?: return@afterEvaluate
        try {
            val setCompileSdkVersion = android.javaClass.getMethod("setCompileSdkVersion", Int::class.java)
            setCompileSdkVersion.invoke(android, 36)
        } catch (e: Exception) {
            logger.lifecycle("Could not force compileSdk for '${project.name}': ${e.message}")
        }
    }
}

// Workaround for old plugins (e.g. isar_flutter_libs 3.1.0+1) that don't
// declare an Android Gradle Plugin `namespace` in their build.gradle, but
// instead set it the legacy way via `package="..."` in their
// AndroidManifest.xml. Newer AGP versions (a) require `namespace` to be set
// in build.gradle and (b) reject the `package` attribute outright ("Setting
// the namespace via the package attribute in the source AndroidManifest.xml
// is no longer supported"). So for every such plugin we:
//   1. Read the `package` value out of its AndroidManifest.xml.
//   2. Set that value as the AGP `namespace` (reflection avoids a
//      compile-time dependency on AGP's DSL classes here in the root script).
//   3. Strip the `package` attribute from the manifest file itself so AGP's
//      manifest merger doesn't reject it.
subprojects {
    if (project.name == "app") return@subprojects
    afterEvaluate {
        if (!plugins.hasPlugin("com.android.library")) return@afterEvaluate

        val manifestFile = file("src/main/AndroidManifest.xml")
        var manifestPackage: String? = null
        if (manifestFile.exists()) {
            val original = manifestFile.readText()
            val match = Regex("package\\s*=\\s*\"([^\"]+)\"").find(original)
            manifestPackage = match?.groupValues?.get(1)
            if (match != null) {
                val patched = original.replaceFirst(match.value, "")
                if (patched != original) {
                    logger.lifecycle("Stripping legacy package attribute from AndroidManifest.xml for '${project.name}'")
                    manifestFile.writeText(patched)
                }
            }
        }

        val android = extensions.findByName("android") ?: return@afterEvaluate
        val getNamespace = android.javaClass.getMethod("getNamespace")
        val currentNamespace = try {
            getNamespace.invoke(android) as String?
        } catch (e: Exception) {
            null
        }
        if (currentNamespace.isNullOrEmpty()) {
            val generatedNamespace = manifestPackage
                ?: "com.generated.${project.name.replace("-", "_").replace(".", "_")}"
            logger.lifecycle("Patching missing Android namespace for '${project.name}' -> $generatedNamespace")
            val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
            setNamespace.invoke(android, generatedNamespace)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
