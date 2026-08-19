#!/bin/zsh
# Two-account RLS proof for Moodring: exercises the full friendship
# lifecycle against a live project and asserts every policy boundary.
#
# Required environment:
#   MOODRING_URL     — project URL, e.g. https://<ref>.supabase.co
#   MOODRING_KEY     — publishable (anon) API key
#   TEST_PHONE_A     — first test phone number, digits only (e.g. 15005550001)
#   TEST_PHONE_B     — second test phone number, digits only
#   TEST_OTP         — the fixed OTP configured for both test numbers
#     (Supabase dashboard: Authentication -> Phone -> Test OTPs)
for v in MOODRING_URL MOODRING_KEY TEST_PHONE_A TEST_PHONE_B TEST_OTP; do
  [[ -n "${(P)v}" ]] || { echo "missing env: $v"; exit 2 }
done
URL=$MOODRING_URL
KEY=$MOODRING_KEY
PASS=0; FAIL=0
check() { # $1 label, $2 actual, $3 expected-substring-or-exact
  if [[ "$2" == *"$3"* ]]; then echo "PASS: $1"; ((PASS++));
  else echo "FAIL: $1 — got: ${2:0:160}"; ((FAIL++)); fi
}
jsonget() { python3 -c "import json,sys
try: d=json.load(sys.stdin)
except Exception: print(''); sys.exit()
for k in sys.argv[1].split('.'):
  d = d[int(k)] if isinstance(d, list) else d.get(k, {})
print(d if isinstance(d,str) else json.dumps(d))" "$1"; }

signin() { # $1 phone-without-plus -> prints access_token|user_id
  curl -s -X POST "$URL/auth/v1/otp" -H "apikey: $KEY" -H 'Content-Type: application/json' -d "{\"phone\":\"+$1\"}" > /dev/null
  R=$(curl -s -X POST "$URL/auth/v1/verify" -H "apikey: $KEY" -H 'Content-Type: application/json' -d "{\"type\":\"sms\",\"phone\":\"+$1\",\"token\":\"$TEST_OTP\"}")
  echo "$(echo "$R" | jsonget access_token)|$(echo "$R" | jsonget user.id)"
}

A=$(signin "$TEST_PHONE_A"); AT=${A%|*}; AID=${A#*|}
B=$(signin "$TEST_PHONE_B"); BT=${B%|*}; BID=${B#*|}
[[ -n "$AT" && -n "$BT" ]] || { echo "sign-in failed"; exit 1 }
echo "A=$AID  B=$BID"

rest() { # $1 token, then curl args
  local T=$1; shift
  curl -s -H "apikey: $KEY" -H "Authorization: Bearer $T" -H 'Content-Type: application/json' "$@"
}

# Clean slate: drop any A-B relationship left over from earlier runs.
rest "$AT" -X DELETE "$URL/rest/v1/friendships?or=(requester.eq.$AID,addressee.eq.$AID)" > /dev/null

# B sets a display name (returning minimal)
rest "$BT" -X PATCH "$URL/rest/v1/profiles?id=eq.$BID" -d '{"display_name":"Bob Test"}' > /dev/null
# B checks in
rest "$BT" -X POST "$URL/rest/v1/checkins?on_conflict=user_id,day" -H 'Prefer: resolution=merge-duplicates' \
  -d "{\"user_id\":\"$BID\",\"day\":\"$(date +%F)\",\"emoji\":\"🙂\",\"note\":\"secret note\"}" > /dev/null
BCHK=$(rest "$BT" "$URL/rest/v1/checkins?user_id=eq.$BID&select=id,emoji,note" | jsonget 0.id)

# 1. Strangers can't see each other
check "stranger cannot read B's profile" "$(rest "$AT" "$URL/rest/v1/profiles?id=eq.$BID&select=id")" "[]"
check "stranger cannot read B's checkins" "$(rest "$AT" "$URL/rest/v1/checkins?user_id=eq.$BID&select=id")" "[]"

# 2. Contact matching finds B for A (Edge Function, service role)
BHASH=$(python3 -c "import hashlib,os;print(hashlib.sha256(os.environ['TEST_PHONE_B'].encode()).hexdigest())")
MATCH=$(rest "$AT" -X POST "$URL/functions/v1/match-contacts" -d "{\"hashes\":[\"$BHASH\"]}")
check "match-contacts returns B" "$MATCH" "$BID"
check "match-contacts returns B's name" "$MATCH" "Bob Test"

# 3. A cannot forge a request FROM B
check "cannot insert friendship as someone else" \
  "$(rest "$AT" -X POST "$URL/rest/v1/friendships" -d "{\"requester\":\"$BID\",\"addressee\":\"$AID\",\"status\":\"pending\"}")" "violates row-level security"

# 4. A requests B properly
FID=$(rest "$AT" -X POST "$URL/rest/v1/friendships" -H 'Prefer: return=representation' \
  -d "{\"requester\":\"$AID\",\"addressee\":\"$BID\",\"status\":\"pending\"}" | jsonget 0.id)
check "request created" "$FID" "-"

# 5. Requester cannot self-accept
SELF=$(rest "$AT" -X PATCH "$URL/rest/v1/friendships?id=eq.$FID" -H 'Prefer: return=representation' -d '{"status":"accepted"}')
check "requester cannot accept own request" "$SELF" "[]"

# 6. Pending: A can now see B's profile (to show the name) but still no checkins
check "pending: A sees B's name" "$(rest "$AT" "$URL/rest/v1/profiles?id=eq.$BID&select=display_name")" "Bob Test"
check "pending: still no checkins" "$(rest "$AT" "$URL/rest/v1/checkins?user_id=eq.$BID&select=id")" "[]"

# 7. Addressee accepts
rest "$BT" -X PATCH "$URL/rest/v1/friendships?id=eq.$FID" -d '{"status":"accepted"}' > /dev/null
check "accepted: A reads B's checkin" "$(rest "$AT" "$URL/rest/v1/checkins?user_id=eq.$BID&select=note")" "secret note"

# 8. Friends still can't write each other's data
check "A cannot edit B's checkin" "$(rest "$AT" -X PATCH "$URL/rest/v1/checkins?id=eq.$BCHK" -H 'Prefer: return=representation' -d '{"emoji":"😢"}')" "[]"
check "checkin delete is revoked" "$(rest "$AT" -X DELETE "$URL/rest/v1/checkins?id=eq.$BCHK")" "permission denied"
check "phone_hash stays hidden even from friends" "$(rest "$AT" "$URL/rest/v1/profiles?id=eq.$BID&select=phone_hash")" "permission denied"

# 9. Unfriend closes the door again
rest "$AT" -X DELETE "$URL/rest/v1/friendships?id=eq.$FID" > /dev/null
check "after unfriend: checkins hidden again" "$(rest "$AT" "$URL/rest/v1/checkins?user_id=eq.$BID&select=id")" "[]"

echo "----"; echo "$PASS passed, $FAIL failed"
exit $FAIL
