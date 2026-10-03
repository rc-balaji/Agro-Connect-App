# Cygnus fixes — 1.5.1+8

## Findings on the connected phone

On 3 October 2026 (IST), AGRO CONNECT 1.5.0+7 was tested over ADB.

1. The installed test APK already used the App Check debug provider. Before
   registration, logs reported failed debug-token exchange and
   `[firebase_app_check/unknown] Too many attempts`.
2. After the user registered the token and the app was reopened, `Hi` returned
   a real AI greeting. This verifies basic AI generation on the installed APK.
3. `Current temperature enna?` reached a second, independent failure:
   `Role 'function' is not supported`. The tool-result turn used the SDK's legacy
   `function` role. This source update sends function responses in a `user` turn
   while retaining their names, results and call IDs.

Firebase Console settings were not changed by the assistant. The private device
debug token is intentionally not included in this archive.

## Source changes

- Keep the existing Actions APK flag `AGRO_APP_CHECK_DEBUG=true`. The production
  AAB omits this flag and uses Play Integrity. Profile builds also default to
  Play Integrity. Log the selected provider; provider activation alone is not
  described as successful verification.
- Correct the tool-response role and classify App Check, throttling, API,
  permission, model, quota, network and timeout failures separately.
- Bound AI requests, discard failed chat state and avoid automatic action retries.
  Empty AI responses are no longer presented as successful completion.
- Replace broad motor keyword matching with an anchored, strict immediate-command
  parser. Clear commands stay local and fast; questions, negations, schedules and
  compound commands go through AI. Only an acknowledgement matching the sent
  command ID can confirm success.
- Save chat history on the phone only, with serialized writes and no cloud wait.
- Handle speech status, final results, errors and cancellation explicitly. Retry
  silent voice turns at most twice; never execute partial speech. Show listening,
  thinking, speaking and recoverable-error states. Voice replies follow spoken
  requests; typed replies stay immediately readable without waiting for TTS.
- Use a total 45-second AI deadline across the tool loop, not 45 seconds per call.
- Improve the narrow-screen header and keep a typed draft editable while waiting.
- Treat missing telemetry as unavailable; identify offline/stale readings rather
  than presenting default values as current data.

## Build and retest

Push the contents of this project folder, including `.github`, to the existing
repository. The included Actions workflow analyzes/tests the app, builds
`agro-connect-test-apk` with Debug App Check, and builds the production AAB with
Play Integrity. This archive is source code, not a rebuilt APK.

After installing the new test artifact:

1. Open the app. If app data was reset or a different phone is used, obtain its
   current debug token and register that token for the Android Firebase app.
2. Start a new Cygnus chat and send `Hi`.
3. Send `Current temperature enna?`. Compare the reading with the app's telemetry
   and connection status. An offline/stale reading must not be called current.
4. Test other tools only when their actual effects are intended.

For bounded logs:

```powershell
./tool/check_cygnus.ps1
```

For live diagnostics (Ctrl+C to stop):

```powershell
./tool/check_cygnus.ps1 -Watch
```

To display the private registration token locally, explicitly add
`-ShowDebugToken`. The SDK may print it under an obfuscated Android tag; filtering
only on `AppCheck` can miss the token-exchange warning. Do not share token logs.

The production bundle must be tested through its intended Play Integrity setup;
success of this private debug APK does not validate production attestation.

## Validation on the updated source

- Flutter 3.41.6 / Dart 3.11.4: static analysis reports no issues.
- Complete test suite: 24 tests passed, including tool-response serialization,
  local-only persistence, concurrent message writes, voice restart/cancellation,
  strict command parsing, matching device acknowledgements, and 320/390-wide UI.
- Connected phone tests were performed on the existing 1.5.0+7 APK: basic AI reply
  succeeded after token registration; tool-role and voice problems were reproduced.
- Updated source is 1.5.1+8. A new Android APK was not built or installed because
  the local Android SDK is absent. Physical microphone/TTS behavior and actual
  device control must be rechecked on the GitHub Actions APK after installation.
- Firebase Console, billing, quotas and existing cloud chat records were unchanged.
