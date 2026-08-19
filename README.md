# Moodring

One mood check-in a day; see how your friends are doing. iOS (SwiftUI, iOS 17+)
with a Supabase backend and phone-number sign-in via Twilio Verify.

Build plan: https://claude.ai/code/artifact/f44b4ae4-1753-49e6-8f0d-9f18084be5fe

## Repo layout

- `project.yml` — XcodeGen definition; the `.xcodeproj` is generated, not committed
- `App/Sources/` — SwiftUI app, one folder per feature (Auth, CheckIn, Board, Friends, History, Core)
- `Config/Secrets.xcconfig` — Supabase URL + anon key (gitignored; copy from `Secrets.example.xcconfig`)
- `supabase/migrations/` — schema + RLS, applied with the Supabase CLI
- `supabase/functions/match-contacts/` — Edge Function for hashed contact matching (deployed in M2)

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
- **`profiles.phone_hash`** is revoked from client roles at the column level;
  only the service-role Edge Function reads it.
- Privacy lives in RLS, not in the app: friends with `accepted` status can
  read your check-ins, nobody else.
