# Team Room 1.0 — QA

Checklist modeled on Apple's HIG and on how the Claude and ChatGPT iOS apps behave. Every item is verified by a test
an AI can run (Kewz's rule: no "please check it on the phone" as the verification step). Results are filled from the CI
run that built the release IPA; screenshots are in that run's `TeamRoom-qa` artifact.

Legend: **U** unit test (`Tests/`), **UI** UI test with screenshot (`UITests/`), **P** performance test,
**B** bridge test (`team-console/tests`, 168 tests), **D** dry-run API check (`team-console/tools/verify-v2-api.mjs`).

## Chat behaviour (team chat and agent rooms)

| # | Expectation (Claude/ChatGPT parity) | How it is verified |
|---|---|---|
| C1 | Answers stream in as they are written; the view follows new text while you are at the bottom | UI `testTeamChatShowsAnswersHandOverAndStreaming`; D "answer streams over the socket" |
| C2 | Scrolling up to read stops the auto-follow; a jump-to-latest button appears and returns you | UI `testAgentsListAndRoomWithTableImageAndReport` (jump-latest) |
| C3 | Send turns into Stop while a coordinator answers; Stop ends the answer, "Ask again" retries | UI (Stop answer button present); B room stop/retry tests |
| C4 | Long-press: Copy, Select Text (full-screen selectable), Share | `MessageActions` on every message; UI screenshots |
| C5 | Markdown: headings, lists, quotes, tables that scroll sideways, code blocks with Copy, links | U table/fence tests, `testRenderedMarkdown…`; UI table + report link |
| C6 | Very long pasted context collapses with "Show full message" (loaded on demand) | D "full text of a long message loads on demand"; fixture `long-context` |
| C7 | Empty chat offers suggestions; @mention picks a coordinator | UI `testEmptyTeamChatOffersSuggestions`; B mention tests |
| C8 | Who answered and why is visible when a question is handed over | UI hand-over expansion; B election tests |
| C9 | Failures are explicit (reason + retry), never a silent spinner | B failover tests; failed-answer UI state |
| C10 | Haptics: send, answer finished, copy | `sensoryFeedback` on composer, answers, code copy |
| C11 | Keyboard: interactive dismiss, composer stays above it, grows to 6 lines | `scrollDismissesKeyboard(.interactively)`, `lineLimit(1...6)` in both composers |

## Navigation and notifications

| # | Expectation | How it is verified |
|---|---|---|
| N1 | Five tabs with badges (unread answers, needs input, inbox) | UI screenshots; `MainTabView` badges |
| N2 | Notification taps open the exact screen (`teamroom://chat/<id>`, `agent/<id>`, `notes/<id>`, `board`, `settings`) | U `testDeepLinksFromNotificationsOpenTheRightScreen` |
| N3 | Background notifications are end-to-end encrypted exactly as Bark decrypts them | B `bark.test.mjs` (AES-256-GCM, tag split as CryptoSwift `.combined`) |
| N4 | No duplicate or replayed notifications (dedupe, restart baseline, none while the app is open) | B bark dedupe/baseline; live-v2 presence test |
| N5 | Relay continuations do not flood the inbox; failures and needs-input always do | U `testNoticeLedger…IgnoresRelayCompletions` |

## Performance

| # | Expectation | How it is verified | Result |
|---|---|---|---|
| P1 | Team refresh is small | D: `/api/team` vs `/api/state` | 10.4 KB vs 1.03 MB (≈99% smaller; 3 KB vs 262 KB gzipped) |
| P2 | Unchanged conversations cost nothing to revalidate | D: ETag → 304 | 304 |
| P3 | Streaming sends only new text, only for the open conversation | B `live-v2.test.mjs` | deltas + per-client subscriptions |
| P4 | Building a 2,000-row conversation is fast | P `testPerformanceBuildingALongConversation` | (CI) |
| P5 | Markdown is rendered once and cached, off the main thread for history | P `testPerformanceRenderingLongMarkdown` | (CI) |
| P6 | Decoding a heavy conversation payload | P `testPerformanceDecodingAConversationPayload` | (CI) |
| P7 | Scrolling a long conversation does not hitch | P `testScrollHitchesInALongConversation` (hitch ratio) | (CI) |
| P8 | Launch time | P `testLaunchTime` | (CI) |
| P9 | Images cannot exhaust memory | `ImageStore`: NSCache 48 MB cap, ImageIO downsampling (700 px inline, 2400 px viewer) | design |

## Reliability

| # | Expectation | How it is verified |
|---|---|---|
| R1 | One malformed value never blanks the app (per-field and per-item lossy decoding) | U decoding tests (5 updated + snapshot lossy test) |
| R2 | Live updates recover by themselves: backoff with jitter, network-path change, 50 s liveness watchdog | `LiveConnection`; reviewed |
| R3 | A missed stream frame resyncs instead of showing garbled text | U `testStreamDeltas…` (UTF-16 bases), `testConversationStore…ResyncsOnGap` |
| R4 | Instant launch from the last saved state; "Updating" instead of a blank spinner | `DiskCache` restore in `boot()`; launch metric |
| R5 | The phone stays paired: permanent address and 30-day sliding sessions | Funnel verified from outside; auth renewal in bridge |
| R6 | Usage stops are enforced for Polaris (85/95) and Sage (90/95) | B `claude-usage.test.mjs` |

## Accessibility and appearance

| # | Expectation | How it is verified |
|---|---|---|
| A1 | Text follows Dynamic Type (all text styles, no fixed point sizes in content) | UI `testDarkModeAndLargeText` (accessibility2 screenshot) |
| A2 | Dark mode | UI dark screenshots |
| A3 | VoiceOver labels for avatars, status, usage, charts, buttons | accessibility labels in components; reviewed |
| A4 | Reduce Motion respected | `ActivityLine` and ring animations check `accessibilityReduceMotion` / static fallbacks |

## Results

Filled after the release CI run.
