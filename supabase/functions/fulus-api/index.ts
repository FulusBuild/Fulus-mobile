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

  const url = new URL(req.url);
  if (url.pathname.endsWith("/health") || url.searchParams.get("action") === "health") {
    return json({ data: { service: "fulus-api", status: "ok", server_authoritative: true } });
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

  if (req.method === "POST") {
    let raw: Record<string, unknown>;
    try { raw = await req.json(); } catch { return json({ error: { code: "INVALID_JSON", message: "Request body must be valid JSON" } }, 400); }
    if (raw.action === "create_business") {
      const name = typeof raw.name === "string" ? raw.name : null;
      if (!name || name.trim().length < 2) {
        return json({ error: { code: "INVALID_BUSINESS", message: "Business name must be at least 2 characters" } }, 400);
      }
      const { data, error } = await admin.rpc("create_business_for_user", {
        target_name: name,
        target_currency_code: typeof raw.currency_code === "string" ? raw.currency_code : "NGN",
        target_timezone: typeof raw.timezone === "string" ? raw.timezone : "Africa/Lagos",
        target_location_name: typeof raw.location_name === "string" ? raw.location_name : "Main",
      });
      if (error) {
        return json({ error: { code: "BUSINESS_CREATION_FAILED", message: error.message } }, error.code === "42501" ? 403 : 400);
      }
      return json({ data: { ...data, server_authoritative: true } }, 201);
    }
    if (raw.action === "customer_create") {
      const businessId = typeof raw.business_id === "string" ? raw.business_id : null;
      const name = typeof raw.name === "string" ? raw.name : null;
      if (!businessId || !name?.trim()) return json({ error: { code: "INVALID_CUSTOMER", message: "business_id and name are required" } }, 400);
      if (!(memberships ?? []).some((m) => m.business_id === businessId)) return json({ error: { code: "FORBIDDEN", message: "User is not an active member of this business" } }, 403);
      const { data, error } = await admin.rpc("create_customer", {
        target_business_id: businessId, target_name: name, target_phone: typeof raw.phone === "string" ? raw.phone : null,
        target_email: typeof raw.email === "string" ? raw.email : null, target_address: typeof raw.address === "string" ? raw.address : null,
        target_credit_limit: Number(raw.credit_limit ?? 0),
      });
      if (error) return json({ error: { code: "CUSTOMER_CREATE_FAILED", message: error.message } }, error.code === "42501" ? 403 : 400);
      return json({ data }, 201);
    }

    if (raw.action === "customer_repayment") {
      const businessId = typeof raw.business_id === "string" ? raw.business_id : null;
      const customerId = typeof raw.customer_id === "string" ? raw.customer_id : null;
      const operationId = typeof raw.operation_id === "string" ? raw.operation_id : null;
      const amount = Number(raw.amount);
      if (!businessId || !customerId || !operationId || !Number.isFinite(amount) || amount <= 0) return json({ error: { code: "INVALID_REPAYMENT", message: "business_id, customer_id, amount and operation_id are required" } }, 400);
      if (!(memberships ?? []).some((m) => m.business_id === businessId)) return json({ error: { code: "FORBIDDEN", message: "User is not an active member of this business" } }, 403);
      const { data: device, error: deviceError } = await admin.from("devices").select("id,status").eq("business_id",businessId).eq("device_client_id",deviceClientId).maybeSingle();
      if (deviceError) return json({ error: { code: "DEVICE_LOOKUP_FAILED", message: "Unable to resolve device" } }, 500);
      if (!device || device.status !== "active") return json({ error: { code: "DEVICE_NOT_REGISTERED", message: "Device is not registered or active" } }, 403);
      const { data, error } = await admin.rpc("record_customer_repayment", {
        target_business_id: businessId, target_customer_id: customerId, target_amount: amount, target_operation_id: operationId,
        target_payment_method: typeof raw.payment_method === "string" ? raw.payment_method : null,
        target_note: typeof raw.note === "string" ? raw.note : null, target_device_id: device.id,
      });
      if (error) return json({ error: { code: "CUSTOMER_REPAYMENT_FAILED", message: error.message } }, error.code === "42501" ? 403 : 400);
      return json({ data });
    }

    if (raw.action === "sale_create") {
      const businessId = typeof raw.business_id === "string" ? raw.business_id : null;
      const locationId = typeof raw.location_id === "string" ? raw.location_id : null;
      const clientReference = typeof raw.client_reference === "string" ? raw.client_reference : null;
      const items = Array.isArray(raw.items) ? raw.items : null;
      if (!businessId || !locationId || !clientReference || !items || items.length === 0) {
        return json({ error: { code: "INVALID_SALE", message: "business_id, location_id, client_reference and items are required" } }, 400);
      }
      if (!(memberships ?? []).some((m) => m.business_id === businessId)) {
        return json({ error: { code: "FORBIDDEN", message: "User is not an active member of this business" } }, 403);
      }
      const { data: device, error: deviceError } = await admin.from("devices")
        .select("id,status").eq("business_id",businessId).eq("device_client_id",deviceClientId).maybeSingle();
      if (deviceError) return json({ error: { code: "DEVICE_LOOKUP_FAILED", message: "Unable to resolve device" } }, 500);
      if (!device || device.status !== "active") return json({ error: { code: "DEVICE_NOT_REGISTERED", message: "Device is not registered or active" } }, 403);
      const { data, error } = await admin.rpc("create_sale_atomic", {
        target_business_id: businessId,
        target_location_id: locationId,
        target_customer_id: typeof raw.customer_id === "string" ? raw.customer_id : null,
        target_client_reference: clientReference,
        target_sale_date: typeof raw.sale_date === "string" ? raw.sale_date : new Date().toISOString(),
        target_discount: Number(raw.discount ?? 0),
        target_tax: Number(raw.tax ?? 0),
        target_amount_paid: Number(raw.amount_paid ?? 0),
        target_payment_method: typeof raw.payment_method === "string" ? raw.payment_method : null,
        target_notes: typeof raw.notes === "string" ? raw.notes : null,
        target_device_id: device.id,
        target_items: items,
      });
      if (error) {
        const status = error.code === "42501" ? 403 : error.code === "22013" ? 409 : 400;
        return json({ error: { code: "SALE_CREATE_FAILED", message: error.message } }, status);
      }
      return json({ data }, data?.status === "already_applied" ? 200 : 201);
    }

    if (raw.action === "inventory_adjust") {
      const businessId = typeof raw.business_id === "string" ? raw.business_id : null;
      const productId = typeof raw.product_id === "string" ? raw.product_id : null;
      const locationId = typeof raw.location_id === "string" ? raw.location_id : null;
      const operationId = typeof raw.operation_id === "string" ? raw.operation_id : null;
      const delta = Number(raw.quantity_delta);
      const reason = typeof raw.reason === "string" ? raw.reason : null;
      if (!businessId || !productId || !locationId || !operationId || !reason || !Number.isSafeInteger(delta) || delta === 0) {
        return json({ error: { code: "INVALID_INVENTORY_ADJUSTMENT", message: "business_id, product_id, location_id, integer quantity_delta, reason and operation_id are required" } }, 400);
      }
      if (!(memberships ?? []).some((m) => m.business_id === businessId)) {
        return json({ error: { code: "FORBIDDEN", message: "User is not an active member of this business" } }, 403);
      }
      const { data: device, error: deviceError } = await admin.from("devices")
        .select("id,status").eq("business_id",businessId).eq("device_client_id",deviceClientId).maybeSingle();
      if (deviceError) return json({ error: { code: "DEVICE_LOOKUP_FAILED", message: "Unable to resolve device" } }, 500);
      if (!device || device.status !== "active") return json({ error: { code: "DEVICE_NOT_REGISTERED", message: "Device is not registered or active" } }, 403);
      const { data, error } = await admin.rpc("apply_inventory_adjustment", {
        target_business_id: businessId, target_product_id: productId, target_location_id: locationId,
        target_quantity_delta: delta, target_reason: reason, target_operation_id: operationId,
        target_device_id: device.id,
      });
      if (error) {
        const status = error.code === "42501" ? 403 : error.code === "22013" ? 409 : 400;
        return json({ error: { code: "INVENTORY_ADJUSTMENT_FAILED", message: error.message } }, status);
      }
      return json({ data }, data?.status === "already_applied" ? 200 : 201);
    }

    if (["catalog_list", "catalog_upsert", "catalog_delete"].includes(String(raw.action))) {
      const businessId = typeof raw.business_id === "string" ? raw.business_id : null;
      const entity = typeof raw.entity === "string" ? raw.entity : null;
      if (!businessId || !entity || !["products", "categories", "suppliers"].includes(entity)) {
        return json({ error: { code: "INVALID_CATALOG_REQUEST", message: "business_id and a supported entity are required" } }, 400);
      }
      if (!(memberships ?? []).some((m) => m.business_id === businessId)) {
        return json({ error: { code: "FORBIDDEN", message: "User is not an active member of this business" } }, 403);
      }
      const permission = raw.action === "catalog_list" ? "catalog.read" : "catalog.manage";
      const { data: permitted, error: permissionError } = await admin.rpc("user_has_permission", {
        target_business_id: businessId,
        target_user_id: userId,
        target_permission: permission,
      });
      if (permissionError) {
        return json({ error: { code: "AUTHORIZATION_CHECK_FAILED", message: "Unable to verify catalog permission" } }, 500);
      }
      if (!permitted) {
        return json({ error: { code: "FORBIDDEN", message: "Insufficient catalog permission" } }, 403);
      }

      const table = entity;
      if (raw.action === "catalog_list") {
        const limit = Math.min(Math.max(Number(raw.limit ?? 100), 1), 500);
        const { data, error } = await admin.from(table)
          .select("*")
          .eq("business_id", businessId)
          .is("deleted_at", null)
          .order("updated_at", { ascending: false })
          .limit(limit);
        if (error) return json({ error: { code: "CATALOG_READ_FAILED", message: "Unable to read catalog" } }, 500);
        return json({ data: { entity, items: data ?? [], server_authoritative: true } });
      }

      const itemId = typeof raw.id === "string" ? raw.id : null;
      if (raw.action === "catalog_delete") {
        if (!itemId) return json({ error: { code: "INVALID_CATALOG_DELETE", message: "id is required" } }, 400);
        const { data, error } = await admin.from(table)
          .update({ deleted_at: new Date().toISOString(), updated_at: new Date().toISOString() })
          .eq("id", itemId)
          .eq("business_id", businessId)
          .select("*")
          .maybeSingle();
        if (error) return json({ error: { code: "CATALOG_DELETE_FAILED", message: "Unable to delete catalog item" } }, 500);
        if (!data) return json({ error: { code: "NOT_FOUND", message: "Catalog item not found" } }, 404);
        return json({ data: { entity, item: data, server_authoritative: true } });
      }

      const input = (raw.item && typeof raw.item === "object") ? raw.item as Record<string, unknown> : {};
      const allowedFields: Record<string, string[]> = {
        categories: ["name", "description"],
        suppliers: ["name", "phone", "email", "address"],
        products: ["name", "sku", "barcode", "category_id", "supplier_id", "cost_price", "selling_price", "low_stock_threshold", "is_active"],
      };
      const row: Record<string, unknown> = { business_id: businessId };
      for (const field of allowedFields[entity]) {
        if (field in input) row[field] = input[field];
      }
      if (entity === "categories" || entity === "suppliers" || entity === "products") {
        if (typeof row.name !== "string" || row.name.trim().length < 1) {
          return json({ error: { code: "INVALID_CATALOG_ITEM", message: "name is required" } }, 400);
        }
        row.name = row.name.trim();
      }
      if (entity === "products") {
        if (typeof row.sku !== "string" || row.sku.trim().length < 1) {
          return json({ error: { code: "INVALID_PRODUCT", message: "sku is required" } }, 400);
        }
        row.sku = row.sku.trim();
        for (const fk of ["category_id", "supplier_id"]) {
          if (row[fk] != null) {
            const { data: parent, error: parentError } = await admin.from(fk === "category_id" ? "categories" : "suppliers")
              .select("id").eq("id", row[fk]).eq("business_id", businessId).maybeSingle();
            if (parentError) return json({ error: { code: "CATALOG_VALIDATION_FAILED", message: "Unable to validate catalog relationship" } }, 500);
            if (!parent) return json({ error: { code: "INVALID_CATALOG_RELATION", message: fk + " belongs to another business or does not exist" } }, 400);
          }
        }
      }
      let query;
      if (itemId) {
        query = admin.from(table).update(row).eq("id", itemId).eq("business_id", businessId).select("*").maybeSingle();
      } else {
        query = admin.from(table).insert(row).select("*").single();
      }
      const { data, error } = await query;
      if (error) return json({ error: { code: "CATALOG_WRITE_FAILED", message: "Unable to save catalog item" } }, 400);
      return json({ data: { entity, item: data, server_authoritative: true } }, itemId ? 200 : 201);
    }

    if (raw.action === "register_device") {
      const businessId = typeof raw.business_id === "string" ? raw.business_id : null;
      const clientId = typeof raw.device_client_id === "string" ? raw.device_client_id : null;
      if (!businessId || !clientId) return json({ error: { code: "INVALID_DEVICE_REGISTRATION", message: "business_id and device_client_id are required" } }, 400);
      if (!(memberships ?? []).some((m) => m.business_id === businessId)) return json({ error: { code: "FORBIDDEN", message: "User is not an active member of this business" } }, 403);
      const { data, error } = await admin.rpc("register_device", {
        target_business_id: businessId, target_user_id: userId, target_device_client_id: clientId,
        target_device_name: typeof raw.device_name === "string" ? raw.device_name : null,
        target_platform: typeof raw.platform === "string" ? raw.platform : null,
        target_app_version: typeof raw.app_version === "string" ? raw.app_version : null,
      });
      if (error) return json({ error: { code: "DEVICE_REGISTRATION_FAILED", message: error.message } }, error.code === "42501" ? 403 : 400);
      return json({ data: { device: data, server_authoritative: true } }, 201);
    }
    if (raw.action === "revoke_device") {
      const businessId = typeof raw.business_id === "string" ? raw.business_id : null;
      const deviceId = typeof raw.device_id === "string" ? raw.device_id : null;
      if (!businessId || !deviceId) return json({ error: { code: "INVALID_DEVICE_REVOCATION", message: "business_id and device_id are required" } }, 400);
      const { data, error } = await admin.rpc("revoke_device", { target_business_id: businessId, target_device_id: deviceId, target_user_id: userId });
      if (error) return json({ error: { code: "DEVICE_REVOCATION_FAILED", message: error.message } }, error.code === "42501" ? 403 : 400);
      return json({ data: { revoked: data, server_authoritative: true } });
    }
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
