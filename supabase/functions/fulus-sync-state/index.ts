import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const url = Deno.env.get("SUPABASE_URL")!;
const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const out = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      "access-control-allow-origin": "*",
    },
  });

const SIMPLE_ENTITIES: Record<string, string> = {
  customer: "customers",
  category: "categories",
  supplier: "suppliers",
  expense_category: "expense_categories",
  expense: "expenses",
  income_record: "income_records",
  cash_drawer_shift: "cash_drawer_shifts",
  location: "locations",
  customer_ledger: "customer_ledger_entries",
  stock_movement: "inventory_movements",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "access-control-allow-origin": "*",
        "access-control-allow-headers":
          "authorization, content-type, x-fulus-device-id",
        "access-control-allow-methods": "GET, OPTIONS",
      },
    });
  }
  if (req.method !== "GET") {
    return out({ error: { code: "METHOD_NOT_ALLOWED", message: "GET is required" } }, 405);
  }

  const auth = req.headers.get("authorization");
  if (!auth?.startsWith("Bearer ")) {
    return out({ error: { code: "UNAUTHENTICATED", message: "Bearer token required" } }, 401);
  }

  const params = new URL(req.url).searchParams;
  const businessId = params.get("business_id");
  const entityType = params.get("entity_type");
  const entityId = params.get("entity_id");
  const deviceClientId = req.headers.get("x-fulus-device-id");
  if (!businessId || !entityType || !entityId || !deviceClientId) {
    return out({
      error: {
        code: "INVALID_CANONICAL_REQUEST",
        message: "business_id, entity_type, entity_id and device id are required",
      },
    }, 400);
  }

  const db = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await db.auth.getUser(auth.slice(7).trim());
  if (userError || !userData.user) {
    return out({ error: { code: "UNAUTHENTICATED", message: "Invalid access token" } }, 401);
  }
  const userId = userData.user.id;
  const { data: membership, error: membershipError } = await db
    .from("business_memberships")
    .select("business_id")
    .eq("business_id", businessId)
    .eq("user_id", userId)
    .eq("status", "active")
    .maybeSingle();
  if (membershipError) {
    return out({ error: { code: "MEMBERSHIP_LOOKUP_FAILED", message: "Unable to resolve membership" } }, 500);
  }
  if (!membership) {
    return out({ error: { code: "FORBIDDEN", message: "User is not an active member of this business" } }, 403);
  }

  const { data: device, error: deviceError } = await db
    .from("devices")
    .select("id,status")
    .eq("business_id", businessId)
    .eq("device_client_id", deviceClientId)
    .maybeSingle();
  if (deviceError) {
    return out({ error: { code: "DEVICE_LOOKUP_FAILED", message: "Unable to resolve device" } }, 500);
  }
  if (!device || device.status !== "active") {
    return out({ error: { code: "DEVICE_NOT_REGISTERED", message: "Device is not registered or active" } }, 403);
  }

  if (entityType === "sale") {
    const { data: sale, error: saleError } = await db
      .from("sales")
      .select("*")
      .eq("business_id", businessId)
      .eq("id", entityId)
      .maybeSingle();
    if (saleError) return out({ error: { code: "CANONICAL_READ_FAILED", message: "Unable to read sale" } }, 500);
    if (!sale) {
      return out({ data: { entity_type: entityType, entity_id: entityId, operation: "delete", sale: null, sale_items: [], sale_payments: [], server_authoritative: true } });
    }
    const [{ data: items, error: itemsError }, { data: payments, error: paymentsError }] = await Promise.all([
      db.from("sale_items").select("*").eq("sale_id", entityId),
      db.from("sale_payments").select("*").eq("sale_id", entityId),
    ]);
    if (itemsError || paymentsError) {
      return out({ error: { code: "CANONICAL_READ_FAILED", message: "Unable to read sale aggregate" } }, 500);
    }
    return out({ data: { entity_type: entityType, entity_id: entityId, operation: "upsert", sale, sale_items: items ?? [], sale_payments: payments ?? [], server_authoritative: true } });
  }

  if (entityType === "product") {
    const { data: product, error } = await db
      .from("products")
      .select("*")
      .eq("business_id", businessId)
      .eq("id", entityId)
      .maybeSingle();
    if (error) return out({ error: { code: "CANONICAL_READ_FAILED", message: "Unable to read product" } }, 500);
    if (!product) {
      return out({ data: { entity_type: entityType, entity_id: entityId, operation: "delete", product: null, stock_levels: [], server_authoritative: true } });
    }
    const { data: stockLevels, error: stockError } = await db
      .from("product_stock_levels")
      .select("*")
      .eq("product_id", entityId);
    if (stockError) return out({ error: { code: "CANONICAL_READ_FAILED", message: "Unable to read product stock" } }, 500);
    return out({ data: { entity_type: entityType, entity_id: entityId, operation: "upsert", product, stock_levels: stockLevels ?? [], server_authoritative: true } });
  }

  if (entityType === "return") {
    const { data: returnRow, error: returnError } = await db
      .from("returns")
      .select("*")
      .eq("business_id", businessId)
      .eq("id", entityId)
      .maybeSingle();
    if (returnError) return out({ error: { code: "CANONICAL_READ_FAILED", message: "Unable to read return" } }, 500);
    if (!returnRow) {
      return out({ data: { entity_type: entityType, entity_id: entityId, operation: "delete", row: null, return_items: [], server_authoritative: true } });
    }
    const { data: items, error: itemsError } = await db
      .from("return_items")
      .select("*")
      .eq("return_id", entityId);
    if (itemsError) return out({ error: { code: "CANONICAL_READ_FAILED", message: "Unable to read return aggregate" } }, 500);
    return out({ data: { entity_type: entityType, entity_id: entityId, operation: "upsert", row: returnRow, return_items: items ?? [], server_authoritative: true } });
  }

  const table = SIMPLE_ENTITIES[entityType];
  if (!table) {
    return out({ error: { code: "UNSUPPORTED_ENTITY", message: `Unsupported canonical entity: ${entityType}` } }, 400);
  }
  const { data: row, error } = await db
    .from(table)
    .select("*")
    .eq("business_id", businessId)
    .eq("id", entityId)
    .maybeSingle();
  if (error) {
    return out({ error: { code: "CANONICAL_READ_FAILED", message: `Unable to read ${entityType}` } }, 500);
  }
  return out({ data: { entity_type: entityType, entity_id: entityId, operation: row ? "upsert" : "delete", row, server_authoritative: true } });
});
