# Roadmap

Ordered by effort, smallest first. Leverage is called out per item so the
order does not read as priority: the invite path is the biggest lever in the
list and also one of the cheapest, the widget is the most valuable and the
most expensive.

Effort: **S** = an afternoon, **M** = a few days, **L** = a week or more,
usually because Apple-side setup (App IDs, profiles, CI secrets) is involved.

Release mechanics to keep in mind: a **minor** version bump is a real Beta App
Review (hours to a day), a patch is not. Batch user-visible features into a
minor; ship the invisible ones (tests, offline queue) as patches whenever.

| # | Item | Effort | Leverage | Depends on |
|---|------|--------|----------|------------|
| 1 | Dynamic Type pass — **done** | S | low | — |
| 2 | Invite share sheet | S | **highest** | — |
| 3 | Limited contacts access (iOS 18) — **done** | S | medium | — |
| 4 | Offline check-in — **done** | M | medium | — |
| 5 | Swift unit tests in CI — **done** | M | medium | — |
| 6 | Named pushes — **done**, device check pending | M–L | high | App Group |
| 7 | Widget, control, Siri | L | high | App Group, shared session, 4 |

---

## 1. Dynamic Type pass — S — done

**Problem.** Emoji buttons, board avatars, the check-in badge and the History
day cells all use `.system(size:)` and fixed frames, so nothing on the two
main screens responds to the user's text size. The History day number is 9pt
on days with a check-in, which is below what anyone should have to read.

**Approach.**
- `EmojiButton` takes its `diameter` / `fontSize` through
  `@ScaledMetric(relativeTo: .title)`; same for the 56pt avatar in `BoardCard`
  and the 26pt badge.
- The home picker's three-column `LazyVGrid` drops to two columns when
  `dynamicTypeSize.isAccessibilitySize` — six 100pt circles do not fit three
  across at the largest sizes.
- `DayCell`: raise the day number to `.caption2` minimum and let the cell
  height scale; the month grid already flexes horizontally.
- Friend names get `.minimumScaleFactor(0.8)` before truncating.

**Verify.** AXe in the simulator at `UICTContentSizeCategoryAccessibilityXXXL`
(`xcrun simctl ui <UDID> content_size extra-extra-extra-large` and the
accessibility variants), one screenshot per screen.

**Decisions.** None. Do it before the App Store submission; reviewers do test
this.

## 2. Invite share sheet — S

**Problem.** The social graph grows only when two people have each other's
numbers *and* both install the app. There is no way to cause the second half
from inside the app: a new user who checks in lands on "No friends yet" with
no action, and the "someone in your contacts joined" push cannot fire for
anyone until somebody outside the app tells them about it.

**Approach.**
- A `ShareLink` with the install link and a short text that says what the
  recipient actually has to do: *"I'm on Howday — a one-tap daily mood
  check-in. Add me to your contacts and we'll see each other's day:
  <link>"*. The contacts sentence matters; without it people install, see an
  empty board and leave.
- The link comes from an `INVITE_URL` build setting in the xcconfig, same
  pattern as `UMAMI_URL`: the public TestFlight link now, the App Store URL
  after launch, with no code change between the two.
- Three placements: the "No friends yet" `ContentUnavailableView` gets it as
  its action, Settings gets an "Invite friends" row at the top, and the
  board's toolbar or header gets a small persistent entry so it is still
  reachable once the board has people on it.
- Track `invite_shared` in Umami (the tap, not the outcome — iOS does not
  reliably report completion).

**Decisions.** Whether the last onboarding screen should end on the share
sheet too. Probably yes once the App Store link exists, probably not while it
is a TestFlight link that asks the recipient to install TestFlight first.

## 3. Limited contacts access (iOS 18) — S — done

**Problem.** `ContactDirectory.isAuthorized` treats `.limited` as authorized,
which is right for the sync, but the UI then has no idea that the user only
shared three contacts. They see a near-empty board, the "Contacts access is
off" state never appears, and nothing explains why their friends are missing.

**Approach.**
- Expose the raw status (`full` / `limited` / `denied`) from
  `ContactDirectory` rather than a Bool.
- When limited, `BoardView` shows a small banner above the grid: *"Howday can
  see N of your contacts."* with an "Add more" button that presents
  `.contactAccessPicker(isPresented:)` (iOS 18, `#available`-gated; the
  deployment target stays 17).
