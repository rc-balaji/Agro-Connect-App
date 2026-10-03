# Cygnus Groq setup

Cygnus now uses Groq through a Cloudflare Worker. The Groq API key is **never embedded in the Flutter APK** and is **never committed to GitHub**.

## 1. Rotate the exposed Groq key

If a Groq key has ever been pasted into chat, a screenshot, a public issue, or a public repository, revoke it and create a new one before deployment.

## 2. Deploy the Worker

```bash
cd cloudflare-cygnus
npm install
npx wrangler login
npx wrangler secret put GROQ_API_KEY
npx wrangler secret put FIREBASE_API_KEY
npm run deploy
```

Expected URL on the current account:

`https://agro-connect-cygnus.rcbalaji2003.workers.dev`

Verify:

`https://agro-connect-cygnus.rcbalaji2003.workers.dev/health`

## 3. Enable Firebase Anonymous Authentication

Firebase Console → Authentication → Sign-in method → Anonymous → Enable.

The Flutter app uses an anonymous Firebase ID token to authenticate with the Worker. This protects the Groq quota from random unauthenticated requests.

## 4. GitHub Actions Firebase config

Do not commit `google-services.json`.

Create this repository secret:

`GOOGLE_SERVICES_JSON`

Paste the complete contents of the Android `google-services.json` into that secret. The workflow recreates `android/app/google-services.json` during CI.

## 5. Model routing

- Fast/simple requests: `openai/gpt-oss-20b` with low reasoning.
- Complex plan/trend/edit requests: `openai/gpt-oss-120b` with medium reasoning.
- Explicit immediate motor commands such as “Motor 2 start pannuda” bypass the LLM completely and use the existing ACK-verified MQTT controller for minimum latency and zero AI tokens.

## 6. Override gateway URL if needed

```bash
flutter build apk --release \
  --dart-define=CYGNUS_GATEWAY_URL=https://YOUR-WORKER.workers.dev
```

The app defaults to `https://agro-connect-cygnus.rcbalaji2003.workers.dev`.
