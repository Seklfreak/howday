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
- **Don't install the Xcode 27.1 beta (the iPhone Duo one) alongside 27.0.**
  It upgrades the machine-wide CoreSimulator service (1171 → 1174), and AXe
  1.8.0's taps then report success and do nothing — on every simulator and
  runtime, from either Xcode. `axe type` still works; on the Duo even
  `describe-ui` times out, and its poses are Device Hub buttons with no
  `simctl` equivalent anyway. Stay on 27.0's service until AXe catches up.
  Deleting the beta does not undo it, and neither does re-running 27.0's
  `XcodeSystemResources.pkg`: the installer won't replace a framework with
  an older version. Remove `/Library/Developer/PrivateFrameworks/CoreSimulator.framework`
  first, reinstall that package from `Xcode.app/Contents/Resources/Packages/`,
  then `killall -9 com.apple.CoreSimulator.CoreSimulatorService`.
- **Use an iOS 26.5 (or newer) simulator runtime, not 26.3.** Under Xcode 27
  on macOS 27 the 26.3 runtime draws every emoji as a missing-glyph "?" box,
  in the app and in the sim's own Safari alike, even though the emoji font is
  in the runtime. A fresh 26.3 device is flaky beyond that (`simctl openurl`
  times out, home-screen widgets stay blank). A 26.5 device renders colour
  emoji normally. If "?" boxes show up, check the device's runtime
  (`xcrun simctl list devices`) before suspecting the app.
- Sign-in uses the Supabase test phone numbers with the fixed OTP (deliberately
  not in this repo — see README/rls-proof env). They're readable via the
  Management API: `curl -H "Authorization: Bearer $TOKEN"
  https://api.supabase.com/v1/projects/<ref>/config/auth` → `sms_test_otp`,
  where `TOKEN=$(security find-generic-password -s "Supabase CLI" -w)` — the
  CLI keeps its login in the macOS keychain, not in `~/.supabase`.
- A simulator that suddenly shows the sign-in screen after a test run is
  the unsigned test host: `xcodebuild test … CODE_SIGNING_ALLOWED=NO`
  installs an unsigned Howday.app over the signed one, and unsigned
  binaries can't read the keychain. It also leaves that unsigned product
  in the shared `-derivedDataPath`, so installing from there again just
  reinstalls it — **rebuild without the flag first**, then install. Signing
  in on the unsigned app appears to work and then reports "Auth session
  missing", which is the same fault wearing a different face.

## Supabase / data model

- **Phone hash format**: Supabase stores `auth.users.phone` as E.164 **without**
  the leading `+`. The signup trigger hashes that form; client-side contact
  matching (`PhoneNumber.hashForMatching`) must hash the identical form or
  nothing ever matches.
- A contact saved the way it is dialled at home (`0176 1234567`) carries no
  calling code, so `ContactDirectory.candidates` supplies one: the country of
  the signed-in user's **own** number, falling back to the device region. The
  device region alone is not enough — a German number stays German on a phone
  set to the US. Outside the NANP that national form is how most people save
  most numbers, and before this every one of them silently failed to match,
  which blanks the board in *both* directions because mutuality needs both
  links. Never hash a candidate starting with `0`: no calling code does, so it
  cannot equal a stored number.
- **The social graph is contacts-based** (no friendships table, no display
  names): the sync-contacts Edge Function stores the caller's hashed contact
  upload as `contact_hashes` and derives their `contact_links` rows from it
  (`replace_contact_hashes`), and check-in visibility requires the link in
  BOTH directions (`are_mutual_contacts`). Names and photos are resolved
  client-side from the viewer's own address book (`ContactDirectory`), keyed
  by the `phone_hash` values `my_mutuals()` returns — safe to echo because a
  mutual contact's number is by definition already in the caller's address
  book.
