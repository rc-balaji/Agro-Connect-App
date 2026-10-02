# AGRO CONNECT — Mobile Plan integration

## Architecture

- Manual Motor 1/2/3: Flutter -> MQTT -> ESP32 (unchanged)
- Plan Motor 1/2/3: Flutter -> Next.js API -> Firebase -> server scheduler -> Next.js motor executor -> MQTT -> ESP32
- Soil automation relay D25 remains local to ESP32 and is not touched by Plan.

## API used by Flutter

- `GET /api/schedules`
- `POST /api/schedules`
- `PATCH /api/schedules/:id`
- `DELETE /api/schedules/:id`
- `GET /api/scheduler/status`

Default base URL: `https://acro-connect.vercel.app`

No Cloudflare secret is shipped in the mobile app.

## Plan UX

1. Open **Plan**.
2. Tap **+ New**.
3. Choose Motor 1, 2 or 3 first.
4. Pick date and exact time (HH:MM plus seconds field).
5. Set duration in seconds or use presets.
6. Choose Once, Daily, or Selected days.
7. Optionally add an end date for recurring plans.
8. Choose Enable or Disable using radio-style controls.
9. Save.

The monthly calendar shows dots on dates where the selected motor has a plan. Tap a date to inspect that day's plans.
