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

## What it does (1.0)

Five tabs, Liquid Glass, one colour per teammate (Polaris gold, Nova violet, Atlas blue, Scout teal, Flint orange,
Sage green):

- **Team** — the team chat. Ask anything about the team; Polaris answers first, then Nova, then Atlas, whoever is free.
  Each answers from its own desk conversation with a live team digest, streams the answer, and shows why it answered
  when a question was handed over ("Nova is answering because Polaris is answering another question"). Stop, ask
  again, @mention a coordinator, suggestion chips, copy / select / share on long-press.
- **Agents** — every teammate's room like a messages list (state ring, what they are doing now, latest message,
  relay queue, holds, usage or balance, usage-limit pause). Each room shows the real conversation with grouped tool
  activity, the reply streaming live, decision cards (questions, approvals, permissions), the delivery queue and a
  composer.
- **Board** — overall progress ring; decisions waiting on Kewz; who is doing what right now; goals → milestones →
  tasks from `team-hub/PLAN.json`; charts of finished work per day by teammate, lore quests per region against the
  20-per-region target and the quest-engine milestones; a live work board (running / queued / blocked / done / failed).
- **Notes** — personal notes, saved on the phone instantly and synced to the PC; private unless shared with the
  coordinators (then the team chat can read them). Pin, search, swipe.
- **Inbox** — what needs you (decisions, questions, failed deliveries) and the updates feed. Settings is the gear in
  every tab.

**Background notifications** arrive through **Bark** (free App Store app, end-to-end encrypted with AES-256-GCM): set
up in Settings → Background notifications (install Bark, paste its key, enter the shown key in Bark's Push Encryption,
send a test). Tapping a notification opens the right screen via `teamroom://` links. While the app is open it shows
alerts itself and the PC holds the pushes.

**Speed and stability.** Lazy chat rows; Markdown rendered once and cached off the main thread; the v2 bridge API
(10 KB team summaries instead of a ~1 MB state on every change, ETag-revalidated conversations, streamed text as small
deltas only for the conversation on screen); ImageIO-downsampled images in a memory-capped cache; instant launch from
the last saved state; reconnect with backoff, a network-path monitor and a 50-second liveness watchdog; per-field
decoding so one bad value can never blank the app; a permanent address (Tailscale) and 30-day sliding sessions so the
phone stays paired.

## QA

CI runs unit tests (decoding, deltas, deep links, notes merge, stores), performance tests (conversation build, Markdown
rendering, payload decoding with clock and memory metrics; scroll hitch rate and launch time in the simulator) and UI
tests that capture every screen populated with the real team and board numbers — light, dark and an accessibility text
size. Screenshots and `results-and-metrics.txt` are in the `TeamRoom-qa` artifact of every run.

## 0.6.0 — DeepSeek balance and the harness teammate

- Decodes the bridge's `usage.balance` object: amount, currency, source, freshness, and every wallet on a
  multi-currency account. Amounts render with the currency's own symbol.
- The teammate row shows a balance chip for pre-paid accounts and keeps the 5-hour/weekly bars for everyone else.
- Settings shows `Balance … · as of … · source`, or `Balance not reported` with the bridge's reason when the PC has
  no balance source configured.
- Maps the new `dsh` provider to the DeepSeek brand mark.

## 0.5.1 — usage timestamp compatibility

Accepts the legacy numeric usage timestamp returned by older bridges as Unix epoch milliseconds,
while preserving string, null and absent timestamps. Incompatible JSON identifies the endpoint
and field without showing response bodies or credentials. No pairing reset is needed for this fix.

## 0.5.0 — task feedback and conversation fixes

- Finished, Working, Needs your input, Failed and Interrupted outcomes with timestamps and team counts.
- Durable updates inbox and optional local banners/sound/badge while the app is open and connected. Enable these in Settings; test notification and iPhone settings links are included. Native APNs registration and provider support are included. Closed-app delivery requires a push-enabled signed profile and matching APNs server credentials; a general signing certificate alone is not sufficient. The inbox catches up on reconnect.
- Normal conversation ordering is preserved. Failed deliveries are clearly separated in a Delivery queue with swipe-right Edit, swipe-left Delete, undo/restore, and a separate Retry action.
- Scroll-to-latest uses the conversation's measured scroll height; manual reading pauses following and the button restores it.
- Markdown tables render aligned columns with horizontal scrolling, inline styles and escaped pipes.
- Image attachments support pinch zoom, panning, double-tap, zoom buttons and Fit.

The bridge's new statusSummary field is optional; legacy explicit completion events remain supported so active runners do not need to be interrupted for the UI update. Tests cover tables, links, outcome precedence and notification deduplication. The GitHub workflow also exercises scrolling, table rendering and image zoom in the iOS simulator and exports screenshots. Install the new unsigned IPA using the existing sideload method, including KravaSign; an old installed build will not update itself.

Shared report links open an authenticated in-app preview; normal web links use the system browser. Missing or disallowed files show an error. The simulator tests also cover failed-delivery swipe/edit/delete/undo and report links.
