import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      "access-control-allow-origin": "*",
      "access-control-allow-headers": "authorization, content-type",
      "access-control-allow-methods": "POST, OPTIONS",
    },
  });

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "access-control-allow-origin": "*",
        "access-control-allow-headers": "authorization, content-type",
        "access-control-allow-methods": "POST, OPTIONS",
      },
    });
  }

  if (req.method !== "POST") {
    return json({ error: { code: "METHOD_NOT_ALLOWED", message: "POST required" } }, 405);
  }

  const authHeader = req.headers.get("authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return json({ error: { code: "UNAUTHENTICATED", message: "Bearer token required" } }, 401);
  }

  const token = authHeader.slice("Bearer ".length).trim();
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData.user) {
    return json({ error: { code: "UNAUTHENTICATED", message: "Invalid access token" } }, 401);
  }

  let raw: Record<string, unknown>;
  try {
    raw = await req.json();
  } catch {
    return json({ error: { code: "INVALID_JSON", message: "Request body must be valid JSON" } }, 400);
  }

  const name = typeof raw.name === "string" ? raw.name.trim() : "";
  if (name.length < 2) {
    return json({ error: { code: "INVALID_BUSINESS", message: "Business name must be at least 2 characters" } }, 400);
  }

  const { data, error } = await admin.rpc("create_business_for_user_service", {
    target_user_id: userData.user.id,
    target_name: name,
    target_currency_code: typeof raw.currency_code === "string" ? raw.currency_code : "NGN",
    target_timezone: typeof raw.timezone === "string" ? raw.timezone : "Africa/Lagos",
    target_location_name: typeof raw.location_name === "string" ? raw.location_name : "Main",
  });

  if (error) {
    return json(
      { error: { code: "BUSINESS_CREATION_FAILED", message: error.message } },
      error.code === "42501" ? 403 : 400,
    );
  }

  return json({ data: { ...data, server_authoritative: true } }, 201);
});
