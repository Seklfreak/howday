// Contact sync: receives SHA-256 hashes of the caller's contacts' phone
// numbers (E.164 WITHOUT leading +, hashed on-device) and replaces the
// caller's contact_links rows with the registered users among them. Only
// hashes travel — names and photos never leave the device. Mutual links
// (both people in each other's contacts) are what unlock check-in
// visibility; see the contacts_based_friends migration.
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
    hashes.length > MAX_HASHES ||
    !hashes.every((h) => typeof h === "string" && /^[0-9a-f]{64}$/.test(h))
  ) {
    return json(
      { error: `hashes must be 0-${MAX_HASHES} sha256 hex strings` },
      400,
    );
  }

  // Identify the caller from their JWT (verify_jwt is on, but we also need
  // the user id to write their links).
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const userClient = createClient(
    supabaseUrl,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      global: {
        headers: { Authorization: req.headers.get("Authorization") ?? "" },
      },
    },
  );
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) {
    return json({ error: "unauthorized" }, 401);
  }

  // Service role: phone_hash and contact_links are revoked from client
  // roles. rpc() sends the hash array in the request body — .in() would put
  // it in the URL, which breaks past ~1000 hashes.
  const admin = createClient(
    supabaseUrl,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data: rows, error } = hashes.length > 0
    ? await admin.rpc("match_phone_hashes", { hashes })
    : { data: [], error: null };
  if (error) {
    return json({ error: error.message }, 500);
  }
  const ids = rows
    .filter((r: { id: string }) => r.id !== user.id)
    .map((r: { id: string }) => r.id);

  // Replace, don't merge: deleting someone from your contacts must delete
  // the link too — that is how mutuality (and their view of you) ends.
  // One RPC, not delete-then-insert from here: concurrent invocations
  // (board load + foreground re-sync firing together) interleaved the two
  // statements and the loser 500'd on the primary key. The DB function is
  // transactional and serialized per owner via an advisory lock.
  const { data: linked, error: replaceError } = await admin.rpc(
    "replace_contact_links",
    { owner: user.id, ids },
  );
  if (replaceError) {
    return json({ error: replaceError.message }, 500);
  }
  return json({ linked });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
