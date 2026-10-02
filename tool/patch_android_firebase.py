#!/usr/bin/env python3
from pathlib import Path
import json
import re
import shutil

ROOT = Path('.')
source = ROOT / 'tool' / 'firebase' / 'google-services.json'
if not source.exists():
    raise SystemExit('Missing tool/firebase/google-services.json')

config = json.loads(source.read_text())
clients = config.get('client') or []
if not clients:
    raise SystemExit('google-services.json has no client entries')
package_name = clients[0].get('client_info', {}).get('android_client_info', {}).get('package_name')
if package_name != 'com.agroconnect.agro_connect':
    raise SystemExit(f'Unexpected Firebase Android package: {package_name!r}')

app_target = ROOT / 'android' / 'app' / 'google-services.json'
app_target.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(source, app_target)

# Modern Flutter templates declare plugin versions in settings.gradle.kts.
settings_kts = ROOT / 'android' / 'settings.gradle.kts'
settings_groovy = ROOT / 'android' / 'settings.gradle'

if settings_kts.exists():
    text = settings_kts.read_text()
    plugin_line = '    id("com.google.gms.google-services") version "4.5.0" apply false\n'
    if 'com.google.gms.google-services' not in text:
        match = re.search(r'plugins\s*\{', text)
        if not match:
            raise SystemExit('Unable to find plugins block in settings.gradle.kts')
        insert_at = match.end()
        text = text[:insert_at] + '\n' + plugin_line + text[insert_at:]
    settings_kts.write_text(text)
elif settings_groovy.exists():
    text = settings_groovy.read_text()
    plugin_line = "    id 'com.google.gms.google-services' version '4.5.0' apply false\n"
    if 'com.google.gms.google-services' not in text:
        match = re.search(r'plugins\s*\{', text)
        if not match:
            raise SystemExit('Unable to find plugins block in settings.gradle')
        insert_at = match.end()
        text = text[:insert_at] + '\n' + plugin_line + text[insert_at:]
    settings_groovy.write_text(text)
else:
    # Older Gradle layout fallback.
    root_kts = ROOT / 'android' / 'build.gradle.kts'
    root_groovy = ROOT / 'android' / 'build.gradle'
    if root_kts.exists():
        text = root_kts.read_text()
        block = 'plugins {\n    id("com.google.gms.google-services") version "4.5.0" apply false\n}\n\n'
        if 'com.google.gms.google-services' not in text:
            text = block + text
        root_kts.write_text(text)
    elif root_groovy.exists():
        text = root_groovy.read_text()
        if 'com.google.gms:google-services' not in text:
            text = text.replace(
                'dependencies {',
                "dependencies {\n        classpath 'com.google.gms:google-services:4.5.0'",
                1,
            )
        root_groovy.write_text(text)
    else:
        raise SystemExit('No supported project-level Gradle file found')

app_kts = ROOT / 'android' / 'app' / 'build.gradle.kts'
app_groovy = ROOT / 'android' / 'app' / 'build.gradle'

if app_kts.exists():
    text = app_kts.read_text()
    if 'id("com.google.gms.google-services")' not in text:
        match = re.search(r'plugins\s*\{', text)
        if not match:
            raise SystemExit('Unable to find app plugins block')
        insert_at = match.end()
        text = text[:insert_at] + '\n    id("com.google.gms.google-services")' + text[insert_at:]
    app_kts.write_text(text)
elif app_groovy.exists():
    text = app_groovy.read_text()
    if "id 'com.google.gms.google-services'" not in text and 'apply plugin: \'com.google.gms.google-services\'' not in text:
        match = re.search(r'plugins\s*\{', text)
        if match:
            insert_at = match.end()
            text = text[:insert_at] + "\n    id 'com.google.gms.google-services'" + text[insert_at:]
        else:
            text += "\napply plugin: 'com.google.gms.google-services'\n"
    app_groovy.write_text(text)
else:
    raise SystemExit('Android app Gradle file not found')

# Assert application ID remains aligned with Firebase registration.
combined = ''
for candidate in (app_kts, app_groovy):
    if candidate.exists():
        combined = candidate.read_text()
        break
if 'com.agroconnect.agro_connect' not in combined:
    print('Note: Flutter template may derive applicationId indirectly; Firebase package was verified from config.')

print('Firebase Android configuration applied successfully.')
