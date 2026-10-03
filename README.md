# AGRO CONNECT Mobile — Cygnus Groq Edition

Flutter mobile app for AGRO CONNECT with live MQTT farm monitoring, manual motor controls, Plan scheduling, offline Plant Health AI, foreground monitoring, multilingual voice, and **Cygnus**, the in-app farm agent.

## Cygnus

Cygnus now uses Groq through a small Cloudflare Worker gateway:

```text
Flutter Cygnus
   ↓
Cloudflare Worker
   ↓
Groq GPT-OSS 20B / 120B
   ↓ tool request
Flutter tool router
   ├─ live telemetry
   ├─ MQTT motor control + ACK
   ├─ plans
   ├─ history/trends
   ├─ navigation
   └─ local Plant Health result
```

The Worker keeps the Groq API key out of the APK. The model never receives MQTT credentials or direct database write access.

### Natural commands

- `Motor 2 start pannuda`
- `Current temperature enna?`
- `Temperature live-ah kattu`
- `Motor 3 tomorrow 7 PM-ku 2 minutes podu`
- `Monday Wednesday Friday Motor 1 6:30 PM-ku 30 seconds`
- `Adha disable pannu`
- Upload a leaf photo and continue the diagnosis in the same Cygnus conversation.

### Token/performance optimization

Clear immediate motor commands use the deterministic controller without an LLM request. Short status/navigation requests use GPT-OSS 20B. More complex planning/history/update requests use GPT-OSS 120B. Only the last part of the conversation is sent to the gateway.

## Cygnus branding

The selected Cygnus cosmic emblem is bundled at:

`assets/branding/cygnus_emblem.png`

It appears in the Cygnus header, side menu, and as a persistent compact button in the top app bar on every screen.

## Setup

Read **CYGNUS-GROQ-SETUP.md** first.

For Android CI, add the GitHub Actions secret `GOOGLE_SERVICES_JSON`. The repository intentionally does not store `google-services.json`.

## Existing systems retained

- MQTT realtime device connection
- Motor 1 / 2 / 3 manual control
- Plan calendar and server scheduler
- Firebase-backed/local Cygnus chat history fallback
- Offline PlantVillage TFLite inference
- English, Tamil, Hindi, Malayalam and Kannada Plant Health guidance
- Speech-to-text and text-to-speech voice interaction
- Foreground live status notifications

## CI

GitHub Actions runs package install, launcher icon generation, analyzer, tests, APK and AAB builds. The existing JVM compatibility patch and notification/desugaring setup remain included.

## Cygnus voice v2

Cygnus voice input now records a short high-quality mono clip and sends it through the authenticated Cloudflare gateway to Groq `whisper-large-v3-turbo`. The gateway keeps `GROQ_API_KEY` off-device. Mixed Tamil/English (Tanglish) is auto-detected and vocabulary hints include AGRO CONNECT motor/sensor terminology. The chat shows a live microphone waveform while recording and a separate transcription state.

Redeploy `cloudflare-cygnus` after this update because `/v1/transcribe` is new.
