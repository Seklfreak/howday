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
- APNs tokens are **environment-specific**: the `aps-environment` entitlement
  comes from the `APS_ENVIRONMENT` build setting (Debug = development,
  Release = production), and `PushRegistrar`'s `#if DEBUG` sandbox flag must
  match — a token sent to the wrong APNs host is just `BadDeviceToken`
  (and gets deleted by the function's dead-token cleanup).

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
- Build number = CI run number; marketing version = the tag. TestFlight
  requires strictly increasing build numbers within a version.

## Public repo

This repo is public with **no license** (all rights reserved) — keep it that
way unless told otherwise, and keep credentials, test-account details, and
private operational specifics out of committed files AND commit messages
(history is public too).
