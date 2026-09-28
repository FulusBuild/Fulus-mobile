-- Bind the verified Edge Function actor before the authoritative return
-- RPC evaluates returns.create. The RPC is service-role-only, so auth.uid()
-- would otherwise refer to the service actor rather than target_user_id.
-- Keep the existing permission check and all financial invariants intact.


