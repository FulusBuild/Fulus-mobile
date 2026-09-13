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

const directBusinessTables = [
  "locations", "location_memberships", "products", "categories", "suppliers",
  "customers", "sales", "inventory_movements", "expenses", "income_records",
  "expense_categories", "returns", "devices", "audit_events", "cash_ledger",
  "tax_remittances", "cash_drawer_shifts", "staff_invites", "roles",
];

async function allRows(table: string, businessId: string) {
  const rows: unknown[] = [];
  let from = 0;
  const pageSize = 1000;
  for (;;) {
    const { data, error } = await admin.from(table).select("*").eq("business_id", businessId).range(from, from + pageSize - 1);
    if (error) throw new Error(`${table}: ${error.message}`);
    const page = data ?? [];
    rows.push(...page);
    if (page.length < pageSize) break;
    from += pageSize;
  }
  return rows;
}

async function rowsIn(table: string, column: string, ids: string[]) {
  if (!ids.length) return [];
  const rows: unknown[] = [];
  for (let i = 0; i < ids.length; i += 500) {
    const chunk = ids.slice(i, i + 500);
    const { data, error } = await admin.from(table).select("*").in(column, chunk);
    if (error) throw new Error(`${table}: ${error.message}`);
    rows.push(...(data ?? []));
  }
  return rows;
}

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

  const { data: membership, error: membershipError } = await admin.from("business_memberships")
    .select("business_id, user_id, role_id, status, joined_at, created_at, updated_at, roles(name)")
    .eq("business_id", businessId).eq("user_id", userData.user.id).eq("status", "active").maybeSingle();
  if (membershipError) return json({ error: { code: "MEMBERSHIP_LOOKUP_FAILED" } }, 500);
  if (!membership) return json({ error: { code: "FORBIDDEN", message: "User is not an active member of this business" } }, 403);

  const roleName = String((membership.roles as { name?: string } | null)?.name ?? "");
  if (roleName !== "owner" && roleName !== "admin") {
    return json({ error: { code: "RESTORE_NOT_ALLOWED", message: "Only a business owner or administrator can restore a Fulus installation" } }, 403);
  }

  const { data: business, error: businessError } = await admin.from("businesses").select("*").eq("id", businessId).maybeSingle();
  if (businessError || !business) return json({ error: { code: "BUSINESS_NOT_FOUND" } }, 404);

  try {
    const snapshot: Record<string, unknown> = {
      version: 2,
      business,
      membership: { ...membership, roles: undefined },
      profile: null,
      businesses: [business],
    };
    const { data: profile } = await admin.from("profiles").select("*").eq("id", userData.user.id).maybeSingle();
    snapshot.profile = profile;

    for (const table of directBusinessTables) snapshot[table] = await allRows(table, businessId);

    const locations = snapshot.locations as Record<string, unknown>[];
    const products = snapshot.products as Record<string, unknown>[];
    const customers = snapshot.customers as Record<string, unknown>[];
    const sales = snapshot.sales as Record<string, unknown>[];
    const returns = snapshot.returns as Record<string, unknown>[];
    const roles = snapshot.roles as Record<string, unknown>[];
    const suppliers = snapshot.suppliers as Record<string, unknown>[];

    snapshot.product_stock_levels = await rowsIn("product_stock_levels", "product_id", products.map((r) => String(r.id)));
    snapshot.sale_items = await rowsIn("sale_items", "sale_id", sales.map((r) => String(r.id)));
    snapshot.sale_payments = await rowsIn("sale_payments", "sale_id", sales.map((r) => String(r.id)));
    snapshot.return_items = await rowsIn("return_items", "return_id", returns.map((r) => String(r.id)));
    snapshot.customer_ledger_entries = await rowsIn("customer_ledger_entries", "customer_id", customers.map((r) => String(r.id)));
    snapshot.supplier_ledger_entries = await rowsIn("supplier_ledger_entries", "supplier_id", suppliers.map((r) => String(r.id)));
    snapshot.role_permissions = await rowsIn("role_permissions", "role_id", roles.map((r) => String(r.id)));
    snapshot.business_memberships = await allRows("business_memberships", businessId);

    const { data: memberships } = await admin.from("business_memberships")
      .select("user_id, role_id, status, joined_at, created_at, updated_at")
      .eq("business_id", businessId);
    const userIds = [...new Set((memberships ?? []).map((m) => m.user_id).filter(Boolean))];
    if (userIds.length) {
      const { data: profiles } = await admin.from("profiles").select("*").in("id", userIds);
      snapshot.profiles = profiles ?? [];
    } else snapshot.profiles = [];

    snapshot.local_restore_notes = {
      non_cloud_local_tables: ["app_notifications", "paired_printers", "diagnostic_events", "sync_queue_items", "draft_carts", "draft_cart_items", "draft_cart_payments"],
      employee_source: "business_memberships + profiles",
      version: 2,
    };

    return json({ data: snapshot });
  } catch (error) {
    return json({ error: { code: "RESTORE_SNAPSHOT_FAILED", message: error instanceof Error ? error.message : "Unable to build restore snapshot" } }, 500);
  }
});
