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

## Supabase / data model

- **Phone hash format**: Supabase stores `auth.users.phone` as E.164 **without**
  the leading `+`. The signup trigger hashes that form; client-side contact
  matching (`PhoneNumber.hashForMatching`) must hash the identical form or
  nothing ever matches.
- `profiles.phone_hash` is revoked from client roles at the **column** level.
  Consequences:
  - Any app-side write to `profiles` must use `returning: .minimal` (or an
    explicit column list). supabase-swift's default `.representation` selects
    `*`, which trips the revoked column and fails the whole write with 42501.
  - Only service-role code (Edge Functions) may read `phone_hash`, and any DB
    function that exposes it (`match_phone_hashes`) must have EXECUTE revoked
    from `anon`/`authenticated` — otherwise it's a phone-number oracle.
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
  `match-contacts` does.
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
