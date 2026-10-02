# AGRO CONNECT background live status

## User flow

Settings -> Background live status -> ON.

When enabled, the Android foreground service keeps its own MQTT connection to the AGRO-001 topics. It continues receiving telemetry while the Flutter UI is backgrounded or removed from recents. The persistent notification can show only the fields selected by the user:

- device online/offline
- temperature
- humidity
- soil moisture
- water level
- Motor 1/2/3 states

Plan activity alerts are separate dismissible notifications. They are emitted when the background MQTT service sees a fresh schedule-originated desired command. The permanent live-status notification is removed only when Background live status is turned OFF in Settings.

## Runtime design

- foreground service type: `specialUse`
- MQTT is event-driven; the 15-second foreground callback is only a reconnect/staleness watchdog
- foreground notification updates are throttled to at most once every 1.5 seconds
- foreground MQTT client ID is unique and does not replace the ESP32 or normal Flutter client
- wake lock and Wi-Fi lock are enabled while the user explicitly enables background monitoring
- service is configured to survive task removal, app updates, reboots and system restarts where Android permits it
- schedule alerts ignore retained schedule commands older than 120 seconds to avoid stale alerts after reconnect

## Android note

Android 14+ can allow a user to swipe some ongoing notifications while the device is unlocked. The service remains active; AGRO CONNECT reposts the live-status notification when the foreground-service notification-dismissed callback is delivered. The user can always stop it from Settings. OEM battery-management policies can still affect long-running background processes on some devices.

The `specialUse` foreground-service type requires a clear use-case declaration for Google Play review. The manifest includes the subtype explanation for continuous user-enabled smart-farm monitoring.
