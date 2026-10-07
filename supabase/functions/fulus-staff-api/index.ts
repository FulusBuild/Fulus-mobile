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

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: { code: "INVALID_JSON", message: "Request body must be valid JSON" } }, 400);
  }

  const action = body.action;

  // Invite inspection and first-device account preparation are intentionally
  // unauthenticated because a brand-new employee has no session yet. Both
  // actions require the high-entropy invitation token; preparation only
  // creates/recoveries an account with no existing business membership.
  if (action === "inspect_invite") {
    const token = typeof body.token === "string" ? body.token.trim() : "";
    if (!token) {
      return json({ error: { code: "INVALID_REQUEST", message: "Invite token is required" } }, 400);
    }

    const tokenHash = await sha256Hex(token);
    const { data: invite, error: inviteError } = await admin
      .from("staff_invites")
      .select("business_id, invited_email, invited_name, role_id, expires_at, claimed_at, location_id")
      .eq("token_hash", tokenHash)
      .maybeSingle();

    if (inviteError || !invite) {
      return json({ error: { code: "INVALID_INVITE", message: "That invitation is not valid." } }, 404);
    }
    if (invite.claimed_at) {
      return json({ error: { code: "INVITE_CLAIMED", message: "That invitation has already been used." } }, 409);
    }
    if (new Date(invite.expires_at).getTime() <= Date.now()) {
      return json({ error: { code: "INVITE_EXPIRED", message: "That invitation has expired." } }, 410);
    }

    const [{ data: role }, { data: business }] = await Promise.all([
      admin.from("roles").select("name").eq("id", invite.role_id).eq("business_id", invite.business_id).maybeSingle(),
      admin.from("businesses").select("name").eq("id", invite.business_id).maybeSingle(),
    ]);

    if (!role || role.name === "owner") {
      return json({ error: { code: "INVALID_INVITE", message: "That invitation is no longer valid." } }, 404);
    }

    return json({
      data: {
        business_id: invite.business_id,
        business_name: business?.name ?? "your business",
        full_name: invite.invited_name ?? "",
        email: invite.invited_email ?? "",
        role_name: role.name,
        expires_at: invite.expires_at,
        location_id: invite.location_id,
      },
      server_authoritative: true,
    });
  }

  // An invitation is also the authorization for first-device account setup.
  // This action is intentionally unauthenticated because a brand-new employee
  // has no session yet. The high-entropy invite token is the bearer secret.
  // Existing orphan auth accounts (created by an interrupted earlier attempt)
  // can safely recover a password only when they have no business membership.
  if (action === "prepare_invited_account") {
    const token = typeof body.token === "string" ? body.token.trim() : "";
    const password = typeof body.password === "string" ? body.password : "";
    if (!token || password.length < 8) {
      return json({ error: { code: "INVALID_REQUEST", message: "Invite token and a password of at least 8 characters are required" } }, 400);
    }

    const tokenHash = await sha256Hex(token);
    const { data: invite, error: inviteError } = await admin
      .from("staff_invites")
      .select("id, invited_email, expires_at, claimed_at")
      .eq("token_hash", tokenHash)
      .maybeSingle();

    if (inviteError || !invite) {
      return json({ error: { code: "INVALID_INVITE", message: "That invitation is not valid." } }, 404);
    }
    if (invite.claimed_at) {
      return json({ error: { code: "INVITE_CLAIMED", message: "That invitation has already been used." } }, 409);
    }
    if (new Date(invite.expires_at).getTime() <= Date.now()) {
      return json({ error: { code: "INVITE_EXPIRED", message: "That invitation has expired." } }, 410);
    }
    const email = (invite.invited_email ?? "").trim().toLowerCase();
    if (!email) {
      return json({ error: { code: "INVALID_INVITE", message: "That invitation has no employee email." } }, 400);
    }

    let existingUser: { id: string } | null = null;
    for (let page = 1; page <= 20 && !existingUser; page += 1) {
      const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
      if (error) {
        return json({ error: { code: "ACCOUNT_SETUP_FAILED", message: "Unable to prepare the employee login." } }, 500);
      }
      const match = data.users.find((candidate) => (candidate.email ?? "").toLowerCase() === email);
      if (match) existingUser = { id: match.id };
      if (data.users.length < 1000) break;
    }

    if (!existingUser) {
      const { data, error } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
      });
      if (error || !data.user) {
        return json({ error: { code: "ACCOUNT_SETUP_FAILED", message: "Unable to create the employee login." } }, 500);
      }
      return json({ data: { user_id: data.user.id, created: true }, server_authoritative: true });
    }

    const { data: memberships, error: membershipError } = await admin
      .from("business_memberships")
      .select("id")
      .eq("user_id", existingUser.id)
      .limit(1);
    if (membershipError) {
      return json({ error: { code: "ACCOUNT_SETUP_FAILED", message: "Unable to check the existing employee login." } }, 500);
    }
    if ((memberships ?? []).length > 0) {
      return json({ error: { code: "ACCOUNT_ALREADY_LINKED", message: "This Fulus account is already linked to a business." } }, 409);
    }

    const { error: updateError } = await admin.auth.admin.updateUserById(existingUser.id, {
      password,
      email_confirm: true,
    });
    if (updateError) {
      return json({ error: { code: "ACCOUNT_SETUP_FAILED", message: "Unable to prepare the employee login." } }, 500);
    }
    return json({ data: { user_id: existingUser.id, created: false, recovered: true }, server_authoritative: true });
  }

  // Every action after invite inspection requires an authenticated account.
  const auth = req.headers.get("authorization");
  if (!auth?.startsWith("Bearer ")) {
    return json({ error: { code: "UNAUTHENTICATED", message: "Bearer token required" } }, 401);
  }

  const { data: userData, error: userError } = await admin.auth.getUser(auth.slice(7));
  if (userError || !userData.user) {
    return json({ error: { code: "UNAUTHENTICATED", message: "Invalid access token" } }, 401);
  }

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
    if (error.code === "23505" && error.message.includes("business_memberships_one_business_per_user")) {
      return json(
        { error: { code: "BUSINESS_ALREADY_LINKED", message: "This Fulus account is already linked to another business." } },
        409,
      );
    }

    if (error.message !== "Invite already claimed") {
      return json(
        { error: { code: "STAFF_ACCESS_FAILED", message: error.code === "42501" ? "Insufficient permission for this staff action" : "Unable to complete staff action" } },
        error.code === "42501" ? 403 : 400,
      );
    }

    const tokenHash = await sha256Hex(token);
    const { data: invite, error: inviteError } = await admin
      .from("staff_invites")
      .select("business_id,role_id,invited_email,claimed_by,expires_at,location_id")
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

    const { data: locationMemberships } = invite.location_id
      ? { data: [{ location_id: invite.location_id }] }
      : await admin
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

  if (action === "get_my_access") {
    const businessId = typeof body.business_id === "string" ? body.business_id.trim() : "";
    if (!businessId) {
      return json({ error: { code: "INVALID_REQUEST", message: "business_id is required" } }, 400);
    }

    const { data: membership, error: membershipError } = await admin
      .from("business_memberships")
      .select("id,user_id,role_id,status,permissions_overridden,roles(name)")
      .eq("business_id", businessId)
      .eq("user_id", userData.user.id)
      .eq("status", "active")
      .maybeSingle();

    if (membershipError) {
      return json({ error: { code: "AUTHORIZATION_CHECK_FAILED", message: "Unable to resolve employee access" } }, 500);
    }
    if (!membership) {
      return json({ error: { code: "NOT_ACTIVE_MEMBER", message: "You are not an active member of this business" } }, 403);
    }

    const roleName = (membership.roles as { name?: string } | null)?.name ?? "employee";
    const { data: profile } = await admin
      .from("profiles")
      .select("full_name")
      .eq("id", userData.user.id)
      .maybeSingle();

    const { data: employee } = await admin
      .from("employees")
      .select("*")
      .eq("business_id", businessId)
      .eq("auth_user_id", userData.user.id)
      .maybeSingle();

    const { data: locationMemberships } = await admin
      .from("location_memberships")
      .select("location_id")
      .eq("business_id", businessId)
      .eq("user_id", userData.user.id)
      .eq("status", "active")
      .order("created_at", { ascending: true })
      .limit(1);

    let permissionCodes: string[] = [];
    if (membership.permissions_overridden) {
      const { data: rows } = await admin
        .from("business_member_permissions")
        .select("permissions(code)")
        .eq("business_id", businessId)
        .eq("user_id", userData.user.id);
      permissionCodes = (rows ?? [])
        .map((row) => (row.permissions as { code?: string } | null)?.code)
        .filter((code): code is string => typeof code === "string");
    } else {
      const { data: rows } = await admin
        .from("role_permissions")
        .select("permissions(code)")
        .eq("role_id", membership.role_id);
      permissionCodes = (rows ?? [])
        .map((row) => (row.permissions as { code?: string } | null)?.code)
        .filter((code): code is string => typeof code === "string");
    }

    return json({
      data: {
        business_id: businessId,
        membership_id: membership.id,
        user_id: userData.user.id,
        role_id: membership.role_id,
        role_name: roleName,
        full_name: profile?.full_name ?? "",
        email: userData.user.email ?? "",
        location_id: locationMemberships?.[0]?.location_id ?? employee?.location_id ?? null,
        permission_codes: permissionCodes,
        employee_id: employee?.id ?? null,
        employee: employee ?? null,
      },
      server_authoritative: true,
    });
  }

  const resolveUserIdByEmail = async (email: string): Promise<string | null> => {
    const normalized = email.trim().toLowerCase();
    if (!normalized) return null;
    for (let page = 1; page <= 20; page += 1) {
      const { data, error } = await admin.auth.admin.listUsers({
        page,
        perPage: 1000,
      });
      if (error) return null;
      const match = data.users.find(
        (candidate) => (candidate.email ?? "").toLowerCase() === normalized,
      );
      if (match) return match.id;
      if (data.users.length < 1000) break;
    }
    return null;
  };

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
  const { data: canManageStaff, error: staffPermissionError } = await admin.rpc(
    "staff_actor_has_permission",
    {
      target_business_id: businessId,
      target_actor_user_id: userData.user.id,
      target_permission_code: "employees.manage",
    },
  );
  if (staffPermissionError) {
    return json({ error: { code: "AUTHORIZATION_CHECK_FAILED", message: "Unable to resolve staff access" } }, 500);
  }
  const managerDelegableActions = new Set([
    "create_invite",
    "set_member_permissions",
    "set_member_status",
    "set_member_status_by_user",
    "set_member_status_by_email",
    "revoke_pending_invites_by_email",
  ]);
  const canManageEmployees =
    isAdmin ||
    (canManageStaff === true && managerDelegableActions.has(String(action)));

  // Device inventory is an administrator-only surface. `employees.manage`
  // authorizes staff roster/access changes, not visibility into every device
  // registered to the business. Keep this boundary explicit because this
  // Edge Function uses the service-role client for its data reads.
  if (action === "list_devices" && !isAdmin) {
    return json({ error: { code: "FORBIDDEN", message: "Owner or admin access is required for device management" } }, 403);
  }
  if (!canManageEmployees) {
    return json({ error: { code: "FORBIDDEN", message: "Owner or admin access is required for this action" } }, 403);
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
      const invitedName = typeof body.invited_name === "string" ? body.invited_name.trim() : "";
      const employeeClientReference = typeof body.employee_client_reference === "string" ? body.employee_client_reference.trim() : null;
      const employee = body.employee && typeof body.employee === "object" ? body.employee as Record<string, unknown> : null;

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
        target_employee_client_reference: employeeClientReference,
        target_employee: employee,
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

    case "set_member_status": {
      ({ data, error } = await admin.rpc("set_member_status", {
        target_business_id: businessId,
        target_membership_id: body.membership_id,
        target_status: body.status,
        target_user_id: userData.user.id,
      }));
      break;
    }

    case "revoke_pending_invites_by_email": {
      const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
      if (!email) {
        return json({ error: { code: "INVALID_REQUEST", message: "Employee email is required" } }, 400);
      }

      if (!isAdmin) {
        const { data: pendingInvites, error: pendingInviteError } = await admin
          .from("staff_invites")
          .select("location_id")
          .eq("business_id", businessId)
          .eq("invited_email", email)
          .is("claimed_at", null)
          .gt("expires_at", new Date().toISOString());
        if (pendingInviteError) {
          return json({ error: { code: "STAFF_ACCESS_FAILED", message: "Unable to resolve pending invitation" } }, 500);
        }
        for (const invite of pendingInvites ?? []) {
          if (!invite.location_id) continue;
          const { data: locationAccess, error: locationError } = await admin
            .from("location_memberships")
            .select("id")
            .eq("business_id", businessId)
            .eq("user_id", userData.user.id)
            .eq("location_id", invite.location_id)
            .eq("status", "active")
            .maybeSingle();
          if (locationError) {
            return json({ error: { code: "AUTHORIZATION_CHECK_FAILED", message: "Unable to resolve employee location access" } }, 500);
          }
          if (!locationAccess) {
            return json({ error: { code: "FORBIDDEN", message: "You do not have access to this employee location" } }, 403);
          }
        }
      }

      const { error: revokeError } = await admin
        .from("staff_invites")
        .update({ expires_at: new Date().toISOString(), updated_at: new Date().toISOString() })
        .eq("business_id", businessId)
        .eq("invited_email", email)
        .is("claimed_at", null)
        .gt("expires_at", new Date().toISOString());
      if (revokeError) {
        return json({ error: { code: "STAFF_ACCESS_FAILED", message: "Unable to revoke pending invitations" } }, 500);
      }
      data = true;
      break;
    }

    case "set_member_status_by_email": {
      const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
      const targetUserId = await resolveUserIdByEmail(email);
      if (!targetUserId) {
        return json({ error: { code: "INVALID_REQUEST", message: "Employee login account not found yet" } }, 404);
      }
      const { data: targetMembership, error: targetMembershipError } = await admin
        .from("business_memberships")
        .select("id")
        .eq("business_id", businessId)
        .eq("user_id", targetUserId)
        .maybeSingle();
      if (targetMembershipError) {
        return json({ error: { code: "STAFF_ACCESS_FAILED", message: "Unable to resolve staff membership" } }, 500);
      }
      if (!targetMembership) {
        return json({ error: { code: "INVALID_REQUEST", message: "Employee has not joined this business yet" } }, 404);
      }
      ({ data, error } = await admin.rpc("set_member_status", {
        target_business_id: businessId,
        target_membership_id: targetMembership.id,
        target_status: body.status,
        target_user_id: userData.user.id,
      }));
      break;
    }

    case "set_member_status_by_user": {
      const targetUserId = typeof body.user_id === "string" ? body.user_id : "";
      const { data: targetMembership, error: targetMembershipError } = await admin
        .from("business_memberships")
        .select("id")
        .eq("business_id", businessId)
        .eq("user_id", targetUserId)
        .maybeSingle();
      if (targetMembershipError) {
        return json({ error: { code: "STAFF_ACCESS_FAILED", message: "Unable to resolve staff membership" } }, 500);
      }
      if (!targetMembership) {
        return json({ error: { code: "INVALID_REQUEST", message: "Active staff membership not found" } }, 404);
      }
      ({ data, error } = await admin.rpc("set_member_status", {
        target_business_id: businessId,
        target_membership_id: targetMembership.id,
        target_status: body.status,
        target_user_id: userData.user.id,
      }));
      break;
    }

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
      { error: { code: "STAFF_ACCESS_FAILED", message: error.code === "42501" ? "Insufficient permission for this staff action" : "Unable to complete staff action" } },
      error.code === "42501" ? 403 : 400,
    );
  }
  return json({ data, server_authoritative: true });
});
