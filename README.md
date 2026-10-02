# AGRO CONNECT Flutter Mobile App

Production-style Flutter client for the AGRO CONNECT ESP32 smart-farming prototype.

## MQTT contract

- Broker: `broker.emqx.io`
- Port: `1883`
- Device: `AGRO-001`
- Telemetry: `agroconnect/AGRO-001/telemetry`
- Desired outputs: `agroconnect/AGRO-001/desired`
- Hardware state / command ACK: `agroconnect/AGRO-001/state`
- Device status: `agroconnect/AGRO-001/status`

The ESP32 keeps its own client ID (`AGRO_CONNECT`). The mobile app always generates a unique MQTT client ID to avoid kicking the ESP32 off the broker.

## App sections

1. **Live** — realtime temperature, humidity, soil, water level, ESP32 status, internet status, MQTT status, last command round-trip.
2. **Control** — automatic soil output status + Motor 1/2/3 remote controls with hardware ACK.
3. **Plan** — Firebase-backed server schedules for Motor 1/2/3 with monthly calendar, exact seconds, Once/Daily/Selected-days recurrence, Enable/Disable, edit, duplicate and delete.
4. **Monitor** — sensor bars, ADC/distance diagnostics, uptime and broker ping.
5. **History** — locally persisted telemetry chart and recent readings.
6. **System** — network probe, MQTT reconnect, broker/topic details and local-history controls.

## Network behavior

`connectivity_plus` identifies the active transport. The app also performs a real TCP reachability probe to `broker.emqx.io:1883`, because having Wi-Fi/mobile connectivity alone does not guarantee Internet reachability.

## Run locally

Install Flutter stable, then from the project root:

```bash
flutter create --platforms=android --org com.agroconnect --project-name agro_connect .
cp tool/android/AndroidManifest.xml android/app/src/main/AndroidManifest.xml
flutter pub get
flutter run
```

If `flutter create` overwrites any custom Dart files in your environment, restore the repository files with Git before running `flutter pub get`.

## GitHub APK/AAB artifact build

Push this repository to GitHub. The included workflow:

`.github/workflows/android-build.yml`

will:

- install Flutter stable
- generate the Android platform scaffold
- apply Internet/network permissions
- run `flutter pub get`
- run `flutter analyze`
- run tests
- build release APK
- build release AAB
- upload both as GitHub Actions artifacts

After a push to `main`/`master`:

**GitHub → Actions → Build Android Artifacts → latest run → Artifacts**

Download:

- `agro-connect-apk`
- `agro-connect-aab`

## ESP32 payload expected by the app

Telemetry example:

```json
{
  "deviceId": "AGRO-001",
  "seq": 42,
  "uptimeMs": 120000,
  "temperature": 28.5,
  "humidity": 65,
  "soil": 42,
  "soilRaw": 27500,
  "waterLevel": 78,
  "waterDistance": 22.1,
  "led1": false,
  "led2": true,
  "led3": false,
  "led4": false
}
```

Mobile command example:

```json
{
  "commandId": "1790193295786_1_123456",
  "led2": true,
  "led3": false,
  "led4": false,
  "sentAt": 1790193295786,
  "source": "flutter-mobile"
}
```

ESP32 ACK on `/state`:

```json
{
  "deviceId": "AGRO-001",
  "led1": false,
  "led2": true,
  "led3": false,
  "led4": false,
  "ackCommandId": "1790193295786_1_123456"
}
```

The app measures the command round trip from publish until that ACK arrives.

## Performance choices

- MQTT TCP directly from Android — no polling/webhook hop for controls.
- MQTT client auto-reconnect + subscription restore.
- Side-menu navigation preserves pages with `IndexedStack`.
- Telemetry history is capped at 300 points.
- History persistence is debounced to avoid disk writes on every MQTT packet.
- History chart renders only the latest 80 cached points.
- Commands wait for real ESP32 ACK instead of showing a fake successful state.
- Network reachability probes are periodic rather than continuous.

## Prototype broker note

`broker.emqx.io` is a public broker and the current topic names are open. This is suitable for the present prototype/demo. Before deploying this as a real farm product, move to a private authenticated MQTT broker and device-specific credentials/topics.

## Branding update

- App icon updated with the selected minimal AGRO CONNECT icon.
- Animated in-app splash screen added with icon-centric motion graphics, glow rings, IoT chips, and a branded loading transition.
- GitHub workflow now generates Android launcher icons automatically before analyze/build.

## Plan tab — server schedules

