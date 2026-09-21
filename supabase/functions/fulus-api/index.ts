import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const url = Deno.env.get("SUPABASE_URL")!;
const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const out = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

Deno.serve(async req => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "authorization, content-type, x-fulus-device-id", "access-control-allow-methods": "GET, POST, OPTIONS" } });
  const u = new URL(req.url);
  if (u.pathname.endsWith("/health") || u.searchParams.get("action") === "health") return out({ data: { service: "fulus-api", status: "ok", server_authoritative: true } });
  const ah = req.headers.get("authorization");
  if (!ah?.startsWith("Bearer ")) return out({ error: { code: "UNAUTHENTICATED", message: "Bearer token required" } }, 401);
  const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  // Keep privileged reads on the service-role client, but execute business RPCs
  // with the caller JWT in the Authorization header so PostgreSQL auth.uid()
  // resolves to the signed-in user inside SECURITY DEFINER functions.
  // Without this, the service-role Authorization header makes auth.uid() null
  // and valid owner operations are incorrectly rejected as forbidden.
  const userDb = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: ah } },
  });
  const { data: ud, error: ue } = await db.auth.getUser(ah.slice(7).trim());
  if (ue || !ud.user) return out({ error: { code: "UNAUTHENTICATED", message: "Invalid access token" } }, 401);
  const uid = ud.user.id;
  const dc = req.headers.get("x-fulus-device-id");
  const { data: members, error: me } = await db.from("business_memberships").select("business_id,role_id,status,joined_at").eq("user_id", uid).eq("status", "active");
  if (me) return out({ error: { code: "MEMBERSHIP_LOOKUP_FAILED", message: "Unable to resolve memberships" } }, 500);

  if (req.method === "GET") {
    const bid = u.searchParams.get("business_id");
    if (!bid) return out({ data: { user_id: uid, memberships: members ?? [], device_client_id: dc, server_authoritative: true } });
    if (!(members ?? []).some(m => m.business_id === bid)) return out({ error: { code: "FORBIDDEN", message: "User is not an active member of this business" } }, 403);
    if (!dc) return out({ error: { code: "DEVICE_REQUIRED", message: "x-fulus-device-id is required for sync" } }, 400);
    const { data: d, error: de } = await db.from("devices").select("id,status").eq("business_id", bid).eq("device_client_id", dc).maybeSingle();
    if (de) return out({ error: { code: "DEVICE_LOOKUP_FAILED", message: "Unable to resolve device" } }, 500);
    if (!d || d.status !== "active") return out({ error: { code: "DEVICE_NOT_REGISTERED", message: "Device is not registered or active" } }, 403);
    const cursor = Number(u.searchParams.get("cursor") ?? "0"), limit = Number(u.searchParams.get("limit") ?? "100");
    if (!Number.isSafeInteger(cursor) || cursor < 0 || !Number.isSafeInteger(limit) || limit < 1 || limit > 500) return out({ error: { code: "INVALID_SYNC_CURSOR", message: "Invalid cursor or limit" } }, 400);
    const { data: changes, error: ce } = await db.from("sync_changes").select("sequence,entity_type,entity_id,operation,payload,created_at").eq("business_id", bid).gt("sequence", cursor).order("sequence", { ascending: true }).limit(limit);
    if (ce) return out({ error: { code: "SYNC_PULL_FAILED", message: "Unable to read server changes" } }, 500);
    const rows = changes ?? [];
    return out({ data: { changes: rows, cursor, next_cursor: rows.length ? Number(rows[rows.length - 1].sequence) : cursor, has_more: rows.length === limit, server_authoritative: true } });
  }

  let b: Record<string, unknown>;
  try { b = await req.json(); } catch { return out({ error: { code: "INVALID_JSON", message: "Request body must be valid JSON" } }, 400); }
  const action = typeof b.action === "string" ? b.action : null;

  if (action === "create_business") {
    const name = typeof b.name === "string" ? b.name.trim() : "";
    if (name.length < 2) return out({ error: { code: "INVALID_BUSINESS", message: "Business name must be at least 2 characters" } }, 400);
    const { data, error } = await userDb.rpc("create_business_for_user", { target_name: name, target_currency_code: typeof b.currency_code === "string" ? b.currency_code : "NGN", target_timezone: typeof b.timezone === "string" ? b.timezone : "Africa/Lagos", target_location_name: typeof b.location_name === "string" ? b.location_name : "Main" });
    if (error) return out({ error: { code: "BUSINESS_CREATION_FAILED", message: error.message } }, error.code === "42501" ? 403 : 400);
    return out({ data: { ...data, server_authoritative: true } }, 201);
  }

  const bid = typeof b.business_id === "string" ? b.business_id : null;
  if (!bid) return out({ error: { code: "INVALID_COMMAND", message: "business_id is required" } }, 400);
  if (!(members ?? []).some(m => m.business_id === bid)) return out({ error: { code: "FORBIDDEN", message: "User is not an active member of this business" } }, 403);

  if (action === "register_device") {
    const cid = typeof b.device_client_id === "string" ? b.device_client_id : null;
    if (!cid) return out({ error: { code: "INVALID_DEVICE_REGISTRATION", message: "device_client_id is required" } }, 400);
    const { data, error } = await userDb.rpc("register_device", { target_business_id: bid, target_user_id: uid, target_device_client_id: cid, target_device_name: typeof b.device_name === "string" ? b.device_name : null, target_platform: typeof b.platform === "string" ? b.platform : null, target_app_version: typeof b.app_version === "string" ? b.app_version : null });
    if (error) return out({ error: { code: "DEVICE_REGISTRATION_FAILED", message: error.message } }, error.code === "42501" ? 403 : 400);
    return out({ data: { device: data, server_authoritative: true } }, 201);
  }

  if (action === "location_create") {
    const name = typeof b.name === "string" ? b.name.trim() : "";
    const operationId = typeof b.operation_id === "string" ? b.operation_id : null;
    if (!name || !operationId) return out({ error: { code: "INVALID_LOCATION", message: "name and operation_id are required" } }, 400);
    const { data, error } = await userDb.rpc("create_location", { target_business_id: bid, target_operation_id: operationId, target_name: name, target_code: typeof b.code === "string" ? b.code : null, target_address: typeof b.address === "string" ? b.address : null, target_timezone: typeof b.timezone === "string" ? b.timezone : "Africa/Lagos" });
    if (error) return out({ error: { code: "LOCATION_CREATION_FAILED", message: error.message } }, error.code === "42501" ? 403 : 400);
    return out({ data: { ...data, server_authoritative: true } }, data?.status === "already_applied" ? 200 : 201);
  }

  if (["catalog_list", "catalog_upsert", "catalog_delete"].includes(String(action))) {
    const entity = typeof b.entity === "string" ? b.entity : null;
    if (!entity || !["products", "categories", "suppliers", "expense_categories"].includes(entity)) return out({ error: { code: "INVALID_CATALOG_REQUEST", message: "Unsupported catalog entity" } }, 400);
    // `user_has_permission` is deliberately called through the service-role client.\n    // The function is explicitly revoked from authenticated users and safely\n    // scopes the check by the already-validated caller uid.\n    const { data: allowed, error: pe } = await db.rpc("user_has_permission", { target_business_id: bid, target_user_id: uid, target_permission: action === "catalog_list" ? "catalog.read" : "catalog.manage" });
    if (pe) return out({ error: { code: "AUTHORIZATION_CHECK_FAILED", message: "Unable to verify catalog permission" } }, 500);
    if (!allowed) return out({ error: { code: "FORBIDDEN", message: "Insufficient catalog permission" } }, 403);
    if (action === "catalog_list") {
      const { data, error } = await db.from(entity).select("*").eq("business_id", bid).is("deleted_at", null).order("updated_at", { ascending: false }).limit(Math.min(Math.max(Number(b.limit ?? 100), 1), 500));
      if (error) return out({ error: { code: "CATALOG_READ_FAILED", message: "Unable to read catalog" } }, 500);
      return out({ data: { entity, items: data ?? [], server_authoritative: true } });
    }
    const id = typeof b.id === "string" ? b.id : null;
    if (action === "catalog_delete") {
      if (!id) return out({ error: { code: "INVALID_CATALOG_DELETE", message: "id is required" } }, 400);
      const { data, error } = await db.from(entity).update({ deleted_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", id).eq("business_id", bid).select("*").maybeSingle();
      if (error) return out({ error: { code: "CATALOG_DELETE_FAILED", message: error.message } }, 500);
      if (!data) return out({ error: { code: "NOT_FOUND", message: "Catalog item not found" } }, 404);
      return out({ data: { entity, item: data, server_authoritative: true } });
    }
    const input = b.item && typeof b.item === "object" ? b.item as Record<string, unknown> : {};
    const fields: Record<string, string[]> = { categories: ["name", "description"], suppliers: ["name", "phone", "email", "address"], products: ["name", "sku", "barcode", "category_id", "supplier_id", "cost_price", "selling_price", "low_stock_threshold", "is_active"], expense_categories: ["name"] };
    const row: Record<string, unknown> = { business_id: bid };
    for (const f of fields[entity]) if (f in input) row[f] = input[f];
    if (typeof row.name !== "string" || !row.name.trim()) return out({ error: { code: "INVALID_CATALOG_ITEM", message: "name is required" } }, 400);
    row.name = (row.name as string).trim();
    const { data, error } = id ? await db.from(entity).update(row).eq("id", id).eq("business_id", bid).select("*").maybeSingle() : await db.from(entity).insert(row).select("*").single();
    if (error) return out({ error: { code: "CATALOG_WRITE_FAILED", message: error.message } }, 400);
    return out({ data: { entity, item: data, server_authoritative: true } }, id ? 200 : 201);
  }

  if (!dc) return out({ error: { code: "DEVICE_REQUIRED", message: "x-fulus-device-id is required for commands" } }, 400);
  const oid = typeof b.operation_id === "string" ? b.operation_id : null;
  if (!oid) return out({ error: { code: "INVALID_COMMAND", message: "operation_id is required" } }, 400);
  const { data: d, error: de } = await db.from("devices").select("id,status").eq("business_id", bid).eq("device_client_id", dc).maybeSingle();
  if (de) return out({ error: { code: "DEVICE_LOOKUP_FAILED", message: "Unable to resolve device" } }, 500);
  if (!d || d.status !== "active") return out({ error: { code: "DEVICE_NOT_REGISTERED", message: "Device is not registered or active" } }, 403);

  let data: any, error: any;
  if (action === "sale_payment") ({ data, error } = await userDb.rpc("record_sale_payment", { target_business_id: bid, target_sale_id: b.sale_id, target_amount: Number(b.amount), target_operation_id: oid, target_payment_method: typeof b.payment_method === "string" ? b.payment_method : "cash", target_device_id: d.id }));
  else if (action === "sale_create") ({ data, error } = await userDb.rpc("create_sale_atomic", { target_business_id: bid, target_location_id: b.location_id, target_customer_id: typeof b.customer_id === "string" ? b.customer_id : null, target_client_reference: b.client_reference, target_sale_date: typeof b.sale_date === "string" ? b.sale_date : new Date().toISOString(), target_discount: Number(b.discount ?? 0), target_tax: Number(b.tax ?? 0), target_amount_paid: Number(b.amount_paid ?? 0), target_payment_method: typeof b.payment_method === "string" ? b.payment_method : null, target_notes: typeof b.notes === "string" ? b.notes : null, target_device_id: d.id, target_items: Array.isArray(b.items) ? b.items : [] }));
  else if (action === "customer_create") ({ data, error } = await userDb.rpc("create_customer", { target_business_id: bid, target_name: b.name, target_phone: typeof b.phone === "string" ? b.phone : null, target_email: typeof b.email === "string" ? b.email : null, target_address: typeof b.address === "string" ? b.address : null, target_credit_limit: Number(b.credit_limit ?? 0) }));
  else if (action === "customer_repayment") ({ data, error } = await userDb.rpc("record_customer_repayment", { target_business_id: bid, target_customer_id: b.customer_id, target_amount: Number(b.amount), target_operation_id: oid, target_payment_method: typeof b.payment_method === "string" ? b.payment_method : null, target_note: typeof b.note === "string" ? b.note : null, target_device_id: d.id }));
  else if (action === "expense_create") ({ data, error } = await userDb.rpc("record_expense", { target_business_id: bid, target_location_id: b.location_id, target_amount: Number(b.amount), target_category: typeof b.category === "string" ? b.category : "general", target_description: typeof b.description === "string" ? b.description : null, target_operation_id: oid, target_device_id: d.id }));
  else if (action === "return_create") ({ data, error } = await userDb.rpc("create_return_atomic", { target_business_id: bid, target_sale_id: b.sale_id, target_client_reference: oid, target_reason: typeof b.reason === "string" ? b.reason : "Customer return", target_refund_amount: Number(b.refund_amount ?? 0), target_device_id: d.id, target_items: Array.isArray(b.items) ? b.items : [] }));
  else if (action === "inventory_adjust") ({ data, error } = await userDb.rpc("apply_inventory_adjustment", { target_business_id: bid, target_product_id: b.product_id, target_location_id: b.location_id, target_quantity_delta: Number(b.quantity_delta), target_reason: b.reason, target_operation_id: oid, target_device_id: d.id }));
  else if (action === "income_create") ({ data, error } = await userDb.rpc("cloud_record_income", { target_business_id: bid, target_location_id: b.location_id, target_source: b.source, target_amount: Number(b.amount), target_income_date: b.income_date, target_notes: typeof b.notes === "string" ? b.notes : null, target_operation_id: oid, target_device_id: d.id }));
  else if (action === "cash_drawer_open") ({ data, error } = await userDb.rpc("cloud_open_cash_drawer_shift", { target_business_id: bid, target_location_id: b.location_id, target_opening_cash: Number(b.opening_cash), target_opened_at: b.opened_at, target_operation_id: oid, target_device_id: d.id }));
  else if (action === "cash_drawer_close") ({ data, error } = await userDb.rpc("cloud_close_cash_drawer_shift", { target_business_id: bid, target_shift_id: b.shift_id, target_closing_cash: Number(b.closing_cash), target_cash_difference: b.cash_difference == null ? null : Number(b.cash_difference), target_closing_note: typeof b.closing_note === "string" ? b.closing_note : null, target_closed_at: b.closed_at, target_operation_id: oid, target_device_id: d.id }));
  else if (action === "sync_operation") {
    const payload = b.payload && typeof b.payload === "object" ? b.payload : {};
    const h = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify(payload)));
    const hash = Array.from(new Uint8Array(h)).map(x => x.toString(16).padStart(2, "0")).join("");
    ({ data, error } = await userDb.rpc("accept_sync_operation", { target_business_id: bid, target_device_id: d.id, target_user_id: uid, target_operation_id: oid, target_operation_type: typeof b.operation_type === "string" ? b.operation_type : "", target_client_reference: typeof b.client_reference === "string" ? b.client_reference : null, target_request_hash: hash }));
  } else return out({ error: { code: "UNSUPPORTED_COMMAND", message: "Unsupported Fulus Cloud command" } }, 400);

  if (error) return out({ error: { code: "COMMAND_FAILED", message: error.message } }, error.code === "42501" ? 403 : error.code === "22013" ? 409 : error.code === "P0002" ? 404 : 400);
  return out({ data }, data?.status === "already_applied" ? 200 : 201);
});
