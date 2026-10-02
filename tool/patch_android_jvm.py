#!/usr/bin/env python3
from pathlib import Path

root = Path('android/build.gradle.kts')
if not root.exists():
    raise SystemExit('android/build.gradle.kts not found. Run flutter create first.')

text = root.read_text()
marker = 'subprojects {\n    project.evaluationDependsOn(":app")\n}'
block = '''// AGRO CONNECT: keep Java/Kotlin bytecode targets aligned across Flutter plugins.
// tflite_flutter compiles Java at JVM 11 while recent Flutter/Kotlin toolchains
// may default Kotlin to JVM 17. AGP rejects that mismatch.
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.apply {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
    }

    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}
'''

if 'AGRO CONNECT: keep Java/Kotlin bytecode targets aligned' not in text:
    if marker in text:
        text = text.replace(marker, block + '\n' + marker)
    else:
        idx = text.find('project.evaluationDependsOn(":app")')
        if idx >= 0:
            sub_idx = text.rfind('subprojects {', 0, idx)
            insert_at = sub_idx if sub_idx >= 0 else 0
            text = text[:insert_at] + block + '\n' + text[insert_at:]
        else:
            text = block + '\n' + text

root.write_text(text)
print('Patched Android JVM targets to Java/Kotlin 17:', root)
