# Cygnus Firebase setup

The Flutter code is already wired to the Android Firebase app registered as
`com.agroconnect.agro_connect`. The CI workflow regenerates Android files, copies
`google-services.json`, applies the Google Services Gradle plugin, then builds the
app.

## 1. Enable Firebase AI Logic

Firebase Console → **AI Logic** → **Get started** → select **Gemini Developer API**.
Use the registered Android app when the guided setup asks which app is calling the
API.

Cygnus uses the stable `gemini-3.8-flash` model and calls it through the
`firebase_ai` Flutter SDK. No Gemini API key is hard-coded separately in the app.

## 2. Enable anonymous authentication for cloud chat history

Firebase Console → **Authentication** → **Sign-in method** → **Anonymous** → Enable.

If Anonymous Auth is not enabled, Cygnus still works, but its conversation history
falls back to local phone storage instead of syncing to Firebase.

## 3. Merge the Cygnus RTDB rules

Do **not** replace your existing database rules. Merge this node into the existing
root rules so each anonymous/authenticated user can read and write only their own
Cygnus sessions:

```json
"cygnusUsers": {
  "$uid": {
    ".read": "auth != null && auth.uid === $uid",
    ".write": "auth != null && auth.uid === $uid"
  }
}
```

The app stores only chat/session records under `cygnusUsers/{uid}/sessions`. Farm
telemetry, schedules and server data keep using their existing paths and rules.

## 4. App Check

Cygnus initializes Firebase App Check before Firebase AI Logic:

- production AAB → Android **Play Integrity** provider
- debug/development → Firebase **Debug** provider
- GitHub test APK → Firebase **Debug** provider through
  `--dart-define=AGRO_APP_CHECK_DEBUG=true`

### Test APK

Install the `agro-connect-test-apk` artifact, open the app, then inspect Android
logs once. Firebase's debug App Check provider prints a debug secret. Add that
secret in:

Firebase Console → **App Check** → your Android app → **Manage debug tokens**.

Never publish a test APK that uses the debug provider to end users.

### Production AAB

Before Play Store release:

1. Firebase Console → App Check → register the Android app with **Play Integrity**.
2. Add the production signing certificate SHA-256/SHA-1 in Firebase project
   settings as required by the provider.
3. Release the AAB through Google Play and verify valid App Check traffic.
4. Keep App Check enforcement enabled for Firebase AI Logic.

## 5. API-key restrictions

Firebase client API keys identify the Firebase project; they are not an app
password. For a public repository, still apply Google Cloud restrictions to the
Android package/signing certificate and allow only the Firebase APIs the app uses.
Security is enforced by App Check, Firebase Authentication and RTDB rules rather
than by hiding the client config file.

## 6. What Cygnus can do

Cygnus tools are deterministic app functions. The model never gets raw MQTT or
Firebase credentials.

- current telemetry + motor state
- live status card
- recent metric chart
- Motor 1 / 2 / 3 immediate control with hardware confirmation
- list/enable/disable motor plans
- conversational schedule preparation with final confirmation
- schedule deletion with confirmation
- local Plant Health photo analysis and multilingual care guidance
- app navigation
- saved chat sessions
- text, push-to-talk, and turn-by-turn voice conversation

The automatic soil-moisture relay is intentionally **not** exposed as a Cygnus
manual-control tool.