- **A signup has to link backwards, because the sync almost always runs
  before it.** Adding someone's number is what triggers your upload, so they
  are typically not registered yet when it lands; afterwards your address
  book is unchanged, so the client's fingerprint check skips every further
  upload for 24h. That is why `contact_hashes` is *kept* rather than matched
  and discarded: the `link_new_profile` trigger creates the incoming links
  for a new profile from everyone already holding its hash. The client half
  is syncing at sign-in (`RootView`, on reaching `.ready`) rather than at
  first check-in, plus a forced `syncIfNeeded(force:)` on pull-to-refresh.
- `profiles`, `contact_links` and `contact_hashes` are fully sealed from
  client roles (RLS on, all grants revoked) — only service-role Edge
  Functions touch them. Any DB function that exposes `phone_hash` beyond
  mutuals must have EXECUTE revoked from `anon`/`authenticated` — otherwise
  it's a phone-number oracle. `contact_hashes` is the most sensitive table in
  the schema: unlike everything else it retains hashes of numbers belonging
  to **non-users**, so never expose it, and never add a function that takes a
  hash and answers whether it is present.
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

## Offline & the check-in queue

- A save that fails with a transient network error (`isTransientNetwork`)
  is parked in `CheckinQueue` (one entry, `UserDefaults`) and retried on
  launch, foreground, and when `NWPathMonitor` reports the network back.
  A later save that succeeds clears it — draining it afterwards would
  resurrect the older tap. An entry for an earlier day is **expired, never
  saved**: `saveToday` cannot backdate and the queue must not become the
  way around that. HomeView shows the parked emoji immediately, board and
  all, and runs the retry behind it; waiting for the retry first was a
  spinner for as long as a dead network takes to say so.
- `Supa` sets `emitLocalSessionAsInitialSession: true`. The default first
  *refreshes* the stored session and emits nil when that fails, so an
  hour-old token with no network landed on the **sign-in screen**. Use
  `auth.currentSession` for anything that needs only the user id (the
  wildcard); `auth.session` refreshes and throws offline.
- The board waits at most 2s for the realtime subscription before loading
  — offline, `subscribe()` never returns — and refetches once it does.
