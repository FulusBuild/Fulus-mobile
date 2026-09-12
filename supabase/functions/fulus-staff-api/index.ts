import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204 });
  const auth = req.headers.get("authorization");
  if (!auth?.startsWith("Bearer ")) return json({ error: { code: "UNAUTHENTICATED", message: "Bearer token required" } }, 401);

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await admin.auth.getUser(auth.slice(7));
  if (userError || !userData.user) return json({ error: { code: "UNAUTHENTICATED", message: "Invalid access token" } }, 401);

  let body: Record<string, unknown>;
  try { body = await req.json(); }
  catch { return json({ error: { code: "INVALID_JSON", message: "Request body must be valid JSON" } }, 400); }

  const action = body.action;
  if (action === "claim_invite") {
    const { data, error } = await admin.rpc("claim_staff_invite", { target_token: body.token, target_actor_user_id: userData.user.id });
    if (error) return json({ error: { code: "STAFF_ACCESS_FAILED", message: error.message } }, error.code === "42501" ? 403 : 400);
    return json({ data, server_authoritative: true });
  }

  const businessId = typeof body.business_id === "string" ? body.business_id : null;
  if (!businessId) return json({ error: { code: "INVALID_REQUEST", message: "business_id is required" } }, 400);

  const { data: membership, error: membershipError } = await admin
    .from("business_memberships")
    .select("role_id,status,roles(name)")
    .eq("business_id", businessId).eq("user_id", userData.user.id).eq("status", "active").maybeSingle();
  if (membershipError) return json({ error: { code: "AUTHORIZATION_CHECK_FAILED", message: "Unable to resolve business access" } }, 500);
  if (!membership) return json({ error: { code: "FORBIDDEN", message: "User is not an active member of this business" } }, 403);

  const roleName = (membership.roles as { name?: string } | null)?.name;
  const isAdmin = roleName === "owner" || roleName === "admin";
  if (!isAdmin) return json({ error: { code: "FORBIDDEN", message: "Owner or admin access is required" } }, 403);

  let data; let error;
  switch (action) {
    case "create_invite":
      ({ data, error } = await admin.rpc("create_staff_invite", {
        target_business_id: businessId, target_role_id: body.role_id,
        target_email: typeof body.email === "string" ? body.email : null,
        target_expires_hours: Number(body.expires_hours ?? 24), target_actor_user_id: userData.user.id,
      }));
      break;
    case "set_member_status":
      ({ data, error } = await admin.rpc("set_member_status", {
        target_business_id: businessId, target_membership_id: body.membership_id, target_status: body.status, target_actor_user_id: userData.user.id,
      }));
      break;
    case "change_member_role":
      ({ data, error } = await admin.rpc("change_member_role", {
        target_business_id: businessId, target_membership_id: body.membership_id, target_role_id: body.role_id, target_actor_user_id: userData.user.id,
      }));
      break;
    case "set_role_permission":
      ({ data, error } = await admin.rpc("set_role_permission", {
        target_business_id: businessId, target_role_id: body.role_id,
        target_permission_id: body.permission_id, enabled: body.enabled === true, target_actor_user_id: userData.user.id,
      }));
      break;
    case "list_devices":
      ({ data, error } = await admin.from("devices").select("*").eq("business_id", businessId).order("created_at", { ascending: false }));
      break;
    case "revoke_device":
      ({ data, error } = await admin.rpc("revoke_device", {
        target_business_id: businessId, target_device_id: body.device_id, target_user_id: userData.user.id,
      }));
      break;
    default:
      return json({ error: { code: "UNKNOWN_ACTION", message: "Unsupported staff access action" } }, 400);
  }

  if (error) {
    return json({ error: { code: "STAFF_ACCESS_FAILED", message: error.message } }, error.code === "42501" ? 403 : 400);
  }
  return json({ data, server_authoritative: true });
});
