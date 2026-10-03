# Cygnus Live v4

This release focuses on command completeness and low-latency voice interaction.

- Mixed multi-motor requests use a dedicated `set_motor_batch` tool and verify every requested motor before Cygnus replies.
- Native Flutter `speech_to_text` is now the primary voice recognizer for immediate partial transcripts and lower turn latency.
- Live mode shows the transcript while the user is still speaking.
- The existing local TTS + barge-in monitor remains, so speaking while Cygnus is talking can interrupt the reply and return to listening.
- AI answers render progressively in the chat instead of appearing as a single full block.
- Leaf-result context, scheduling, MQTT ACK verification, Plant Health, foreground status and Firebase session history are retained.

The Cloudflare worker must be redeployed because `set_motor_batch` was added to the gateway tool allow-list.
