# Cygnus Groq Gateway (Cloudflare Worker)

This Worker keeps `GROQ_API_KEY` outside the Flutter APK and forwards only the local AGRO CONNECT tool schemas that Cygnus is allowed to request.

## Deploy

```bash
cd cloudflare-cygnus
npm install
npx wrangler login
npx wrangler secret put GROQ_API_KEY
npx wrangler secret put FIREBASE_API_KEY
npm run deploy
```

The default Worker name is `agro-connect-cygnus`, so on the existing account it should deploy to:

`https://agro-connect-cygnus.rcbalaji2003.workers.dev`

The Flutter app uses that URL by default. To override it at build time:

```bash
flutter build apk --release \
  --dart-define=CYGNUS_GATEWAY_URL=https://YOUR-WORKER.workers.dev
```

## Firebase authentication

The Worker defaults to `REQUIRE_FIREBASE_AUTH = "true"`. Enable **Anonymous** sign-in in Firebase Authentication. The Flutter app obtains a short-lived Firebase ID token and sends it to the Worker; the Worker verifies the token before spending Groq quota.

For a short local-only gateway test you may temporarily set `REQUIRE_FIREBASE_AUTH = "false"`, deploy, test, and turn it back on before sharing the app.

## Health check

Open:

`https://YOUR-WORKER.workers.dev/health`

A healthy deployment returns JSON with `ok: true`.
