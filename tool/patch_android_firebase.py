#!/usr/bin/env python3
from pathlib import Path
import json
import os
import re

ROOT = Path('.')
raw = os.environ.get('GOOGLE_SERVICES_JSON', '').strip()
local_source = ROOT / 'tool' / 'firebase' / 'google-services.json'

if raw:
    try:
        config = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f'GOOGLE_SERVICES_JSON is invalid JSON: {exc}')
elif local_source.exists():
    config = json.loads(local_source.read_text())
else:
    raise SystemExit(
        'Missing Firebase Android config. Add GitHub Actions secret '
        'GOOGLE_SERVICES_JSON containing the full google-services.json.'
    )

clients = config.get('client') or []
if not clients:
    raise SystemExit('google-services.json has no client entries')
package_name = clients[0].get('client_info', {}).get('android_client_info', {}).get('package_name')
if package_name != 'com.agroconnect.agro_connect':
    raise SystemExit(f'Unexpected Firebase Android package: {package_name!r}')

app_target = ROOT / 'android' / 'app' / 'google-services.json'
app_target.parent.mkdir(parents=True, exist_ok=True)
app_target.write_text(json.dumps(config, indent=2) + '\n')

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
    if "id 'com.google.gms.google-services'" not in text and "apply plugin: 'com.google.gms.google-services'" not in text:
        match = re.search(r'plugins\s*\{', text)
        if match:
            insert_at = match.end()
            text = text[:insert_at] + "\n    id 'com.google.gms.google-services'" + text[insert_at:]
        else:
            text += "\napply plugin: 'com.google.gms.google-services'\n"
    app_groovy.write_text(text)
else:
    raise SystemExit('Android app Gradle file not found')

print('Firebase Android configuration applied successfully.')
