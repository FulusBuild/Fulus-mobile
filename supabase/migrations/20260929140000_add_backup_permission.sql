-- Add a distinct cloud capability for Backup & Restore.
-- business.manage is broader than backup access, so using it for the local
-- manageBackup permission would overgrant Settings after a cross-device restore.

insert into public.permissions (code, description)
values ('backup.manage', 'Backup and restore business data')
on conflict (code) do nothing;
