> Latest update: see [VOICE-LIVE-SETUP.md](VOICE-LIVE-SETUP.md) for version 1.5.2+9 Live audio, reviewed dictation and fixed App Check tokens.

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

## 2. Local chat history

Cygnus conversations are saved only on this phone using SharedPreferences.
Anonymous sign-in and Firebase RTDB chat-history rules are no longer required.
The legacy rules snippet is not used by this version. Existing cloud records are
not migrated or deleted. Farm telemetry and schedule services keep their existing
configuration. The AI request itself still sends the relevant conversation and
tool results to Firebase AI Logic for generation.

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

## Free-tier and voice behavior

The Gemini Developer API offers a quota-limited free tier for eligible models on
Firebase Spark projects without a linked billing account. A linked billing account
uses paid-tier pricing; code alone cannot guarantee a free project. No billing
setting is changed by this source update. See the current official pages:

- https://firebase.google.com/docs/ai-logic/pricing
- https://firebase.google.com/docs/ai-logic/quotas
- https://ai.google.dev/gemini-api/docs/pricing

Voice uses the phone speech recognizer, then text AI, then phone TTS. It is not a
Gemini Live audio session. Select Tamil for Tamil speech. Android can end listening
after silence; voice mode retries a silent turn twice, then pauses with guidance.
Recognition errors and AI failures pause the loop instead of repeatedly calling
the API. See https://pub.dev/packages/speech_to_text .

