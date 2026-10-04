import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

type AdminClient = SupabaseClient;

const rows = <T>(value: T[] | null | undefined): T[] => value ?? [];

async function read<T>(query: PromiseLike<{ data: T | null; error: any }>): Promise<T> {
  const result = await query;
  if (result.error) throw result.error;
  return result.data as T;
}

export async function buildEmployeeRestoreSnapshot(
  admin: AdminClient,
  businessId: string,
  userId: string,
): Promise<Record<string, unknown> | null> {
  const membership = await read(admin.from("business_memberships")
    .select("id,business_id,user_id,role_id,status,permissions_overridden,joined_at,created_at,updated_at,roles(id,name,business_id)")
    .eq("business_id", businessId).eq("user_id", userId).eq("status", "active").maybeSingle());
  if (!membership) return null;

  const role = Array.isArray(membership.roles) ? membership.roles[0] : membership.roles;
  const roleName = String(role?.name ?? "").toLowerCase();
  if (roleName === "owner" || roleName === "admin") return null;

  const [profile, employee, locationMemberships, locations, rolePermissions, memberPermissions, permissions, business, boundary] =
    await Promise.all([
      read(admin.from("profiles").select("*").eq("id", userId).maybeSingle()),
      read(admin.from("employees").select("*").eq("business_id", businessId).eq("auth_user_id", userId).maybeSingle()),
      read(admin.from("location_memberships").select("*").eq("business_id", businessId).eq("user_id", userId).eq("status", "active")),
      read(admin.from("locations").select("*").eq("business_id", businessId).eq("status", "active")),
      read(admin.from("role_permissions").select("*").eq("role_id", membership.role_id)),
      read(admin.from("business_member_permissions").select("*").eq("business_id", businessId).eq("user_id", userId)),
      read(admin.from("permissions").select("*")),
      read(admin.from("businesses").select("*").eq("id", businessId).maybeSingle()),
      read(admin.from("sync_changes").select("sequence").eq("business_id", businessId).order("sequence", { ascending: false }).limit(1).maybeSingle()),
    ]);

  const permissionById = new Map(rows(permissions).map((p: any) => [String(p.id), String(p.code)]));
  const rolePermissionIds = new Set(rows(rolePermissions).map((p: any) => String(p.permission_id)));
  const memberPermissionIds = new Set(rows(memberPermissions).map((p: any) => String(p.permission_id)));
  const effectiveIds = membership.permissions_overridden === true ? memberPermissionIds : rolePermissionIds;
  const codes = new Set([...effectiveIds].map(id => permissionById.get(id)).filter(Boolean) as string[]);
  const locationIds = rows(locationMemberships).map((m: any) => String(m.location_id));
  const accessibleLocations = rows(locations).filter((l: any) => locationIds.includes(String(l.id)));

  const categories = await read(admin.from("categories").select("*").eq("business_id", businessId));
  const products = await read(admin.from("products").select("*").eq("business_id", businessId));
  const allStock = await read(admin.from("product_stock_levels").select("*").in("location_id", locationIds.length ? locationIds : ["00000000-0000-0000-0000-000000000000"]));
  const suppliers = (codes.has("inventory.read") || codes.has("catalog.manage"))
    ? await read(admin.from("suppliers").select("*").eq("business_id", businessId)) : [];
  const customers = (codes.has("customers.read") || codes.has("customers.manage") || codes.has("credit.manage"))
    ? await read(admin.from("customers").select("*").eq("business_id", businessId)) : [];
  const sales = codes.has("sales.read")
    ? await read(admin.from("sales").select("*").eq("business_id", businessId)
        .in("location_id", locationIds.length ? locationIds : ["00000000-0000-0000-0000-000000000000"])) : [];
  const saleIds = rows(sales).map((s: any) => s.id);

  // Historical sales can reference cashiers other than the restoring employee.
  // Export only those cashier identities that are actually referenced by
  // sales in the employee's accessible locations. This keeps SQLite foreign
  // keys valid without exposing the whole business roster.
  const historicalCashierIds = [...new Set(
    rows(sales)
      .map((s: any) => s.cashier_user_id)
      .filter((id: any) => id != null)
      .map((id: any) => String(id)),
  )].filter((id) => id !== userId);

  const historicalMemberships = historicalCashierIds.length
    ? await read(admin.from("business_memberships").select("id,business_id,user_id,role_id,status,permissions_overridden,joined_at,created_at,updated_at,roles(id,name,business_id)")
        .eq("business_id", businessId).in("user_id", historicalCashierIds))
    : [];
  const historicalProfiles = historicalCashierIds.length
    ? await read(admin.from("profiles").select("*").in("id", historicalCashierIds))
    : [];
  const historicalRoles = rows(historicalMemberships)
    .map((m: any) => Array.isArray(m.roles) ? m.roles[0] : m.roles)
    .filter((r: any) => r?.id != null);
  const saleItems = codes.has("sales.read") && saleIds.length
    ? await read(admin.from("sale_items").select("*").in("sale_id", saleIds)) : [];
  const salePayments = codes.has("sales.read") && saleIds.length
    ? await read(admin.from("sale_payments").select("*").in("sale_id", saleIds)) : [];
  const expenses = (codes.has("finance.read") || codes.has("finance.manage"))
    ? await read(admin.from("expenses").select("*").eq("business_id", businessId)
        .in("location_id", locationIds.length ? locationIds : ["00000000-0000-0000-0000-000000000000"])) : [];
  const income = (codes.has("finance.read") || codes.has("finance.manage"))
    ? await read(admin.from("income_records").select("*").eq("business_id", businessId)
        .in("location_id", locationIds.length ? locationIds : ["00000000-0000-0000-0000-000000000000"])) : [];
  const cashShifts = (codes.has("cash.read") || codes.has("cash.manage"))
    ? await read(admin.from("cash_drawer_shifts").select("*").eq("business_id", businessId)
        .in("location_id", locationIds.length ? locationIds : ["00000000-0000-0000-0000-000000000000"])) : [];
  const movements = (codes.has("inventory.read") || codes.has("inventory.adjust") || codes.has("inventory.transfer"))
    ? await read(admin.from("inventory_movements").select("*").eq("business_id", businessId).in("location_id", locationIds.length ? locationIds : ["00000000-0000-0000-0000-000000000000"])) : [];
  const returns = (codes.has("returns.create") || codes.has("returns.approve"))
    ? await read(admin.from("returns").select("*").eq("business_id", businessId)) : [];
  const returnIds = rows(returns).map((r: any) => r.id);
  const returnItems = returnIds.length ? await read(admin.from("return_items").select("*").in("return_id", returnIds)) : [];

  return {
    version: 7,
    generated_at: new Date().toISOString(),
    sync_boundary: Number((boundary as any)?.sequence ?? 0),
    business,
    businesses: business ? [business] : [],
    membership,
    profile,
    locations: accessibleLocations,
    location_memberships: rows(locationMemberships),
    categories: rows(categories),
    products: rows(products),
    suppliers: rows(suppliers),
    customers: rows(customers),
    sales: rows(sales),
    sale_items: rows(saleItems),
    sale_payments: rows(salePayments),
    product_stock_levels: rows(allStock),
    inventory_movements: rows(movements),
    expenses: rows(expenses),
    income_records: rows(income),
    cash_drawer_shifts: rows(cashShifts),
    returns: rows(returns),
    return_items: rows(returnItems),
    employees: employee ? [employee] : [],
    roles: role ? [role] : [],
    business_memberships: [membership, ...rows(historicalMemberships)],
    business_member_permissions: rows(memberPermissions),
    profiles: [profile, ...rows(historicalProfiles)],
    role_permissions: rows(rolePermissions),
    permissions: rows(permissions),
    historical_cashier_user_ids: historicalCashierIds,
    historical_cashier_roles: historicalRoles,
    expense_categories: [],
    tax_remittances: [],
    audit_events: [],
    local_restore_notes: {
      employee_bootstrap: true,
      employee_source: "own employee + own active membership + own profile",
      authorization_source: "effective role/member permissions",
      location_scope: "active employee location memberships",
      sensitive_sections: "included only when the employee has the corresponding read/manage permission",
      version: 7,
    },
  };
}
