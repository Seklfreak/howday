// Contact matching (M2): receives SHA-256 hashes of the caller's contacts'
// phone numbers (E.164 WITHOUT leading +, hashed on-device) and returns the
// profiles already registered. Match-and-discard: nothing is stored.
import { createClient } from "npm:@supabase/supabase-js@2";

const MAX_HASHES = 5000;

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "POST only" }, 405);
  }

  let hashes: unknown;
  try {
    ({ hashes } = await req.json());
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  if (
    !Array.isArray(hashes) ||
    hashes.length === 0 ||
    hashes.length > MAX_HASHES ||
    !hashes.every((h) => typeof h === "string" && /^[0-9a-f]{64}$/.test(h))
  ) {
    return json({ error: `hashes must be 1-${MAX_HASHES} sha256 hex strings` }, 400);
  }

  // Identify the caller from their JWT (verify_jwt is on, but we also need
  // the user id to exclude them from their own results).
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const userClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) {
    return json({ error: "unauthorized" }, 401);
  }

  // Service role: the phone_hash column is revoked from client roles.
  const admin = createClient(supabaseUrl, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data, error } = await admin
    .from("profiles")
    .select("id, display_name, phone_hash")
    .in("phone_hash", hashes)
    .neq("id", user.id);
  if (error) {
    return json({ error: error.message }, 500);
  }

  // phone_hash is echoed back so the client can map matches onto the local
  // contact (it already knows these hashes — no new information leaks).
  return json({ matches: data });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
