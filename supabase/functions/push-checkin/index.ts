// Sends "a friend just checked in" APNs pushes to a check-in author's mutual
// contacts. Invoked by the on_checkin_insert_push DB trigger via pg_net, not
// by clients: verify_jwt is off (config.toml), and the x-push-secret header
// (PUSH_FN_SECRET, mirrored in Vault for the trigger) is the only gate.
// The server stores no names, so the alert text is deliberately generic.
import { createClient } from "npm:@supabase/supabase-js@2";

const APNS_HOST = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
} as const;

// Apple wants provider JWTs reused for 20-60 minutes; cache per instance.
let cached: { jwt: string; issuedAt: number } | null = null;

async function apnsJwt(): Promise<string> {
  if (cached && Date.now() - cached.issuedAt < 45 * 60_000) {
    return cached.jwt;
  }
  const pem = Deno.env.get("APNS_AUTH_KEY")!;
  const der = Uint8Array.from(
    atob(pem.replace(/-----[^-]+-----|\s/g, "")),
    (c) => c.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const b64url = (bytes: Uint8Array) =>
    btoa(String.fromCharCode(...bytes))
      .replaceAll("+", "-")
      .replaceAll("/", "_")
      .replace(/=+$/, "");
  const part = (obj: unknown) =>
    b64url(new TextEncoder().encode(JSON.stringify(obj)));
  const unsigned = `${
    part({ alg: "ES256", kid: Deno.env.get("APNS_KEY_ID") })
  }.${
    part({
      iss: Deno.env.get("APNS_TEAM_ID"),
      iat: Math.floor(Date.now() / 1000),
    })
  }`;
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(unsigned),
  );
  cached = {
    jwt: `${unsigned}.${b64url(new Uint8Array(sig))}`,
    issuedAt: Date.now(),
  };
  return cached.jwt;
}

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
  try {
    ({ user_id: userId } = await req.json());
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  if (typeof userId !== "string") {
    return json({ error: "user_id required" }, 400);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data: recipients, error } = await admin.rpc(
    "checkin_push_recipients",
    { author: userId },
  );
  if (error) {
    return json({ error: error.message }, 500);
  }
  if (!recipients || recipients.length === 0) {
    return json({ sent: 0, of: 0 });
  }

  const jwt = await apnsJwt();
  const bundleId = Deno.env.get("APNS_BUNDLE_ID") ?? "dev.winktech.moodring";
  const results = await Promise.all(
    recipients.map(
      async ({ token, sandbox }: { token: string; sandbox: boolean }) => {
        const host = sandbox ? APNS_HOST.sandbox : APNS_HOST.production;
        const res = await fetch(`${host}/3/device/${token}`, {
          method: "POST",
          headers: {
            authorization: `bearer ${jwt}`,
            "apns-topic": bundleId,
            "apns-push-type": "alert",
            "apns-priority": "10",
          },
          body: JSON.stringify({
            aps: {
              alert: { body: "A friend just checked in 💫" },
              sound: "default",
              "thread-id": "friend-checkins",
            },
          }),
        });
        if (res.ok) {
          return true;
        }
        const { reason } = await res.json().catch(() => ({ reason: "" }));
        // Dead tokens (app deleted, token expired, wrong environment):
        // drop the row so we stop pushing at them.
        if (
          res.status === 410 || reason === "BadDeviceToken" ||
          reason === "DeviceTokenNotForTopic"
        ) {
          await admin.from("device_tokens").delete().eq("token", token);
        }
        return false;
      },
    ),
  );
  return json({ sent: results.filter(Boolean).length, of: results.length });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
