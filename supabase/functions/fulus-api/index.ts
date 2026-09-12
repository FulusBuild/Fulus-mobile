import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "access-control-allow-origin": "*",
        "access-control-allow-headers": "authorization, content-type, x-fulus-device-id",
        "access-control-allow-methods": "GET, POST, OPTIONS",
      },
    });
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

  const userId = userData.user.id;
  const deviceClientId = req.headers.get("x-fulus-device-id");

  const { data: memberships, error: membershipError } = await admin
    .from("business_memberships")
    .select("business_id, role_id, status, joined_at")
    .eq("user_id", userId)
    .eq("status", "active");

  if (membershipError) {
    return json({ error: { code: "MEMBERSHIP_LOOKUP_FAILED", message: "Unable to resolve memberships" } }, 500);
  }

  if (req.method === "GET") {
    return json({
      data: {
        user_id: userId,
        memberships: memberships ?? [],
        device_client_id: deviceClientId,
        server_authoritative: true,
      },
    });
  }

  let body: { business_id?: string; operation_type?: string; operation_id?: string; client_reference?: string; payload?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: { code: "INVALID_JSON", message: "Request body must be valid JSON" } }, 400);
  }

  if (!body.business_id || !body.operation_type || !body.operation_id) {
    return json({
      error: {
        code: "INVALID_COMMAND",
        message: "business_id, operation_type and operation_id are required",
      },
    }, 400);
  }

  const membership = (memberships ?? []).find((m) => m.business_id === body.business_id);
  if (!membership) {
    return json({ error: { code: "FORBIDDEN", message: "User is not an active member of this business" } }, 403);
  }

  if (!deviceClientId) {
    return json({ error: { code: "DEVICE_REQUIRED", message: "x-fulus-device-id is required for commands" } }, 400);
  }

  const { data: device, error: deviceError } = await admin
    .from("devices")
    .select("id, status")
    .eq("business_id", body.business_id)
    .eq("device_client_id", deviceClientId)
    .maybeSingle();

  if (deviceError) {
    return json({ error: { code: "DEVICE_LOOKUP_FAILED", message: "Unable to resolve device" } }, 500);
  }
  if (!device || device.status !== "active") {
    return json({ error: { code: "DEVICE_NOT_REGISTERED", message: "Device is not registered or active" } }, 403);
  }

  const requestBody = JSON.stringify(body.payload ?? null);
  const requestHashBuffer = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(requestBody),
  );
  const requestHash = Array.from(new Uint8Array(requestHashBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  const { data: existing, error: existingError } = await admin
    .from("idempotency_keys")
    .select("operation_type, request_hash, response_status, response_body, completed_at")
    .eq("business_id", body.business_id)
    .eq("key", body.operation_id)
    .maybeSingle();

  if (existingError) {
    return json({ error: { code: "IDEMPOTENCY_LOOKUP_FAILED", message: "Unable to inspect command idempotency" } }, 500);
  }

  if (existing) {
    if (existing.operation_type !== body.operation_type || existing.request_hash !== requestHash) {
      return json({ error: { code: "IDEMPOTENCY_CONFLICT", message: "Operation id was already used with a different request" } }, 409);
    }
    if (existing.completed_at && existing.response_body) {
      return json(existing.response_body, existing.response_status ?? 200);
    }
  }

  const { data: operation, error: operationError } = await admin
    .from("sync_operations")
    .insert({
      business_id: body.business_id,
      device_id: device.id,
      user_id: userId,
      operation_id: body.operation_id,
      operation_type: body.operation_type,
      client_reference: body.client_reference ?? null,
      status: "received",
    })
    .select("id")
    .single();

  if (operationError) {
    return json({ error: { code: "OPERATION_RECORD_FAILED", message: "Unable to record sync operation" } }, 500);
  }

  const response = {
    data: {
      accepted: true,
      operation_id: body.operation_id,
      server_operation_id: operation.id,
      status: "received",
      server_authoritative: true,
    },
  };

  const { error: idemError } = await admin.from("idempotency_keys").upsert({
    business_id: body.business_id,
    device_id: device.id,
    user_id: userId,
    key: body.operation_id,
    operation_type: body.operation_type,
    request_hash: requestHash,
    response_status: 202,
    response_body: response,
    completed_at: new Date().toISOString(),
  }, { onConflict: "business_id,key" });

  if (idemError) {
    return json({ error: { code: "IDEMPOTENCY_RECORD_FAILED", message: "Unable to finalize command idempotency" } }, 500);
  }

  return json(response, 202);
});
