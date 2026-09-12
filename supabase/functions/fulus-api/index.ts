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
    const url = new URL(req.url);
    const businessId = url.searchParams.get("business_id");
    const cursorRaw = url.searchParams.get("cursor") ?? "0";
    const limitRaw = url.searchParams.get("limit") ?? "100";

    if (!businessId) {
      return json({ data: {
        user_id: userId,
        memberships: memberships ?? [],
        device_client_id: deviceClientId,
        server_authoritative: true,
      }});
    }

    const membership = (memberships ?? []).find((m) => m.business_id === businessId);
    if (!membership) {
      return json({ error: { code: "FORBIDDEN", message: "User is not an active member of this business" } }, 403);
    }

    if (!deviceClientId) {
      return json({ error: { code: "DEVICE_REQUIRED", message: "x-fulus-device-id is required for sync" } }, 400);
    }

    const { data: device, error: deviceError } = await admin
      .from("devices")
      .select("id, status")
      .eq("business_id", businessId)
      .eq("device_client_id", deviceClientId)
      .maybeSingle();

    if (deviceError) {
      return json({ error: { code: "DEVICE_LOOKUP_FAILED", message: "Unable to resolve device" } }, 500);
    }
    if (!device || device.status !== "active") {
      return json({ error: { code: "DEVICE_NOT_REGISTERED", message: "Device is not registered or active" } }, 403);
    }

    const cursor = Number(cursorRaw);
    const requestedLimit = Number(limitRaw);
    if (!Number.isSafeInteger(cursor) || cursor < 0 || !Number.isSafeInteger(requestedLimit) || requestedLimit < 1 || requestedLimit > 500) {
      return json({ error: { code: "INVALID_SYNC_CURSOR", message: "cursor must be a non-negative integer and limit must be between 1 and 500" } }, 400);
    }

    const { data: changes, error: changesError } = await admin
      .from("sync_changes")
      .select("sequence, entity_type, entity_id, operation, payload, created_at")
      .eq("business_id", businessId)
      .gt("sequence", cursor)
      .order("sequence", { ascending: true })
      .limit(requestedLimit);

    if (changesError) {
      return json({ error: { code: "SYNC_PULL_FAILED", message: "Unable to read server changes" } }, 500);
    }

    const rows = changes ?? [];
    const nextCursor = rows.length ? Number(rows[rows.length - 1].sequence) : cursor;
    return json({
      data: {
        changes: rows,
        cursor,
        next_cursor: nextCursor,
        has_more: rows.length === requestedLimit,
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

  const { data: result, error: commandError } = await admin.rpc(
    "accept_sync_operation",
    {
      target_business_id: body.business_id,
      target_device_id: device.id,
      target_user_id: userId,
      target_operation_id: body.operation_id,
      target_operation_type: body.operation_type,
      target_client_reference: body.client_reference ?? null,
      target_request_hash: requestHash,
    },
  );

  if (commandError || !result) {
    return json({
      error: {
        code: "COMMAND_ACCEPTANCE_FAILED",
        message: "Unable to accept sync operation",
      },
    }, 500);
  }

  if (result.error) {
    return json({ error: result.error }, result.status_code ?? 500);
  }

  return json(result.response, result.status_code ?? 202);
});
