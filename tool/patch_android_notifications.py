#!/usr/bin/env python3
from pathlib import Path

kts = Path('android/app/build.gradle.kts')
groovy = Path('android/app/build.gradle')

if kts.exists():
    text = kts.read_text()
    if 'isCoreLibraryDesugaringEnabled = true' not in text:
        text = text.replace(
            'compileOptions {',
            'compileOptions {\n        isCoreLibraryDesugaringEnabled = true',
            1,
        )
    if 'multiDexEnabled = true' not in text and 'defaultConfig {' in text:
        text = text.replace('defaultConfig {', 'defaultConfig {\n        multiDexEnabled = true', 1)
    dep = 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")'
    if dep not in text:
        if 'dependencies {' in text:
            text = text.replace('dependencies {', f'dependencies {{\n    {dep}', 1)
        else:
            text += f'\n\ndependencies {{\n    {dep}\n}}\n'
    kts.write_text(text)
    print('Patched notification desugaring:', kts)
elif groovy.exists():
    text = groovy.read_text()
    if 'coreLibraryDesugaringEnabled true' not in text:
        text = text.replace('compileOptions {', 'compileOptions {\n        coreLibraryDesugaringEnabled true', 1)
    if 'multiDexEnabled true' not in text and 'defaultConfig {' in text:
        text = text.replace('defaultConfig {', 'defaultConfig {\n        multiDexEnabled true', 1)
    dep = "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'"
    if dep not in text:
        if 'dependencies {' in text:
            text = text.replace('dependencies {', f'dependencies {{\n    {dep}', 1)
        else:
            text += f'\n\ndependencies {{\n    {dep}\n}}\n'
    groovy.write_text(text)
    print('Patched notification desugaring:', groovy)
else:
    raise SystemExit('Android app Gradle file not found. Run flutter create first.')
