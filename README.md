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

## App tabs

1. **Live** — realtime temperature, humidity, soil, water level, ESP32 status, internet status, MQTT status, last command round-trip.
2. **Control** — automatic soil output status + Motor 1/2/3 remote controls with hardware ACK.
3. **Monitor** — sensor bars, ADC/distance diagnostics, uptime and broker ping.
4. **History** — locally persisted telemetry chart and recent readings.
5. **System** — network probe, MQTT reconnect, broker/topic details and local-history controls.

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
- Bottom navigation preserves pages with `IndexedStack`.
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