- The empty-board state carries the same banner, since that is where a
  limited selection bites hardest.
- No sync plumbing needed: expanding the selection posts
  `CNContactStoreDidChange`, which the existing observer already turns into
  a re-index and, because the fingerprint changes, an upload.

**Decisions.** Whether onboarding should mention limited access at all. Lean
no: the system sheet explains it, and the banner catches the outcome.

## 4. Offline check-in — M — done

**Problem.** The tap is the whole product, and in a tunnel it fails: `lockIn`
rolls `selected` back to the last confirmed emoji and shows an error. The day
is lost unless the user remembers to try again.

**Approach.**
- Persist `(emoji, day)` as a pending check-in in `UserDefaults` (App Group
  container once item 7 exists, so the widget shares the same queue).
- Only queue on transport failures (`URLError`). A 4xx from PostgREST or RLS
  means the server rejected it and should still roll back and report.
- On a queued save the picker keeps the chosen emoji and shows a quiet
  *"Saving when you're back online"* line instead of red text. Rolling back
  reads as the app refusing the choice, which is the wrong message.
- Retry on `scenePhase == .active` and when an `NWPathMonitor` path becomes
  satisfied; `HomeView.load()` drains the queue before reading today's row.
- A pending entry whose `day` is no longer today is discarded, not saved:
  `saveToday` deliberately cannot backdate, and a silent "yesterday" write
  would bypass that. Show a one-line note that yesterday's mood did not make
  it, then clear it.
- `ReminderScheduler.cancelToday()` stays where it is (after the confirmed
  save) so a reminder still fires if the queue never drains.
- Umami: `checkin_queued`, and `checkin_saved` / `checkin_edited` when the
  drain succeeds, so the funnel still counts each check-in once.

**Verify.** Simulator with network conditioner off/on; the existing AXe loop.
Unit test the queue's day-rollover rule (see item 5).

## 5. Swift unit tests in CI — M — done

**Problem.** There are none. The SQL graph tests cover the schema, but every
client-side regression in the history has been in pure code: national-number
matching, pasted-number detection, wildcard emoji components, reminder
booking, the local-day formatter. `test.yaml` only compile-checks Debug, so
none of it is guarded.

**Approach.**
- `HowdayTests` target in `project.yml` (Swift Testing; Xcode 16+ is already
  what CI runs). `xcodegen generate` picks it up.
- Make the pure pieces reachable: `ContactDirectory.candidates(for:homeDial:)`
  and `insert(national:dial:into:)` go from `private` to internal, and
  `ReminderScheduler.book` splits into a pure planner that returns
  `[(day: String, minute: Int)]` and the thin `UNUserNotificationCenter`
  writer around it.
- First cases, one file per subject:
  - `PhoneNumber.e164`: trunk `0` dropped, Italy kept, NANP digit count.
  - `PhoneNumber.hashForMatching`: hashes the `+`-less E.164 form, pinned
    against a known digest so a drift from the SQL trigger's form is caught.
  - `ContactDirectory.candidates`: national format gets the home dial, a
    candidate starting with `0` is never hashed, `+`/`00` forms normalise.
  - `CountryCode.international(in:)` and `split`: shared codes (+1, +7),
    longest-prefix wins.
  - `MoodEmoji.all`: no modifiers, no hair components, none of the five
    suggestions; `wildcard(for:day:)` is stable for the same input and
    differs across days.
  - `LocalDay.string(for:)`: fixed date across a few time zones, and that
    the cached formatter follows a time-zone change.
  - Reminder planner: skips the checked-in day, never books a past minute
    today, honours `lastPlanned`, produces at most `horizonDays` entries.
  - Offline queue day rollover (item 4).
- `test.yaml` build job runs `xcodebuild test` on a simulator destination
  instead of `build`; same unsigned settings as today.

**Decisions.** None. Land this before items 6 and 7 touch the same code.

## 6. Named pushes — M–L — done (device check pending)

