# Cygnus Live v3

- Live Interaction starts a fresh Cygnus chat and preserves the transcript in that session.
- Listening can be finished or cancelled. The entire Live screen can always be closed with End / X.
- Spoken replies can be interrupted; Cygnus stops speaking and starts listening to the user.
- Normal mic input acts like dictation by default; audio reply is opt-in outside Live Interaction.
- Voice reply language follows the script of the actual reply (Tamil, Hindi, Malayalam, Kannada, or Indian English).
- Cloudflare transcription now defaults to Groq `whisper-large-v3` for maximum multilingual accuracy, with Tanglish/farm vocabulary hints.
- Cygnus is strictly scoped to AGRO CONNECT/farming workflows; unrelated programming/general-chat requests are redirected.
- Local leaf diagnosis is retained as structured chat context. Prevention/treatment/symptom follow-ups use the same scanned leaf result rather than generic advice.
