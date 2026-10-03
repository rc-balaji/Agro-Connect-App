# Cygnus migration notes

## What changed

- Firebase AI Logic generation removed from Cygnus.
- Groq GPT-OSS added through a Cloudflare Worker gateway.
- Simple/fast prompts route to GPT-OSS 20B; complex agent requests route to GPT-OSS 120B.
- Existing local Flutter tool execution is preserved: live telemetry, trends, motor control with hardware ACK, plans, navigation and latest Leaf AI result.
- Clear immediate motor commands continue to bypass the LLM for minimum latency and zero AI usage.
- Selected Cygnus cosmic emblem added to the Cygnus header, drawer and global top app bar button.
- `google-services.json` is no longer stored in the repository; GitHub Actions restores it from `GOOGLE_SERVICES_JSON`.
- Existing MQTT, Plan, Leaf AI, background monitoring and Firebase chat-session storage remain intact.

## Required one-time setup

1. Revoke the Groq key that was previously exposed and create a new key.
2. Deploy `cloudflare-cygnus/` and store the new Groq key with `wrangler secret put GROQ_API_KEY`.
3. Store the Firebase Android web API key in the Worker with `wrangler secret put FIREBASE_API_KEY`.
4. Firebase Authentication → enable Anonymous sign-in.
5. GitHub Actions → create repository secret `GOOGLE_SERVICES_JSON` with the complete Android config JSON.
6. Push this project and run the Android workflow.
