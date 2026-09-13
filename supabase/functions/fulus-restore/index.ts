import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json" },
});

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: {
    "access-control-allow-origin": "*",
    "access-control-allow-headers": "authorization, content-type",
    "access-control-allow-methods": "POST, OPTIONS",
  }});
  if (req.method !== "POST") return json({ error: { code: "METHOD_NOT_ALLOWED" } }, 405);

  const authHeader = req.headers.get("authorization");
  if (!authHeader?.startsWith("Bearer ")) return json({ error: { code: "UNAUTHENTICATED", message: "Bearer token required" } }, 401);
  const token = authHeader.slice("Bearer ".length).trim();
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData.user) return json({ error: { code: "UNAUTHENTICATED", message: "Invalid access token" } }, 401);

  let body: { business_id?: string };
  try { body = await req.json(); } catch { return json({ error: { code: "INVALID_JSON" } }, 400); }
  const businessId = body.business_id;
  if (!businessId) return json({ error: { code: "BUSINESS_REQUIRED", message: "business_id is required" } }, 400);

  const { data, error } = await admin.rpc("build_fulus_restore_snapshot", {
    p_business_id: businessId,
    p_user_id: userData.user.id,
  });

  if (error) {
    const message = error.message ?? "Unable to build restore snapshot";
    if (message.includes("not an active member")) return json({ error: { code: "FORBIDDEN", message } }, 403);
    if (message.includes("Only a business owner")) return json({ error: { code: "RESTORE_NOT_ALLOWED", message } }, 403);
    if (message.includes("Business not found")) return json({ error: { code: "BUSINESS_NOT_FOUND", message } }, 404);
    return json({ error: { code: "RESTORE_SNAPSHOT_FAILED", message } }, 500);
  }

  return json({ data });
});
