import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const sha256Hex = async (value: string) => {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204 });

  const auth = req.headers.get("authorization");
  if (!auth?.startsWith("Bearer ")) {
    return json({ error: { code: "UNAUTHENTICATED", message: "Bearer token required" } }, 401);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await admin.auth.getUser(auth.slice(7));
  if (userError || !userData.user) {
    return json({ error: { code: "UNAUTHENTICATED", message: "Invalid access token" } }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: { code: "INVALID_JSON", message: "Request body must be valid JSON" } }, 400);
  }

  const action = body.action;

  if (action === "claim_invite") {
    const token = typeof body.token === "string" ? body.token.trim() : "";
    if (!token) {
      return json({ error: { code: "INVALID_REQUEST", message: "Invite token is required" } }, 400);
    }

    const displayName = typeof body.full_name === "string" ? body.full_name.trim() : "";
    if (displayName) {
      const { error: profileError } = await admin
        .from("profiles")
        .upsert({ id: userData.user.id, full_name: displayName }, { onConflict: "id" });
      if (profileError) {
        return json({ error: { code: "PROFILE_UPDATE_FAILED", message: "Unable to save the employee name" } }, 500);
      }
    }

    const { data, error } = await admin.rpc("claim_staff_invite", {
      target_token: token,
      target_user_id: userData.user.id,
    });
    if (!error) return json({ data, server_authoritative: true });

    // Claiming is intentionally idempotent for the same account. This makes
    // a partially completed first-device restore recoverable without asking
    // the owner to issue a second invitation.
    if (error.message !== "Invite already claimed") {
      return json(
        { error: { code: "STAFF_ACCESS_FAILED", message: error.message } },
        error.code === "42501" ? 403 : 400,
      );
    }

    const tokenHash = await sha256Hex(token);
    const { data: invite, error: inviteError } = await admin
      .from("staff_invites")
      .select("business_id,role_id,invited_email,claimed_by,expires_at")
      .eq("token_hash", tokenHash)
      .maybeSingle();

    if (inviteError || !invite || invite.claimed_by !== userData.user.id) {
      return json(
        { error: { code: "STAFF_ACCESS_FAILED", message: "Invite already claimed" } },
        409,
      );
    }

    if (invite.invited_email &&
        invite.invited_email.toLowerCase() !== (userData.user.email ?? "").toLowerCase()) {
      return json(
        { error: { code: "FORBIDDEN", message: "Invite email does not match the signed-in account" } },
        403,
      );
    }

    const { data: member, error: memberError } = await admin
      .from("business_memberships")
      .select("id,user_id,role_id,status,permissions_overridden")
      .eq("business_id", invite.business_id)
      .eq("user_id", userData.user.id)
      .eq("status", "active")
      .maybeSingle();

    if (memberError || !member) {
      return json(
        { error: { code: "STAFF_ACCESS_FAILED", message: "Claimed membership could not be recovered" } },
        500,
      );
    }

    const { data: role } = await admin
      .from("roles")
      .select("name")
      .eq("id", member.role_id)
      .eq("business_id", invite.business_id)
      .maybeSingle();

    const { data: profile } = await admin
      .from("profiles")
      .select("full_name")
      .eq("id", userData.user.id)
      .maybeSingle();

    const { data: locationMemberships } = await admin
      .from("location_memberships")
      .select("location_id")
      .eq("business_id", invite.business_id)
      .eq("user_id", userData.user.id)
      .eq("status", "active")
      .order("created_at", { ascending: true })
      .limit(1);

    let permissionCodes: string[] = [];
    if (member.permissions_overridden) {
      const { data: rows } = await admin
        .from("business_member_permissions")
        .select("permissions(code)")
        .eq("business_id", invite.business_id)
        .eq("user_id", userData.user.id);
      permissionCodes = (rows ?? [])
        .map((row) => (row.permissions as { code?: string } | null)?.code)
        .filter((code): code is string => typeof code === "string");
    } else {
      const { data: rows } = await admin
        .from("role_permissions")
        .select("permissions(code)")
        .eq("role_id", member.role_id);
      permissionCodes = (rows ?? [])
        .map((row) => (row.permissions as { code?: string } | null)?.code)
        .filter((code): code is string => typeof code === "string");
    }

    return json({
      data: {
        business_id: invite.business_id,
        membership_id: member.id,
        user_id: userData.user.id,
        role_id: member.role_id,
        role_name: role?.name ?? "cashier",
        full_name: profile?.full_name ?? "",
        email: userData.user.email ?? "",
        location_id: locationMemberships?.[0]?.location_id ?? null,
        permission_codes: permissionCodes,
      },
      server_authoritative: true,
    });
  }

  const businessId = typeof body.business_id === "string" ? body.business_id : null;
  if (!businessId) {
    return json({ error: { code: "INVALID_REQUEST", message: "business_id is required" } }, 400);
  }

  const { data: membership, error: membershipError } = await admin
    .from("business_memberships")
    .select("id,user_id,role_id,status,roles(name)")
    .eq("business_id", businessId)
    .eq("user_id", userData.user.id)
    .eq("status", "active")
    .maybeSingle();

  if (membershipError) {
    return json({ error: { code: "AUTHORIZATION_CHECK_FAILED", message: "Unable to resolve business access" } }, 500);
  }

  if (!membership) {
    return json({ error: { code: "FORBIDDEN", message: "User is not an active member of this business" } }, 403);
  }

  const roleName = (membership.roles as { name?: string } | null)?.name;
  const isAdmin = roleName === "owner" || roleName === "admin";
  if (!isAdmin) {
    return json({ error: { code: "FORBIDDEN", message: "Owner or admin access is required" } }, 403);
  }

  let data: unknown;
  let error: { code?: string; message: string } | null = null;

  switch (action) {
    case "create_invite": {
      const requestedRole = typeof body.role_name === "string" ? body.role_name.trim().toLowerCase() : "";
      const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
      const permissionCodes = Array.isArray(body.permission_codes)
        ? body.permission_codes.filter((value): value is string => typeof value === "string")
        : null;
      const locationId = typeof body.location_id === "string" ? body.location_id.trim() : null;

      if (!requestedRole || requestedRole === "owner") {
        return json({ error: { code: "INVALID_REQUEST", message: "A non-owner staff role is required" } }, 400);
      }
      if (!email) {
        return json({ error: { code: "INVALID_REQUEST", message: "Employee email is required" } }, 400);
      }

      const { data: role, error: roleError } = await admin
        .from("roles")
        .select("id")
        .eq("business_id", businessId)
        .eq("name", requestedRole)
        .maybeSingle();

      if (roleError) {
        return json({ error: { code: "STAFF_ACCESS_FAILED", message: "Unable to resolve staff role" } }, 500);
      }
      if (!role) {
        return json({ error: { code: "INVALID_REQUEST", message: "That staff role is not available for this business" } }, 400);
      }

      ({ data, error } = await admin.rpc("create_staff_invite", {
        target_business_id: businessId,
        target_role_id: role.id,
        target_email: email,
        target_expires_hours: Number(body.expires_hours ?? 24),
        target_actor_user_id: userData.user.id,
        target_permission_codes: permissionCodes,
        target_location_id: locationId || null,
      }));
      break;
    }

    case "set_member_permissions": {
      const targetUserId = typeof body.user_id === "string" ? body.user_id : "";
      const permissionCodes = Array.isArray(body.permission_codes)
        ? body.permission_codes.filter((value): value is string => typeof value === "string")
        : [];

      ({ data, error } = await admin.rpc("set_member_permission_overrides", {
        target_business_id: businessId,
        target_user_id: targetUserId,
        target_permission_codes: permissionCodes,
        target_actor_user_id: userData.user.id,
      }));
      break;
    }

    case "set_member_status":
      ({ data, error } = await admin.rpc("set_member_status", {
        target_business_id: businessId,
        target_membership_id: body.membership_id,
        target_status: body.status,
        target_user_id: userData.user.id,
      }));
      break;

    case "change_member_role":
      ({ data, error } = await admin.rpc("change_member_role", {
        target_business_id: businessId,
        target_membership_id: body.membership_id,
        target_role_id: body.role_id,
        target_user_id: userData.user.id,
      }));
      break;

    case "set_role_permission":
      ({ data, error } = await admin.rpc("set_role_permission", {
        target_business_id: businessId,
        target_role_id: body.role_id,
        target_permission_id: body.permission_id,
        enabled: body.enabled === true,
        target_actor_user_id: userData.user.id,
      }));
      break;

    case "list_devices":
      ({ data, error } = await admin
        .from("devices")
        .select("*")
        .eq("business_id", businessId)
        .order("created_at", { ascending: false }));
      break;

    case "revoke_device":
      ({ data, error } = await admin.rpc("revoke_device", {
        target_business_id: businessId,
        target_device_id: body.device_id,
        target_user_id: userData.user.id,
      }));
      break;

    default:
      return json({ error: { code: "UNKNOWN_ACTION", message: "Unsupported staff access action" } }, 400);
  }

  if (error) {
    return json(
      { error: { code: "STAFF_ACCESS_FAILED", message: error.message } },
      error.code === "42501" ? 403 : 400,
    );
  }
  return json({ data, server_authoritative: true });
});
