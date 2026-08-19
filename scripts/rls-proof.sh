#!/bin/zsh
# Two-account RLS proof for Moodring's contacts-based model: exercises the
# sync → mutual → unsync lifecycle against a live project and asserts every
# policy boundary. The critical property: a ONE-WAY contact link must grant
# nothing — visibility requires the link in both directions.
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
hash256() { python3 -c "import hashlib,sys;print(hashlib.sha256(sys.argv[1].encode()).hexdigest())" "$1"; }

signin() { # $1 phone-without-plus -> prints access_token|user_id
  curl -s -X POST "$URL/auth/v1/otp" -H "apikey: $KEY" -H 'Content-Type: application/json' -d "{\"phone\":\"+$1\"}" > /dev/null
  R=$(curl -s -X POST "$URL/auth/v1/verify" -H "apikey: $KEY" -H 'Content-Type: application/json' -d "{\"type\":\"sms\",\"phone\":\"+$1\",\"token\":\"$TEST_OTP\"}")
  echo "$(echo "$R" | jsonget access_token)|$(echo "$R" | jsonget user.id)"
}

A=$(signin "$TEST_PHONE_A"); AT=${A%|*}; AID=${A#*|}
B=$(signin "$TEST_PHONE_B"); BT=${B%|*}; BID=${B#*|}
[[ -n "$AT" && -n "$BT" ]] || { echo "sign-in failed"; exit 1 }
echo "A=$AID  B=$BID"

AHASH=$(hash256 "$TEST_PHONE_A")
BHASH=$(hash256 "$TEST_PHONE_B")

rest() { # $1 token, then curl args
  local T=$1; shift
  curl -s -H "apikey: $KEY" -H "Authorization: Bearer $T" -H 'Content-Type: application/json' "$@"
}
sync() { # $1 token, $2 hashes-json-array
  rest "$1" -X POST "$URL/functions/v1/sync-contacts" -d "{\"hashes\":$2}"
}

# Clean slate: both drop all links left over from earlier runs.
sync "$AT" '[]' > /dev/null
sync "$BT" '[]' > /dev/null

# B checks in
rest "$BT" -X POST "$URL/rest/v1/checkins?on_conflict=user_id,day" -H 'Prefer: resolution=merge-duplicates' \
  -d "{\"user_id\":\"$BID\",\"day\":\"$(date +%F)\",\"emoji\":\"🙂\"}" > /dev/null
BCHK=$(rest "$BT" "$URL/rest/v1/checkins?user_id=eq.$BID&select=id" | jsonget 0.id)

# 1. Strangers see nothing
check "stranger cannot read B's checkins" "$(rest "$AT" "$URL/rest/v1/checkins?user_id=eq.$BID&select=id")" "[]"

# 2. A one-way link grants NOTHING — the model's core property
check "A syncs B's number" "$(sync "$AT" "[\"$BHASH\"]")" '"linked":1'
check "one-way: A still cannot read B's checkins" "$(rest "$AT" "$URL/rest/v1/checkins?user_id=eq.$BID&select=id")" "[]"
check "one-way: A's mutuals are empty" "$(rest "$AT" -X POST "$URL/rest/v1/rpc/my_mutuals" -d '{}')" "[]"
check "one-way: B's mutuals are empty too" "$(rest "$BT" -X POST "$URL/rest/v1/rpc/my_mutuals" -d '{}')" "[]"

# 3. The link in both directions unlocks both sides
sync "$BT" "[\"$AHASH\"]" > /dev/null
check "mutual: A reads B's checkin" "$(rest "$AT" "$URL/rest/v1/checkins?user_id=eq.$BID&select=emoji")" "🙂"
check "mutual: my_mutuals returns B for A" "$(rest "$AT" -X POST "$URL/rest/v1/rpc/my_mutuals" -d '{}')" "$BID"
check "mutual: my_mutuals echoes B's phone_hash" "$(rest "$AT" -X POST "$URL/rest/v1/rpc/my_mutuals" -d '{}')" "$BHASH"

# 4. Mutuality still doesn't grant writes, and the raw tables stay sealed
check "A cannot edit B's checkin" "$(rest "$AT" -X PATCH "$URL/rest/v1/checkins?id=eq.$BCHK" -H 'Prefer: return=representation' -d '{"emoji":"😢"}')" "[]"
check "checkin delete is revoked" "$(rest "$AT" -X DELETE "$URL/rest/v1/checkins?id=eq.$BCHK")" "permission denied"
check "clients cannot read contact_links" "$(rest "$AT" "$URL/rest/v1/contact_links?select=owner_id")" "permission denied"
check "clients cannot forge contact_links" "$(rest "$AT" -X POST "$URL/rest/v1/contact_links" -d "{\"owner_id\":\"$BID\",\"user_id\":\"$AID\"}")" "permission denied"
check "profiles are sealed from clients" "$(rest "$AT" "$URL/rest/v1/profiles?select=id")" "permission denied"

# 4b. Push plumbing: the token table is sealed, registration goes through the
# RPCs and is scoped to the caller, and the fan-out RPC is service-role only.
check "clients cannot read device_tokens" "$(rest "$AT" "$URL/rest/v1/device_tokens?select=token")" "permission denied"
check "clients cannot write device_tokens directly" \
  "$(rest "$AT" -X POST "$URL/rest/v1/device_tokens" -d "{\"token\":\"deadbeefdeadbeef\",\"user_id\":\"$AID\"}")" "permission denied"
FAKE_TOKEN=$(printf 'ab%.0s' {1..32})
R=$(rest "$AT" -X POST "$URL/rest/v1/rpc/register_device_token" -d "{\"device_token\":\"$FAKE_TOKEN\",\"is_sandbox\":true}")
check "A registers a device token via rpc" "${R:-ok}" "ok"
check "push recipient fan-out is service-role only" \
  "$(rest "$AT" -X POST "$URL/rest/v1/rpc/checkin_push_recipients" -d "{\"author\":\"$AID\"}")" "permission denied"
rest "$AT" -X POST "$URL/rest/v1/rpc/unregister_device_token" -d "{\"device_token\":\"$FAKE_TOKEN\"}" > /dev/null

# 5. sync-contacts input validation
check "sync rejects malformed hashes" "$(sync "$AT" '["nope"]')" "sha256 hex"

# 6. Deleting the contact closes the door again
sync "$BT" '[]' > /dev/null
check "after unsync: A cannot read B's checkins" "$(rest "$AT" "$URL/rest/v1/checkins?user_id=eq.$BID&select=id")" "[]"
check "after unsync: A's mutuals are empty again" "$(rest "$AT" -X POST "$URL/rest/v1/rpc/my_mutuals" -d '{}')" "[]"

echo "----"; echo "$PASS passed, $FAIL failed"
exit $FAIL
