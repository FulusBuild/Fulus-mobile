import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const url = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const db = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
const out = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

Deno.serve(async req => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "authorization, content-type, x-fulus-device-id", "access-control-allow-methods": "POST, OPTIONS" } });
  if (req.method !== "POST") return out({ error: { code: "METHOD_NOT_ALLOWED", message: "POST required" } }, 405);
  const auth = req.headers.get("authorization");
  if (!auth?.startsWith("Bearer ")) return out({ error: { code: "UNAUTHENTICATED", message: "Bearer token required" } }, 401);
  const { data: ud, error: ue } = await db.auth.getUser(auth.slice(7).trim());
  if (ue || !ud.user) return out({ error: { code: "UNAUTHENTICATED", message: "Invalid access token" } }, 401);
  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return out({ error: { code: "INVALID_JSON", message: "Request body must be valid JSON" } }, 400); }
  const event = body.event && typeof body.event === "object" ? body.event as Record<string, unknown> : null;
  if (!event || typeof event.id !== "string" || typeof event.title !== "string" || typeof event.message !== "string") return out({ error: { code: "INVALID_DIAGNOSTIC_EVENT", message: "A structured diagnostic event is required" } }, 400);
  const deviceClientId = req.headers.get("x-fulus-device-id") ?? (typeof body.device_client_id === "string" ? body.device_client_id : null);
  const businessId = typeof body.business_id === "string" ? body.business_id : null;
  if (businessId) {
    const { data: member, error: me } = await db.from("business_memberships").select("business_id").eq("business_id", businessId).eq("user_id", ud.user.id).eq("status", "active").maybeSingle();
    if (me) return out({ error: { code: "MEMBERSHIP_LOOKUP_FAILED", message: "Unable to verify business" } }, 500);
    if (!member) return out({ error: { code: "FORBIDDEN", message: "User is not an active member of this business" } }, 403);
  }
  const allowedSeverity = new Set(["info", "warning", "error", "critical"]);
  const severity = typeof event.severity === "string" && allowedSeverity.has(event.severity) ? event.severity : "error";
  const payload = JSON.parse(JSON.stringify(event));
  if (typeof payload.stackTrace === "string" && payload.stackTrace.length > 8000) payload.stackTrace = payload.stackTrace.slice(0, 8000) + "\n... [remote truncation]";
  const row = {
    id: event.id,
    user_id: ud.user.id,
    business_id: businessId,
    device_client_id: deviceClientId,
    severity,
    category: typeof event.category === "string" ? event.category : "unknown",
    title: event.title.slice(0, 200),
    message: event.message.slice(0, 500),
    component: typeof event.component === "string" ? event.component.slice(0, 200) : null,
    operation: typeof event.operation === "string" ? event.operation.slice(0, 200) : null,
    screen: typeof event.screen === "string" ? event.screen.slice(0, 200) : null,
    exception_type: typeof event.exceptionType === "string" ? event.exceptionType.slice(0, 200) : null,
    error_code: typeof event.errorCode === "string" ? event.errorCode.slice(0, 100) : null,
    failure_stage: typeof event.failureStage === "string" ? event.failureStage.slice(0, 200) : null,
    occurrence_count: typeof event.occurrenceCount === "number" ? Math.max(1, Math.min(1000000, Math.trunc(event.occurrenceCount))) : 1,
    event_timestamp: typeof event.timestamp === "string" ? event.timestamp : new Date().toISOString(),
    payload,
  };
  const { error } = await db.from("diagnostic_events").upsert(row, { onConflict: "id" });
  if (error) return out({ error: { code: "DIAGNOSTIC_WRITE_FAILED", message: "Unable to store diagnostic event" } }, 500);
  return out({ data: { accepted: true, id: event.id } }, 202);
});
