// APNs plumbing shared by the push-* functions: provider JWT minting and a
// fan-out send with dead-token cleanup. Both callers are invoked by DB
// triggers through pg_net, never by clients — verify_jwt is off for them and
// the x-push-secret header is the only gate.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

const APNS_HOST = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
} as const;

export interface Recipient {
  token: string;
  sandbox: boolean;
}

// Apple wants provider JWTs reused for 20-60 minutes; cache per instance.
let cached: { jwt: string; issuedAt: number } | null = null;

export async function apnsJwt(): Promise<string> {
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

/// Send one alert to every recipient device. Returns how many APNs accepted.
export async function sendAlerts(
  admin: SupabaseClient,
  recipients: Recipient[],
  alert: {
    body: string;
    threadId: string;
    // Top-level custom keys for the app's Notification Service Extension,
    // which rewrites the generic body into a named one on the device
    // (the server never knows a name). Their presence sets
    // mutable-content, which is what makes iOS run the extension at all.
    payload?: Record<string, string>;
  },
): Promise<{ sent: number; of: number }> {
  if (recipients.length === 0) {
    return { sent: 0, of: 0 };
  }
  const jwt = await apnsJwt();
  const bundleId = Deno.env.get("APNS_BUNDLE_ID") ?? "dev.winktech.moodring";
  const results = await Promise.all(
    recipients.map(async ({ token, sandbox }: Recipient) => {
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
            alert: { body: alert.body },
            sound: "default",
            "thread-id": alert.threadId,
            ...(alert.payload ? { "mutable-content": 1 } : {}),
          },
          ...alert.payload,
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
    }),
  );
  return { sent: results.filter(Boolean).length, of: results.length };
}