**Problem.** "A friend just checked in 💫" is the same text every time, so it
gets muted within a week. The server can never know a name, but the sender's
`phone_hash` is already safe to hand to their mutuals (it is by definition a
number in the recipient's address book), and the recipient's device can turn
it into a name.

**Approach.**
- **Payload.** `push-checkin` and `push-joined` look up the sender's
  `phone_hash` from `profiles` (service role, same function) and send it as a
  custom key with `mutable-content: 1`. `checkin_push_recipients` /
  `join_push_recipients` already restrict delivery to mutuals, so nothing
  new leaks; write that reasoning next to the field.
- **Name map.** `ContactDirectory.localIndex` already builds
  `phone_hash → ContactRef`. Write a `[hash: name]` JSON file into the App
  Group container on every re-index. Names never leave the device; the map
  is just a second copy of what the board already resolves.
- **Notification Service Extension.** New target in `project.yml`
  (`app-extension`, point `com.apple.usernotifications.service`, bundle id
  `dev.winktech.moodring.notifications`). It reads the map, rewrites the
  body to *"Anna just checked in"* / *"Anna changed her mood"* /
  *"Anna joined Howday"*, and falls back to the current generic text when the
  hash is unmapped. No `CNContactStore` in the extension.
- **Apple side, no UI.** Enable App Groups on the app's App ID, register the
  extension's bundle id with App Groups, create its `IOS_APP_STORE` profile,
  regenerate the app's profile (capability change), and add a second profile
  secret for `testflight.yaml`. Release signing for the extension goes in
  `project.yml` under the extension target's Release config only, same rule
  as the app.
- Umami: nothing. The extension has no network and should not.

**Decisions.**
- Whether the **emoji** rides along. The server already has it (the trigger
  fires on `checkins`); sending it means *"Anna 🙂 just checked in"* on the
  lock screen. This is the one place a mood would be visible without opening
  the app and without the check-in gate. Recommend no for the first version:
  the name alone fixes the muting problem, and the gate is the product.
- `thread-id` per sender versus one thread. Per sender groups a chatty friend
  in Notification Center; keep one thread until that is an actual complaint.

## 7. Widget, control, Siri — L

**Problem.** A one-tap app still needs to be found and opened. The natural
place for the tap is the home screen and the lock screen.

**Approach.**
- **`CheckInIntent: AppIntent`** with an emoji parameter. Everything else
  hangs off it.
- **Shared session.** The extension has to talk to Supabase as the user.
  `SupabaseClient` accepts a custom `AuthLocalStorage`; implement one over the
  Keychain with a shared access group (`keychain-access-groups` entitlement
  on app and extension, plus the App Group for `UserDefaults`). This is the
  hard part and the reason the item is L.
- **Home-screen widget (medium).** Today's five moods plus the wildcard as
  interactive buttons; picking one runs the intent, which saves through the
  same repository and reloads the timeline. Reuse the item 4 queue: an
  intent that fails offline enqueues, and the app drains it.
- **Reminder cancellation.** The extension cannot cancel the app's local
  notification, so `HomeView.load()` calls `cancelToday()` whenever today's
  row already exists. That closes the gap from a widget check-in.
- **Lock-screen widget (accessory).** Your ring in today's color, or the
  neutral ring before you have checked in. Tapping opens the app.
- **Control Center control (iOS 18).** `ControlWidget` that opens the app on
  the picker, or runs the intent with the last-used mood.
- **Siri / Shortcuts.** `AppShortcutsProvider` with *"Log my mood in
  Howday"*; the emoji is a parameter Siri asks for.
- **Friends' rings on the widget** is a second phase: the board needs names
  and photos, which means the name map from item 6 and a thumbnail cache in
  the group container, plus a `board_today` call from the extension.
  Ship the picker first.
- Apple side: same App Group as item 6, a widget-extension bundle id and
  profile, a third CI profile secret.
- Umami: `checkin_saved` with a `source: widget` field, so the app and the
  widget stay distinguishable without a new event.

**Decisions.**
- Whether the widget check-in should be allowed to *change* an existing mood
  or only make the first one. Recommend both, matching the app.
- Timeline refresh budget: WidgetKit allows a few dozen reloads a day.
  Reload on the user's own check-in and on app foreground only; friends'
  changes wait for the second phase and its own reload policy.

---

## Suggested sequence

1. **Patch releases, any order:** 5 (tests), 4 (offline queue), 1 (Dynamic
   Type).
2. **One minor release:** 2 (invite) + 3 (limited contacts), the two
   user-visible small items, so they share one Beta App Review.
3. **One minor release:** 6 (named pushes). Does the App Group and CI
   profile work that 7 reuses.
4. **One minor release:** 7 (widget picker, lock screen, control, Siri);
   friends' rings on the widget as a follow-up.
