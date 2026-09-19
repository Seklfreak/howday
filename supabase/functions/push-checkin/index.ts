// Sends "a friend just checked in" APNs pushes to a check-in author's mutual
// contacts. Invoked by the on_checkin_push DB trigger via pg_net, not by
// clients: verify_jwt is off (config.toml), and the x-push-secret header
// (PUSH_FN_SECRET, mirrored in Vault for the trigger) is the only gate.
// The server stores no names, so the alert text is deliberately generic;
// the author's phone hash rides along so the recipient's device can put a
// name to it from its own address book. Safe to send: every recipient is a
// mutual contact, so that number is by definition already in their book.
import { createClient } from "npm:@supabase/supabase-js@2";
import { type Recipient, sendAlerts } from "../_shared/apns.ts";

// The trigger fires for a new check-in and for a mood changed later the same
// day; only the wording differs. Unknown values fall back to the new-check-in
// body rather than dropping the push.
const ALERT_BODY = {
  new: "A friend just checked in 💫",
  update: "A friend changed their mood 💫",
} as const;

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "POST only" }, 405);
  }
  const secret = Deno.env.get("PUSH_FN_SECRET");
  if (!secret || req.headers.get("x-push-secret") !== secret) {
    return json({ error: "unauthorized" }, 401);
  }
  if (!Deno.env.get("APNS_AUTH_KEY")) {
    return json({ error: "APNs secrets not configured" }, 500);
  }

  let userId: unknown;
  let kind: unknown;
  try {
    ({ user_id: userId, kind } = await req.json());
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  if (typeof userId !== "string") {
    return json({ error: "user_id required" }, 400);
  }
  const alertBody = kind === "update" ? ALERT_BODY.update : ALERT_BODY.new;

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const [{ data: recipients, error }, { data: author }] = await Promise.all([
    admin.rpc("checkin_push_recipients", { author: userId }),
    admin.from("profiles").select("phone_hash").eq("id", userId).maybeSingle(),
  ]);
  if (error) {
    return json({ error: error.message }, 500);
  }

  return json(
    await sendAlerts(admin, (recipients ?? []) as Recipient[], {
      body: alertBody,
      threadId: "friend-checkins",
      payload: {
        kind: kind === "update" ? "update" : "new",
        ...(author?.phone_hash ? { sender_hash: author.phone_hash } : {}),
      },
    }),
  );
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
