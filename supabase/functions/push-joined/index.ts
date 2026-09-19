// Sends "someone in your contacts just joined Howday" to one recipient when a
// newly registered contact becomes mutual with them. Invoked by the
// on_contact_link_announce_join DB trigger via pg_net, not by clients:
// verify_jwt is off (config.toml) and the x-push-secret header is the only
// gate. The server stores no names, so the alert text is deliberately
// generic — the board is where the newcomer gets a face and a first name,
// resolved from the viewer's own address book.
import { createClient } from "npm:@supabase/supabase-js@2";
import { type Recipient, sendAlerts } from "../_shared/apns.ts";

const ALERT_BODY = "Someone in your contacts just joined Howday 👋";

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

  let recipientId: unknown;
  let newUserId: unknown;
  try {
    ({ recipient_id: recipientId, new_user_id: newUserId } = await req.json());
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  if (typeof recipientId !== "string" || typeof newUserId !== "string") {
    return json({ error: "recipient_id and new_user_id required" }, 400);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  // Re-checks mutuality server-side rather than trusting the caller: a
  // one-way link must not even reveal that somebody joined.
  const { data: recipients, error } = await admin.rpc("join_push_recipients", {
    recipient: recipientId,
    newcomer: newUserId,
  });
  if (error) {
    return json({ error: error.message }, 500);
  }

  return json(
    await sendAlerts(admin, (recipients ?? []) as Recipient[], {
      body: ALERT_BODY,
      threadId: "friend-joins",
    }),
  );
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
