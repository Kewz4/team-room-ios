# Team Room (iOS)

Native SwiftUI client for the private [Kewz Team Room](../Kewz-Cobblemon-Handoff) bridge — the same local Node.js app the
browser UI talks to. Liquid Glass styling, built with the iOS 26 SDK (runs on iOS 26/27+ devices).

The app is a **thin client**: the Windows PC runs the Team Room server and its Cloudflare tunnel; this app connects over
private HTTPS with a device-link session cookie and shows the real teammate conversations.

## Build (GitHub Actions, no Mac needed)

Every push to `main` (or a manual dispatch) builds an **unsigned** `TeamRoom.ipa` on a GitHub-hosted macOS runner and
uploads it as an artifact:

1. Actions → **Build unsigned IPA** → run (or push).
2. Open the run → **Artifacts** → download `TeamRoom-unsigned-ipa`.
3. Unzip → `TeamRoom-unsigned.ipa`.

The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`); `TeamRoom.xcodeproj` is generated in
CI and is not committed.

### Why unsigned?

This repo does not hold certificates or provisioning profiles. Sign on your device side:

- **Sideloadly / AltStore / ESign / Scarlet** with your certificate: import the `.ipa` and sign normally.
- Free Apple ID signing works too (7-day provisioning, refresh after expiry).
- If you build locally on a Mac later, just open `TeamRoom.xcodeproj` (run `xcodegen generate` first) and sign there.

## Pair the app with the PC

1. On the PC, open Team Room → **Connection settings** → **Another device** → **Create device link** → **Copy link**
   (30 minutes, single use).
2. Paste the whole link into the app's pairing screen (or AirDrop/message it to your phone and paste it).
3. The app signs in, stores the session cookie in the iOS Keychain, and connects to the live WebSocket.

The tunnel hostname is temporary (Cloudflare Quick Tunnel): if it changes after a tunnel restart, create a fresh device
link and paste it again; the app re-pairs in place.

## What it does today (v1)

- Teammate tabs with brand icons (DeepSeek / OpenAI / Claude) and live state.
- Real conversation view: transcript messages, live streaming reply text, and expandable tool/command/file activity rows.
- Delivery queue with states (queued, waiting for busy/connection), cancel, retry, and **Stop this turn**.
- Live updates over `/live` WebSocket with a polling fallback and reconnects.
- Settings: teammate usage, recheck runners, create device links, sign out.
- Pairing/security: device-link sign-in only, cookie in Keychain, no credentials or links in the repo.

## Not yet (next)

- Message **steering** ("Steer now" vs "Queue next") — the app is ready to send a `mode` field on `POST /api/messages`,
  but the server side must ship first (planned in the Team Room rework).
- Inline image previews from `/api/media`, message search, push notifications.

## API used

`GET /api/health`, `POST /api/signin`, `GET /api/session`, `GET /api/state?agentId=`, `POST /api/messages`,
`POST /api/cancel-message`, `POST /api/retry`, `POST /api/stop`, `POST /api/refresh-connections`,
`POST /api/device-link`, `POST /api/signout`, `GET /api/event`, WebSocket `/live`. All requests carry the
`kewz_session` cookie and the server origin as `Origin`.

## Requirements

- iPhone/iPad on iOS 26 or later (built against the latest iOS SDK; iOS 26 is the Liquid Glass baseline).
- The PC side: Team Room server + tunnel running (`start-remote.ps1`) and reachable.