This build adds a sixth **Plan** tab backed by the existing Next.js/Vercel API and Firebase schedule store.

Default API base URL:

```text
https://acro-connect.vercel.app
```

Override it at build time if needed:

```bash
flutter build apk --release --dart-define=AGRO_API_BASE_URL=https://your-domain.vercel.app
```

Plan features:

- Motor 1 / Motor 2 / Motor 3 independent calendar views.
- Google Calendar-style monthly view with plan dots.
- Create flow starts with motor selection.
- Exact `HH:MM:SS` start time in Asia/Kolkata (IST).
- Duration stored in seconds with quick presets.
- Repeat modes: Once, Daily, Selected days.
- Optional repeat end date.
- Enable / Disable radio-style state control.
- Edit, duplicate, delete and refresh.
- Server overlap validation errors are surfaced directly in the app.
- Scheduler health badge displays whether the server scheduler is configured and reachable.

The Flutter app never stores the Cloudflare scheduler secret. Schedule CRUD goes to the Next.js API; the Next.js server owns Firebase + scheduler integration. Manual motor control continues to use direct MQTT independently.


## Leaf AI — offline disease screening

The side drawer now contains **Leaf AI**. It supports:

- Live camera scanning with repeated on-device inference.
- Camera capture and gallery-photo analysis.
- 38 PlantVillage classes across 14 crops.
- TensorFlow Lite / LiteRT inference with no cloud inference call.
- English, Tamil, Hindi, Malayalam and Kannada guidance.
- Confidence-aware results, top alternatives, treatment and prevention guidance.

### Model setup

The source ZIP contains a tiny placeholder at the model asset path so the repository structure is complete. GitHub Actions automatically runs:

```bash
bash tool/fetch_ai_model.sh
```

before analyze/test/build, replacing the placeholder with the actual ~3 MB quantized MobileNetV3 TFLite model. For a local build, run the same command once before `flutter run`. After installation the model is inside the app and Leaf AI works offline.

### Android

Camera permission is already included. The workflow forces Android minSdk 24 for the current camera/image-picker plugin line.


## Android JVM compatibility fix

The Android build pipeline now runs `python3 tool/patch_android_jvm.py` after generating the Flutter Android scaffold. It aligns Java and Kotlin plugin bytecode targets to JVM 17, including `tflite_flutter`, preventing the Gradle error where Java compiled at 11 while Kotlin compiled at 17.

For a local fresh Android scaffold, run:

```bash
flutter create --platforms=android --org com.agroconnect --project-name agro_connect .
python3 tool/patch_android_jvm.py
flutter pub get
flutter build apk --release
```


## Customer UI refresh

- Bottom navigation removed; all sections now live in the side menu.
- End-user screens use customer-facing labels and hide transport/model implementation details.
- Settings retains technical diagnostics for setup and support.
- Plant Health keeps the five-language experience while removing model/offline jargon from the customer flow.

## Background live status (Android)

Settings now includes an opt-in **Background live status** control. When enabled, AGRO CONNECT runs a dedicated foreground MQTT monitor with a persistent farm-status notification. The user can independently choose device status, temperature, humidity, soil moisture, water level and motor status. Plan activity alerts are separate dismissible notifications.

The service uses Android `specialUse`, keeps CPU/Wi-Fi locks only while the user has explicitly enabled it, and is configured with task-removal/restart/boot recovery. See `BACKGROUND-MONITOR-NOTES.md` for the runtime design and Android platform caveats.

## Cygnus — in-app farm agent

Cygnus is integrated as a first-class side-menu experience instead of a separate
chatbot demo. It uses Firebase AI Logic function calling to invoke the same
controllers used by the manual UI, so AI and manual controls share one source of
truth.

Key behavior:

- natural multilingual chat (English, Tamil/Tanglish, Hindi, Malayalam, Kannada)
- current telemetry and truly live chat cards backed by the existing MQTT stream
- recent metric trend charts in the conversation
- Motor 1/2/3 immediate commands with the existing hardware ACK path
- conversational schedule create/update/delete/enable/disable through the
  existing Next.js scheduling APIs; create/update/delete use final confirmation
- Plant Health photo capture/gallery runs the bundled TFLite model on-device,
  then places diagnosis and treatment guidance in the same chat
- Firebase RTDB chat sessions with local-history fallback
- push-to-talk and continuous turn-by-turn voice conversation using the phone's
  speech recognizer and TTS
- Cygnus failure never disables Home, Motors, Plans, Plant Health, or monitoring

See `FIREBASE-CYGNUS-SETUP.md` before the first Cygnus test.
