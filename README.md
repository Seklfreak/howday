# Moodring

One mood check-in a day; see how your friends are doing. You can't see your
friends' moods until you've shared yours. Friends are contacts-based — no
friend requests, no profiles to fill in: you see each other once you're both
in each other's address books, shown with the name and photo from your own
contacts. iOS (SwiftUI, iOS 17+) with a Supabase backend and phone-number
sign-in via Twilio Verify.

Source-visible, all rights reserved — no license is granted for reuse or
redistribution.

## Repo layout

- `project.yml` — XcodeGen definition; the `.xcodeproj` is generated, not committed
- `App/Sources/` — SwiftUI app, one folder per feature (Auth, CheckIn, Board, History, Core)
- `Config/Secrets.xcconfig` — Supabase URL + anon key (gitignored; copy from `Secrets.example.xcconfig`)
- `supabase/migrations/` — schema + RLS, applied with the Supabase CLI
- `supabase/functions/sync-contacts/` — Edge Function that turns hashed contact uploads into `contact_links`

## One-time setup

1. **Supabase project** — create one at https://supabase.com/dashboard (free tier).
   Then link and push the schema:
   ```sh
   supabase login
   supabase link --project-ref <PROJECT_REF>
   supabase db push
   ```
2. **Twilio Verify** — create a Twilio account, then a Verify service
   (Console → Verify → Services). Note the Account SID, Auth Token, and
   Verify service SID.
3. **Wire Twilio into Supabase** — Dashboard → Authentication → Sign In /
   Providers → Phone: enable, provider = Twilio Verify, paste the three values.
   For free dev iterations add a test phone number with a fixed OTP under
   Authentication → Phone → Test OTPs.
4. **App secrets** — `cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig`
   and fill in the project URL + anon key (Dashboard → Project Settings → API).
5. **Push notifications** (friend check-ins) — optional; without this setup
   check-ins still work, the notify trigger just no-ops.
   1. Apple Developer portal: enable the **Push Notifications** capability on
      the App ID, then regenerate the App Store provisioning profile (and
      update the `APP_STORE_PROFILE` CI secret — archives fail signing against
      the old profile once the entitlement is in the app). Create an **APNs
      auth key** (Certificates → Keys → Apple Push Notifications service),
      download the `.p8`, note the Key ID.
   2. Edge Function secrets:
      ```sh
      supabase secrets set \
        APNS_AUTH_KEY="$(cat AuthKey_XXXXXXXXXX.p8)" \
        APNS_KEY_ID=<key id> APNS_TEAM_ID=<team id> \
        PUSH_FN_SECRET=$(openssl rand -hex 32)
      supabase functions deploy push-checkin
      ```
   3. Tell the DB trigger where to call (SQL editor; Vault keeps the project
      ref and secret out of this public repo):
      ```sql
      select vault.create_secret('https://<PROJECT_REF>.supabase.co', 'project_url');
      select vault.create_secret('<the same PUSH_FN_SECRET value>', 'push_fn_secret');
      ```

## Build & run

```sh
xcodegen generate   # after cloning or editing project.yml
open MoodRing.xcodeproj
```

Or from the CLI:
```sh
xcodebuild -project MoodRing.xcodeproj -scheme MoodRing \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## Conventions worth knowing

- **Phone hash format**: Supabase stores `auth.users.phone` as E.164 *without*
  the leading `+`. The signup trigger hashes that form; client-side contact
  matching must hash the identical form (`PhoneNumber.hashForMatching`).
- **`checkins.day`** is the user's *local* date, computed client-side; the
  `unique (user_id, day)` constraint enforces one check-in per day.
- **Friend-check-in pushes** notify only *mutual* contacts, and the alert text
  is generic — the server stores no names to put in it. Changing today's mood
  notifies too, but pushes are rate limited to one per author per 30 minutes
  so that re-tapping emoji can't spam anyone; a new day's check-in always
  goes out regardless of the cooldown.
- **`profiles.phone_hash`** is revoked from client roles at the column level;
  only the service-role Edge Function reads it.
- Privacy lives in RLS, not in the app: your check-ins are readable only by
  *mutual* contacts — the hashed-contact sync must have linked you both ways.
  A one-way link (someone merely has your number) grants nothing. Names and
  photos are never uploaded; each viewer renders friends from their own
  address book. `scripts/rls-proof.sh` asserts every policy boundary against
  a live project — it needs `MOODRING_URL`, `MOODRING_KEY`,
  `TEST_PHONE_A/B`, and `TEST_OTP` in the environment (configure test
  numbers under Authentication → Phone → Test OTPs).

## CI

`.github/workflows/test.yaml` compile-checks every push/PR. A green `main`
auto-cuts a versioned release (`release.yaml`, Seklfreak/ai-release-action
proposes the semver bump), and the version tag triggers `testflight.yaml`,
which archives with a stored distribution certificate and uploads to
TestFlight — dormant until the App Store Connect secrets listed in that file
exist. `testflight-refresh.yaml` runs monthly and re-uploads the latest
released tag when the newest TestFlight build is older than ~30 days, so the
build never hits TestFlight's 90-day expiry during quiet stretches.
