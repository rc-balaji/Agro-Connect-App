# Cygnus voice update — 1.5.2+9

## Controls

- **Waveform / Start Live audio:** real Gemini bidirectional audio with spoken responses and interruption. Speak Tamil, Tanglish or English naturally. Uses `gemini-3.1-flash-live-preview`, 16 kHz mono PCM input and 24 kHz mono PCM output, independently of Android speech recognition/TTS.
- **Composer microphone:** dictate in the selected language, review/edit, then Send. Partial words are preserved if Android ends before a final result. Dictated replies are spoken when Voice replies is enabled and the selected TTS voice is installed.
- Live answers general questions and reads farm telemetry, trends, schedules and the last leaf result. Motor/schedule changes use reviewed dictation or typed commands; Live cannot execute them.
- Stop, leaving the chat screen, or backgrounding the app closes Live. No automatic reconnect loop. Restart after connection, quota or session-limit errors.
- Transcripts use existing local history. Audio is streamed to Gemini for processing; the app does not save audio files.

## Fixed App Check token

Firebase requires a UUID v4 secret. `9080778096` can be the **display name**, not the secret value.

1. Use the same valid UUID in Firebase Console's Android app debug-token registration and GitHub repository **Settings → Secrets and variables → Actions → New repository secret**.
2. Name the Actions secret `AGRO_APP_CHECK_DEBUG_TOKEN`. Set its value to the UUID without quotes. Reuse the existing phone token; do not regenerate it per build.
3. Run the workflow. Test APKs use that secret via a temporary JSON file. The production AAB omits debug defines and uses Play Integrity.

If the secret is absent, normal per-install generated-token behavior remains. Invalid values fail the build. The workflow never prints the token. Setting the build secret does not register it in Firebase; registration is still required once for the correct Android app.

Local test configuration belongs in ignored `.local/appcheck-debug.json`, with `AGRO_APP_CHECK_DEBUG` set to true and `AGRO_APP_CHECK_DEBUG_TOKEN` set to the registered UUID:

```powershell
flutter build apk --release --dart-define-from-file=.local/appcheck-debug.json
```

## Free tier and validation

Firebase documents this Live model as available on the Gemini Developer API free tier. Usage is limited; this update does not inspect or change account billing. App Check and model/API access must work first. Firebase Console was not modified.

Source verification: analyzer clean; 28 tests pass, including dictation review/partial recovery, Live cancellation and token validation. No Android SDK is installed on this PC, so the new APK has not been built or installed locally. Phone microphone accuracy, speaker routing, interruption and backend access still need verification with the new Actions APK.

After installing `agro-connect-test-apk` version 1.5.2+9:

1. Send `Hi` to verify App Check/backend access.
2. Tap the waveform, allow microphone access, and say “Vanakkam, Tamil-la pesu”. Check sound and transcript.
3. Interrupt while it speaks. Ask “Current temperature enna?” and compare with the app's data status.
4. End Live, select Tamil, dictate a harmless question, correct the text, and Send. Check TTS separately; install the phone's Tamil voice data if unavailable.
5. Stop or background the app; the microphone indicator should disappear. Reopen and start Live again.

References: [Firebase Live API](https://firebase.google.com/docs/ai-logic/live-api), [token format](https://firebase.google.com/docs/reference/appcheck/rest/v1/projects.apps.debugTokens), [pricing](https://firebase.google.com/docs/ai-logic/pricing).
