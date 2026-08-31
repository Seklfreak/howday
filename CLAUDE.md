# CLAUDE.md

Guidance for working in this repo. Hard-won gotchas — read before changing the
matching area.

## Project mechanics

- The `.xcodeproj` is **generated** — edit `project.yml`, then `xcodegen generate`.
  Never edit the project file directly; regeneration discards it.
- `Config/Secrets.xcconfig` is gitignored; copy from `Secrets.example.xcconfig`.
  In xcconfig files `//` starts a comment, so URLs need the `https:/$()/…` split.
- Versioning lives in `project.yml` (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`),
  wired into Info.plist via `$(…)`. Don't put literal versions in the plist
  properties — a literal silently overrides the build settings (this shipped a
  wrong version once).
- Manual signing settings live in `project.yml` under the target's **Release
  config only**. Do not pass signing settings on the `xcodebuild` command line:
  CLI settings hit SPM package targets (swift-crypto etc.), which refuse
  provisioning profiles. Debug stays on automatic signing for local device runs.
- Simulator smoke tests: don't build with `CODE_SIGNING_ALLOWED=NO` if you'll
  *run* the app — unsigned binaries break Keychain writes, and supabase-swift
  then reports "Auth session missing" right after a successful sign-in.
  Simulator builds sign locally without a team; the flag is for compile-checks only.

## Simulator UI testing (AXe)

Drive the app in the simulator with the AXe CLI (`brew install
cameroncooke/axe/axe`) — it reads the accessibility tree and injects touches
via the simulator's HID interface. Do NOT use `cliclick`/`screencapture`
window automation: it needs macOS Accessibility + Screen Recording permissions
and window-geometry guessing; AXe needs neither.

- Loop: `axe describe-ui --udid <UDID>` → find the element's frame (device
  points) → `axe tap -x -y` / `axe type` / `axe swipe`. Screenshots stay
  `xcrun simctl io <UDID> screenshot out.png`.
- **Always pass an explicit UDID** (`xcrun simctl list devices`). Simulator
  names are ambiguous — this machine has two "iPhone 17 Pro" devices, and
  boot-by-name may boot a different one than the UDID you then target
  (`simctl bootstatus` on the other device hangs forever).
- **Re-run `describe-ui` after anything that changes layout** (keyboard
  appearing, a form section added/removed) — cached coordinates land on the
  wrong element and taps "succeed" while doing nothing you wanted.
- `axe type` is HID-keycode based, **ASCII only — it cannot type emoji**
  (`No keycode found for character`). Instead: `printf '🥳' | xcrun simctl
  pbcopy <UDID>`, long-press the field (`axe touch -x -y --down`, sleep ~1s,
  `--up`), then `describe-ui` to find and tap the `Paste` callout button.
- **The iOS 26 simulator runtime does not render color emoji** — every emoji
  shows as a missing-glyph "?" box, at any size, in the app AND in the sim's
  Safari (that's how to prove it's not an app bug). Judge emoji rendering on a
  real device; in the sim, verify emoji correctness via the accessibility
  tree's AXLabels instead of screenshots.
- Sign-in uses the Supabase test phone numbers with the fixed OTP (deliberately
  not in this repo — see README/rls-proof env). They're readable via the
  Management API: `curl -H "Authorization: Bearer $(cat ~/.supabase/access-token)"
  https://api.supabase.com/v1/projects/<ref>/config/auth` → `sms_test_otp`.

## Supabase / data model

- **Phone hash format**: Supabase stores `auth.users.phone` as E.164 **without**
  the leading `+`. The signup trigger hashes that form; client-side contact
  matching (`PhoneNumber.hashForMatching`) must hash the identical form or
  nothing ever matches.
- **The social graph is contacts-based** (no friendships table, no display
  names): the sync-contacts Edge Function replaces the caller's
  `contact_links` rows from hashed contact uploads, and check-in visibility
  requires the link in BOTH directions (`are_mutual_contacts`). Names and
  photos are resolved client-side from the viewer's own address book
  (`ContactDirectory`), keyed by the `phone_hash` values `my_mutuals()`
  returns — safe to echo because a mutual contact's number is by definition
  already in the caller's address book.
- `profiles` and `contact_links` are fully sealed from client roles (RLS on,
  all grants revoked) — only service-role Edge Functions touch them. Any DB
  function that exposes `phone_hash` beyond mutuals (`match_phone_hashes`)
  must have EXECUTE revoked from `anon`/`authenticated` — otherwise it's a
  phone-number oracle.
- **`security definer` functions that call pgcrypto need
  `set search_path = public, extensions`** — Supabase preinstalls pgcrypto in
  the `extensions` schema, and a search_path pinned to `public` alone makes
  `digest()` unresolvable at runtime (broke every signup with "Database error
  saving new user").
- `checkins.day` is the user's **local** date computed client-side
  (`LocalDay`); `unique (user_id, day)` enforces one check-in per day.
  Edit-until-midnight falls out of always targeting today — no timer logic.
- Don't pass large arrays to PostgREST `.in()` filters — they go in the URL and
  500 past ~1000 values. Use a DB function taking an array (request body), as
  `sync-contacts` does via `match_phone_hashes`.
- Schema changes go through `supabase/migrations/` + `supabase db push`, never
  the dashboard. `scripts/rls-proof.sh` (env-var driven, see README) asserts
  every policy boundary against a live project — run it after RLS changes.

## Realtime

- **Push the user's JWT to the realtime socket before subscribing**
  (`Supa.client.realtimeV2.setAuth(token)`, see `BoardView`). An anonymous
  socket subscribes "successfully" but RLS filters every event — silent, no
  error, no events. Verified against this project.
- Tables must be in the `supabase_realtime` publication to emit
  postgres_changes (`checkins` is; new tables need a migration).

## Push notifications

- The check-in push trigger reads `project_url` and `push_fn_secret` from
  **Vault** (repo is public — no project ref in migrations) and silently
  no-ops if they're absent; the `push-checkin` Edge Function has
  `verify_jwt = false` and is gated only by the `x-push-secret` header.
- The trigger fires on insert **and** on an emoji change to a recent day, so
  edits notify too. Edits are rate limited per author (30 min) via the sealed
  `checkin_push_log` table, claimed atomically in the same
  `insert … on conflict … where` that records it. Inserts bypass the cooldown
  on purpose — there's at most one per user per day, and the daily alert must
  not be swallowed by an edit made just before midnight.
- APNs tokens are **environment-specific**: the `aps-environment` entitlement
  comes from the `APS_ENVIRONMENT` build setting (Debug = development,
  Release = production), and `PushRegistrar`'s `#if DEBUG` sandbox flag must
  match — a token sent to the wrong APNs host is just `BadDeviceToken`
  (and gets deleted by the function's dead-token cleanup).

## Analytics (Umami)

- `Core/Umami.swift` talks to Umami's `/api/send` directly — the same JSON the
  web tracker posts. Two things about that endpoint bite:
  **a request with no `User-Agent` is rejected**, and one whose UA trips
  Umami's bot filter gets a **`200` that stores nothing**. `browserUserAgent()`
  therefore has to keep looking like a browser; it is also where Umami reads
  the OS and device from, so don't reduce it to `Howday/1.0`.
- An app has no browser session for Umami to hash into a visitor id, so every
  event carries `payload.id` — a random UUID per install, kept in
  `UserDefaults`. Never put the Supabase user id (or anything derived from a
  phone number) there. Umami caps that field at 50 characters.
- Events **never carry the mood emoji**, a name, or a hash. `checkin_saved` /
  `checkin_edited` record that a check-in happened, not what it was; keep it
  that way unless the decision is made deliberately.
- Disabled in Debug (`#if !DEBUG` in `HowdayApp`, mirroring Sentry) and
  disabled whenever `UMAMI_URL`/`UMAMI_WEBSITE_ID` are empty — which is what CI
  and simulator builds get from the placeholder xcconfig. **CI compile-checks
  Debug only**, so the `#if !DEBUG` block is not built by `test.yaml`; a
  Release build (`-configuration Release CODE_SIGNING_ALLOWED=NO`) is the only
  local check that covers it.
- `Analytics.screen` drops a screen that repeats within 2 seconds: SwiftUI
  fires `onAppear` more than once on a NavigationStack root when a pushed view
  pops, which double-counted every return from History. Keep the time bound —
  suppressing *every* repeat would swallow genuine second visits.
- Every action event is filed under the last screen `Analytics.screen` was
  given, so anything that changes what's on screen without an `onAppear` has
  to say so. Dismissing a sheet is the one that bites: `HomeView` reports the
  board again when Settings closes, or taps get attributed to `/settings`.
- Adding `payload.id` made the app touch `UserDefaults`, a required-reason API,
  so `App/PrivacyInfo.xcprivacy` declares `CA92.1`. Keep it in the target's
  `sources` in `project.yml` — it must land at the `.app` root. The reasons key is
  `NSPrivacyAccessedAPITypeReasons`; the shorter `NSPrivacyAccessedAPIReasons`
  passes `plutil -lint` and is rejected on upload as ITMS-91056 (see
  TN3181).

## Onboarding & permissions

- Sign-in takes a **country + national number**, never a typed `+code`:
  `CountryCode` carries the ISO-region → calling-code table because iOS
  publishes no calling-code API (names and flags are still derived from the
  region, so they follow the device language). `PhoneNumber.e164` drops a
  leading trunk `0` — Italy is the one country that keeps it, and only on
  landlines, which can't receive the SMS anyway. A pasted `+…`/`00…` number
  moves the picker instead of landing in the national field.
- **Only onboarding (and Reminder settings) may raise the notification
  prompt.** `PushRegistrar.registerIfAuthorized()` deliberately never asks —
  it re-registers for APNs when permission already exists, so a rotated token
  still gets re-uploaded on every launch. The onboarding screen asks via
  `ReminderScheduler.sync`, so one prompt covers the daily reminder and
  friend-check-in pushes, and it lands after the screen that explains them.
  That screen is also what makes the daily reminder real: before it,
  `reminderConfigured` was only ever written by a Settings visit nobody made.
- `onboardingCompleted` (UserDefaults) is what stops onboarding reappearing
  on every launch after a "Not now" — the contacts authorization status alone
  can't tell a deliberate skip from a fresh install. `BoardView` still raises
  the contacts prompt on first board load; that stays the way back in for
  someone who skipped.

## Daily reminder

- The reminder fires at a **random minute inside a window** (default 8:00–22:00),
  so it is not one repeating trigger: `ReminderScheduler` books one
  non-repeating request per day (`daily-checkin-<yyyy-MM-dd>`) for the next 14
  days and `topUp()` extends the plan on every foreground (`RootView`
  `scenePhase`). `topUp` must never prompt — it only checks the current
  authorization status; `sync` is the one that asks, from onboarding/Settings.
- `reminderLastPlannedDay` (UserDefaults) is what stops a day from being booked
  twice: a request that already fired is no longer pending, so "not pending"
  alone can't tell "fired" from "never booked". `sync` skips today when today
  was planned before and its request is gone.
- Saving a check-in calls `cancelToday()`, which removes today's request and
  records the day under `reminderCheckedInDay`; `book` skips that day so a
  settings re-plan the same evening doesn't bring the reminder back.
- Window edges are stored as minutes since midnight (`reminderWindowStart`/
  `reminderWindowEnd`); the old `reminderHour`/`reminderMinute` keys and the
  single `daily-checkin` request are ignored/removed on the next `sync`.

## Auth / Twilio

- Twilio Verify on a **trial** account only delivers to verified caller IDs —
  Twilio error 21608 surfaces via Supabase as `sms_send_failed`. Multiple
  Twilio accounts are easy to confuse; the Account SID configured in Supabase's
  phone provider is the one that must be paid.
- Test phone numbers with fixed OTPs are configured in Supabase (Auth → Phone →
  Test OTPs), not Twilio — they send no SMS and are free. The credentials are
  deliberately NOT in this repo (public); they're needed for simulator sign-ins.

## CI (mirrors lab-tracker)

- `test.yaml` compile-checks; green `main` → `release.yaml`
  (Seklfreak/ai-release-action cuts the tag + notes) → `testflight.yaml`
  archives with a stored distribution cert and uploads; release notes become
  the build's "What to Test". Dormant without the secrets listed in
  `testflight.yaml`'s header.
- The stored `.p12` secret must contain **cert + private key** in **legacy**
  PKCS#12 encryption. `security import` exits 0 but yields "0 valid
  identities" for key-only or PBES2/AES p12s — always verify with
  `security find-identity` after changing the secret.
- Build number = CI run number; marketing version = the tag's major.minor
  (patch releases reuse the approved TestFlight version, so only minor/major
  bumps trigger a real Beta App Review). TestFlight requires strictly
  increasing build numbers within a version.

## Public repo

This repo is public with **no license** (all rights reserved) — keep it that
way unless told otherwise, and keep credentials, test-account details, and
private operational specifics out of committed files AND commit messages
(history is public too).