- **Simulating offline**: point `SUPABASE_URL` in `Secrets.xcconfig` at
  `https://<ref>.invalid`. supabase-swift's keychain key is
  `sb-<first host label>-auth-token`, so the session survives the swap;
  any other host loses it. DNS fails instantly, but the auth retry
  interceptor (2 retries, backoff) stacks across the board's sequential
  requests, so the board takes ~25s to settle that way — airplane mode on
  a device fails at once. Restore the xcconfig afterwards (gitignored, so
  `git status` won't remind you).
- **Planting UserDefaults in the simulator**: `simctl spawn <udid> defaults
  write <bundle id> …` lands in the simulator-level preferences, which the
  app can *read* but its `removeObject` never touches — an entry planted
  that way looks un-removable. Write to the container plist instead:
  `$(simctl get_app_container <udid> <bundle id> data)/Library/Preferences/<bundle id>.plist`.

## Realtime

- **Push the user's JWT to the realtime socket before subscribing**
  (`Supa.client.realtimeV2.setAuth(token)`, see `BoardView`). An anonymous
  socket subscribes "successfully" but RLS filters every event — silent, no
  error, no events. Verified against this project.
- Tables must be in the `supabase_realtime` publication to emit
  postgres_changes (`checkins` is; new tables need a migration).

## Push notifications

- The push triggers read `project_url` from the sealed `push_config` table
  and `push_fn_secret` from **Vault** — the URL is the origin every client
  already ships, so only the shared secret is encrypted; neither is in a
  migration, because the repo is public. Both silently no-op if absent.
  (`ALTER DATABASE … SET` would be cheaper than either, but Postgres refuses
  a custom parameter there without superuser, which Supabase's `postgres`
  role is not.) The `push-checkin` Edge Function has
  `verify_jwt = false` and is gated only by the `x-push-secret` header.
- **The payload carries the mood** (`emoji`) and the sender's id
  (`sender_id`) alongside the hash, and that is a deliberate trade, not an
  oversight: it means moods pass through APNs, where Apple can read them.
  It buys the one thing that makes a friend's check-in reach a *locked*
  phone at once — `NotificationService` writes the new sky into the App
  Group itself (`SkySnapshot.applying(emoji:from:at:)`), so no widget has
  to go to the network. Marking the sky stale instead sent every widget to
  the board, and a widget's fetch runs on a locked phone with the radio
  asleep, which is both the slow part and the part that fails. It leaks
  nothing to the recipient — every recipient is a mutual contact who can
  already select that row through `board_today`. If that trade is ever
  revisited, the fallback is still in the extension and still correct.
- **The mood is in the payload but never in the banner.** `PushText` keeps
  the alert generic — "Anna just checked in 💫", where the 💫 is a fixed
  sparkle — because seeing a friend's mood is what checking in earns, and
  the board and both widgets gate on `mine != nil`. A banner carrying the
  emoji would route around that gate entirely. The extension reads the
  payload's mood for the widget sky and nothing else.
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

## Named pushes (Notification Service Extension)

- `Notifications/` is the `HowdayNotifications` extension
  (`dev.winktech.moodring.notifications`). The push functions send the
  sender's `phone_hash` and a `kind` as top-level payload keys plus
  `mutable-content: 1`; the extension looks the hash up in `names.json` in
  the App Group container (`group.dev.winktech.moodring`) and rewrites the
  body via `PushText`. Anything missing leaves the server's generic text.
  The hash is safe to send because every recipient is a mutual contact.
- `NameMap` (in `Shared/`, compiled into app and extension) is rewritten
  by `ContactDirectory.currentIndex()` on every index build. It is written
  with `completeFileProtectionUntilFirstUserAuthentication`, **not** full
  protection: pushes arrive on a locked phone and the extension runs right
  then; a fully protected file is unreadable and the lookup fails exactly
  when it matters.
- **The simulator never runs service extensions.** `simctl push` with
  `mutable-content` delivers the payload untouched and the extension
  process is never launched, so a generic banner in the simulator proves
  nothing. Verify on a device (Console, subsystem `dev.winktech.moodring`,
  category `notifications` logs the outcome, never the name).
- An unsigned build (`CODE_SIGNING_ALLOWED=NO`, i.e. CI and simulator
  smoke builds) has no entitlements and therefore no group container:
  `containerURL(forSecurityApplicationGroupIdentifier:)` is nil and
  `NameMap.write` is a no-op. Tests point `NameMap.directory` at a temp
  directory for that reason.
- Apple side: the App Group has **no App Store Connect API** — it was made
  and attached to both App IDs in the portal by hand; bundle IDs and
  profiles went through the API. Two profiles ship: `Moodring App Store` for the
  app and `Howday Notifications App Store` for the extension, as the
  `APP_STORE_PROFILE` / `APP_STORE_PROFILE_NOTIFICATIONS` secrets.
  The widget ships as a third: `Howday Widgets App Store` /
  `APP_STORE_PROFILE_WIDGETS`. Changing capabilities on an App ID
  invalidates its profile: delete and recreate through the API, then
  update the secret.
- The extension's `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` must
  equal the app's or App Store Connect rejects the upload; CI passes both
  on the `xcodebuild` command line, which reaches every target.

## Widgets (WidgetKit extension)

- `Widgets/` is `HowdayWidgets` (`dev.winktech.moodring.widgets`), one
  widget kind `FriendsSky` in small/medium/large: the friends' emoji
  afloat, sized by recency, named from the App Group `names.json`; the
  large one places them by check-in time (`board_today` now returns
  `checked_in_at` for this). Display only — nothing is written from it.
- **The widget reads the app's Supabase session straight from the
  keychain.** Its entitlements list the app's own keychain group
  (`$(AppIdentifierPrefix)dev.winktech.moodring`) *first*, so a default
  `KeychainLocalStorage` finds the app's items and a token refresh made by
  the widget lands where the app looks. No Keychain Sharing capability is
  needed on the App ID for that — every profile already allows the team's
  groups. Both processes may refresh the same token; Supabase's reuse
  window covers the race, but if sign-outs ever cluster around widget
  refreshes, that is the first suspect.
- The widget's Info.plist needs `SUPABASE_URL` / `SUPABASE_ANON_KEY` of
  its own (`AppConfig` reads `Bundle.main`, which is the appex bundle); the
  TestFlight archive's command-line settings reach every target, so the
  same secrets populate it.
- **Never call `WidgetCenter.reloadAllTimelines()` from the app — go
  through `WidgetSync`.** Every request draws on the same daily refresh
  budget iOS gives a widget, and the ones carrying nothing new are what
  push the ones that matter past it; a friend's push arriving on a spent
  budget is a widget that does not refresh at all. The board used to ask
  on *every* read — each appear, each pull, each realtime event, identical
  board or not. `WidgetSync.publish` now writes the board into the App
  Group (`SkySnapshotStore`) and reloads only when `showsSameAs` says a
  viewer would see something different.
- That store is also what the widget reads: `SkyRepository.load` serves a
  published snapshot up to `SkySnapshot.freshFor` (90s) old instead of
  making its own round trip, which matters because a refresh usually runs
  on a locked phone where the round trip is the part that fails. **So
  anything that changes the board without reading it back must
  `invalidate()` first** — your own check-in, the queue draining, the
  lock-screen intent — or the widget serves the sky from before the change.
  A friend's push is the exception: it carries the mood, so the extension
  writes the change rather than announcing one (above). `SkySnapshot.Patch`
  has three answers, and each is load-bearing: `.written` reloads,
  `.cannotAnswer` (no mood in the payload, a sender who is not on the
  stored sky, yesterday's sky) falls back to `invalidate()` plus a reload,
  and `.alreadyShown` — the app read the board just before the push landed
  — does **neither**. Folding that last case into the fallback spends a
  fetch and a reload proving nothing changed, which is a reload the next
  friend's push then does not get. Sign-out must `clear()` it, or the next person to
  pick the phone up still sees a friend's mood.
- The push extension calls the handler a fifth of a second after the
  reload: handing back the content is what lets iOS tear the process down,
  and the reload is a message to the widget daemon that has to leave
  first.
- `SkyLayout` is deterministic (SplitMix64 seeded by day and size) so a
  refresh never reshuffles the sky within a day. It, `SkyFriend`,
  `SkySnapshot` and `MoodEmoji` live in **`Shared/`** rather than
  `Widgets/` for one reason: an app-hosted test bundle cannot
  `@testable import` an extension module, so anything the tests need has
  to reach them through the app module. `Widgets/` keeps only what needs
  WidgetKit or Supabase.
- `CheckInWidget` (`Widgets/CheckInWidget.swift`) is the lock screen:
  circular = your ring (dashed "?" before check-in, your emoji inside an
  arc of the day left after), rectangular = the six-mood picker before,
  friends latest-first after. The picker's `Button(intent:)` runs
  `CheckInIntent`, **the one write a widget makes**: the same upsert as
  `CheckinRepository.saveToday` (duplicated there because the repository
  sits behind Sentry tracing the widget doesn't link), no offline queue.
  `HomeView.load()` cancels today's reminder when a row exists, which is
  how a lock-screen check-in silences the nudge. `RootView` reloads all
  timelines on sign-in and sign-out so a signed-out phone doesn't keep
  showing friends' moods until the next half-hourly refresh.
- Lock-screen widgets are added in the simulator via `axe button lock`,
  long-press, Customize, the "ADD WIDGETS" strip, then Howday in the
  sheet. Both accessory families render there and run the real timeline.
- The simulator can add the widget (long-press home → Edit → Add Widget →
  search Howday, driven with AXe) and runs the real timeline with the
  app's session. Gallery previews show `SkySnapshot.placeholder`.

## Analytics (Umami)

- `Core/Analytics.swift` talks to Umami's `/api/send` directly — the same JSON the
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
- **The widgets report too, and share the app's identity.** `Shared/Umami.swift`
  holds the visitor id, the payload shape and the POST; `Core/Analytics.swift`
  adds the app's queue and screen state, `Widgets/WidgetAnalytics.swift`
  fires one awaited event (a widget process dies too soon for a queue).
  The visitor id lives in the **App Group**, not `UserDefaults.standard`,
  or every widget user would count as a second person; an install from
  before that adopts its old id rather than minting a new one. The app
  publishes its measured screen size there too — an extension has no
  window and would report `0x0`.
- Widget events: `widget_opened` (a tap, via `howday://open?source=…` on
  `widgetURL` and the Control Center tile's `OpenURLIntent`), `widget_active`
  (**the denominator** — which widgets are installed, at most once a day per
  widget and size, throttled in the App Group), and `checkin_saved` from the
  lock-screen picker. Every one carries a `source` from `WidgetSource`, and
  the app's own check-ins carry `source: app` so the two are comparable.
  Those raw values are schema: change one and the reports split at that date.
- The widget target needs `UMAMI_URL` / `UMAMI_WEBSITE_ID` in **its own**
  Info.plist — `Umami.config()` reads `Bundle.main`, which in an extension
  is the appex. Same for the `#if !DEBUG` rule below: a Release build is
  the only thing that compiles `WidgetAnalytics`.
- Adding `payload.id` made the app touch `UserDefaults`, a required-reason API,
  so `App/PrivacyInfo.xcprivacy` declares `CA92.1`. Keep it in the target's
  `sources` in `project.yml` — it must land at the `.app` root. The reasons key is
  `NSPrivacyAccessedAPITypeReasons`; the shorter `NSPrivacyAccessedAPIReasons`
  passes `plutil -lint` and is rejected on upload as ITMS-91056 (see
  TN3181).

## Colour on the accent

- **Never leave a filled button's label to `.borderedProminent`.** It writes
  white on the tint, and every accent in the scale is a bright colour:
  measured on screen, white on the gold is **1.53:1**, and no mood does
  better than 2.8:1 — against the 4.5:1 body-sized text needs. `.onAccent()`
  puts the mood's own `deep` there instead, which measures 6:1 to 10:1 on
  the same fills. It has to sit **inside** the button's label, where it
  beats the style's own choice; outside the button it is ignored.
- That modifier reads `\.moodTheme`, which is why every screen sets its mood
  with `.moodTheme(_:)` rather than `.tint(_:)`. A tint carries the accent
  and nothing else, and the accent alone is not something you can write on.
- A spinner inside such a button needs it too — a white `ProgressView` on
  the gold is as invisible as the label was.

## Invites

- `INVITE_URL` is a build setting in `project.yml`, not in
  `Config/Secrets.xcconfig`. It is a public link rather than a credential,
  and putting it behind a CI secret only adds a way to ship an "Invite a
  friend" button with nothing behind it. `AppConfig.inviteURL` stays
  optional all the same: blank it and every entry point disappears, which
  is better than sharing a link that goes nowhere.
- **The share sheet gets ONE item — `InviteItem` — and no `message:`.**
  `ShareLink`'s `message:` is a *second* item, and the sheet lets every
  target pick from the pile, which goes wrong in both directions: with the
  link in the message as well as the URL item, Messages takes both and puts
  it in the bubble twice; with the link only in the item, Copy takes the
  message and leaves the clipboard holding an invite with no way to install
  the app. Both were seen. One `Transferable` exporting text first and URL
  second cannot do either — whatever a target picks, it gets the sentence
  and the link, once. Don't reintroduce `message:` to "add the sentence":
  the text representation already carries it.
- `SharePreview("Howday", image: Image(.shareIcon))` is not decoration: a
  URL nobody has fetched has no metadata, so without it the sheet heads the
  invite with Safari's compass and the bare host. `ShareIcon` is a 256px
  copy of the app icon — the real `AppIcon` asset can't be loaded as an
  `Image` at runtime.
- **What the recipient's link preview says is not the app's to decide.** The
  invite host is a bare redirect to the beta join page, so Messages follows
  it and renders *that* page's OpenGraph tags. Giving the recipient a
  Howday-branded card means putting real `og:` tags on the landing page
  itself; no change on this side can do it.
- The copy is the feature, which is why `Invite` is a pure enum next to
  `InviteTests` rather than strings in a view. The message ends on a colon
  and `shareText` puts the link after it — they are one sentence, so don't
  repunctuate one without the other.
- **The mutual-contacts rule is explained to the sender, not the
  recipient.** `InviteSheet` is where it belongs, because the sender is the
  one who can act on it; an invite that opens by instructing a stranger to
  save your number reads like a chore. The message was written that way
  once and taken back out.
- `InviteSheet` explains before it shares. The mutual-contacts rule is the
  thing nobody guesses, and it is the *sender* who has to act on it — a
  share sheet on its own never tells them.
- Three entry points, all opening the same sheet: the empty board's action,
  a tile under the board's grid (the one that survives the board filling
  up), and Settings' "Friends" section. Each passes its own `source` to
  `invite_opened`; those raw values are schema, like `WidgetSource`.
- Settings' contact count comes from `ContactDirectory.mutualCount()`,
  which is server-side only — it is right even with contacts access off,
  where the board itself can show nothing.

## Onboarding & permissions

- Sign-in takes a **country + national number**, never a typed `+code`:
  `CountryCode` carries the ISO-region → calling-code table because iOS
  publishes no calling-code API (names and flags are still derived from the
  region, so they follow the device language). `PhoneNumber.e164` drops a
  leading trunk `0` — Italy is the one country that keeps it, and only on
  landlines, which can't receive the SMS anyway. A pasted `+…`/`00…` number
  moves the picker instead of landing in the national field — `PhoneNumberField`
  is a `UIViewRepresentable` only because `shouldChangeCharactersIn` is the one
  place a paste is distinguishable from typing (multi-character insertion vs.
  one character per keystroke). Guessing from the text instead — a jump in
  length between two `onChange` values — reads fast typing as a paste and
  swallows the rest of the number. It holds its own first-responder state:
  a `FocusState` case no SwiftUI view claims is reset to nil, which drops the
  keyboard.
- The country list's rows are plain `Button`s, so they need
  `.contentShape(.rect)`: a plain button is hittable only where it draws
  something, and the `Spacer` between the name and the dial code is most of
  the row. Without it most taps land on nothing.
- **Only onboarding (and Reminder settings) may raise the notification
  prompt.** `PushRegistrar.registerIfAuthorized()` deliberately never asks —
  it re-registers for APNs when permission already exists, so a rotated token
  still gets re-uploaded on every launch. The onboarding screen asks via
  `ReminderScheduler.sync`, so one prompt covers the daily reminder and
  friend-check-in pushes, and it lands after the screen that explains them.
  That screen is also what makes the daily reminder real: before it,
  `reminderConfigured` was only ever written by a Settings visit nobody made.
- iOS 18 **limited** contacts access counts as authorized for the sync and
  the board, and `BoardView` shows a banner with the visible-contact count
  and an "Add more" button (`.contactAccessPicker`, which needs
  `import ContactsUI`, not just SwiftUI). The picker's completion runs
  *before* `CNContactStoreDidChange` is posted, so the reload it triggers
  calls `ContactDirectory.noteAddressBookChanged()` first — otherwise it
  reads the cached index and the new contacts show up one refresh late.
- A mutual whose number is no longer readable locally renders as "Friend"
  until the next upload drops the link — the automatic sync after a
  permission change is not awaited by the board's first fetch, so that
  interim card is expected for a moment, not a bug in the directory.
- `onboardingCompleted` (UserDefaults) is what stops onboarding reappearing
  on every launch after a "Not now" — the contacts authorization status alone
  can't tell a deliberate skip from a fresh install. `BoardView` still raises
  the contacts prompt on first board load; that stays the way back in for
  someone who skipped.

## History

- The months page with the **system's own** paged scrolling: a horizontal
  `ScrollView` over a `LazyHStack` of month anchors (five years back, the
  current month last), `.scrollTargetBehavior(.paging)`,
  `.scrollPosition(id:)` for the header, `.defaultScrollAnchor(.trailing)`
  to open on today. **Do not hand-roll this with a `DragGesture`** — it was,
  and it felt stiff: a gesture commit on distance alone ignores velocity so
  a flick springs back, a fixed-duration animation ignores how fast the
  finger moved, `minimumDistance` swallows the first points, and none of it
  can be interrupted mid-animation. Velocity, deceleration, rubber-banding
  at the ends and interruption are exactly what the scroll view gives free.
- One query covers the month either side as well as the one on screen, and
  `monthCache` keeps every month seen this visit — a page arriving empty
  and filling in a moment later is what reads as flicker.
- The page is fixed at six rows so a five-row month cannot change the
  height mid-swipe, and each month carries the screen margin itself so the
  pager can span the full width; the `edgeFade` mask then fades over that
  margin rather than across a day cell.

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

## Unit tests

- `Tests/` is the `HowdayTests` target (Swift Testing, `@testable import
  Howday`), run by `xcodebuild test -scheme Howday` — the scheme is
  declared explicitly in `project.yml` so it includes the test target;
  CI's build job runs `test`, not `build`. Local:
  `xcodebuild test -project Howday.xcodeproj -scheme Howday -destination
  'platform=iOS Simulator,id=<UDID>' CODE_SIGNING_ALLOWED=NO`.
- It covers the pure pieces, which is where every client regression has
  been: `PhoneNumber`, `CountryCode`, `ContactDirectory.candidates`,
  `MoodEmoji`, `LocalDay`, `ReminderScheduler.plan` (the booking logic
  minus the random draw and the notification center), and
  `CheckinQueue.drain` (with an injected save). Keep new logic in that
  shape — a pure function beside the side effect — so it lands here too.
- `#expect(cond, message)` takes a `Comment`, which is a string *literal*
  type: pass `"\(value)"`, not `value`, or it fails to compile.
- `CheckinQueueTests` is `.serialized` and points `CheckinQueue.defaults`
  at a throwaway suite per test; the queue is process-wide state, and
  Swift Testing runs suites in parallel by default.
- Seen once: a run with failing tests reported the failures and then
  `xcodebuild test` never exited (a passing run exits in seconds). If a
  CI test job hangs rather than going red, read the log for `✘` lines.

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
- `release.yaml` only triggers a TestFlight build when the release touched
  the shipped code — the path filter names `App/`, `Widgets/`,
  `Notifications/`, `Shared/`, `Config/` and `project.yml`. A new source
  directory must be added there, or its releases get a tag and no build
  (v1.23.1 and v1.23.2 were widget-only and shipped nothing).
- Build number = CI run number; marketing version = the tag's major.minor
  (patch releases reuse the approved TestFlight version, so only minor/major
  bumps trigger a real Beta App Review). TestFlight requires strictly
  increasing build numbers within a version.

## Privacy policy & terms (howday-web)

The privacy policy (howday.app/privacy-policy/) and terms of service
(howday.app/terms/) live in the sibling repo `Seklfreak/howday-web`, not
here. Both are written from what the app **actually does** — that the
address book never leaves the device, which hashes are kept and why, what a
push carries, that sign-in codes are the only SMS — so a change here can
make them wrong without anything in this repo failing.

- **Any change that alters what the app stores, sends, or shares must update
  the documents in the same piece of work**, not as a follow-up. Check both
  pages whenever you touch: what goes to Supabase (new column, table, or
  retention), contact hashing/matching/`sync-contacts`, what a push payload
  contains, analytics events (the policy promises no emoji, name, number or
  hash is ever recorded), Sentry/PII settings, any new SDK or third-party
  service, hosting region, SMS behaviour, the age requirement, or the scope
  of **Delete account**. Monetisation of any kind rewrites the terms
  (liability cap, Apple's paid-app wording).
- Read the relevant section of each document before deciding nothing
  changed; the policy is specific enough that "probably still accurate" is
  usually wrong.
- When editing: bump **Last updated** in both places on the page (the
  `.stamp` and the footer), keep the two documents consistent with each
  other, and if the change is material, announce it in the app — the policy
  promises that. Pushing `main` in howday-web deploys the site.
- The three `[YOUR …]` placeholders (responsible party, postal address,
  contact email) are shared by both documents and must be filled on both
  pages at once; CI there warns while any remain.
- Settings links to both pages via `AppConfig.privacyPolicyURL` /
  `termsURL`, and the App Store record points at the same URLs. Moving a
  page means changing all three.

## Wording: it is an emoji, never a mood

**Nothing a user, tester, reviewer or visitor can read may say "mood"** —
or "feeling", "mental", "wellbeing", "health", or anything else that frames
Howday as tracking how someone *is*. That includes the indirect forms:
**"How are you?", "how your day is going", "how your day went", "the emoji
your day feels like", "see how your friends are doing"** all say mood
without the word, and all have been in the copy. The emoji is not *of*
anything: you pick one, friends see it. Say "today's emoji", "pick one
emoji", "your friends' emoji", "checked in". The terms of service say
Howday is not a mental-health or crisis service; every one of those
phrases argues the other way, and "consumer health data" statutes
(Washington's MHMDA and its copies) turn on exactly that framing.

Where the rule applies, and where the word has crept in before:

- **UI strings** in `App/`, including notices, onboarding, empty states and
  `accessibilityLabel`s (VoiceOver reads them out).
- **Notifications**: `ReminderScheduler` body, `Shared/PushText`, and the
  server-side fallback text in `supabase/functions/push-checkin` (that one
  needs `supabase functions deploy` — it is not in CI).
- **Widgets and intents**: `configurationDisplayName`, `.description(…)`,
  `IntentDescription`, Siri phrases.
- **Analytics screen names** in `Analytics.swift` (they show up in Umami).
- **App Store Connect**: app name and subtitle, App Store description,
  keywords, promotional text, the TestFlight beta description
  (`betaAppLocalizations`), beta review notes, and each build's "What to
  Test" (`betaBuildLocalizations`). The name was "Howday: Moods with
  Friends" until 2026-09-22.
- **Generated release notes**: `release.yaml`'s `project-description`
  carries the rule because the notes become What to Test and are generated
  from commits that do say "mood". Keep that paragraph when editing it.
- **Public prose**: `README.md`, `ROADMAP.md`, and everything in
  `Seklfreak/howday-web` (pages, meta descriptions, Open Graph text).

Exempt: identifiers (`MoodEmoji`, `MoodTheme`, `.moodTheme`, the Sentry
project, the bundle id), SQL migrations already applied, and existing code
comments. New code and comments should still say emoji or check-in. Before
shipping copy, run
`grep -rn -i mood App Widgets Notifications Shared supabase/functions README.md ROADMAP.md`
and check that every hit is an identifier or a comment; then
`grep -rn -i -E "how are you|how your|are doing|feels? like|day went" App Widgets Shared`
for the indirect forms.

## Public repo

This repo is public with **no license** (all rights reserved) — keep it that
way unless told otherwise, and keep credentials, test-account details, and
private operational specifics out of committed files AND commit messages
(history is public too).
