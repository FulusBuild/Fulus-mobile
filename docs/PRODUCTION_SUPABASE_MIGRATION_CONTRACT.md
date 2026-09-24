# Production Supabase Migration Contract

Fulus production schema changes are migration-driven.

## Authoritative source

The repository `supabase/migrations/` directory is the canonical migration chain.

The production project's `supabase_migrations.schema_migrations` table must contain only migration versions and names from the repository chain, in the same order. Before deployment, production history must be an exact prefix of the repository chain; after deployment, it must exactly match the repository chain.

Supabase tracks migration identity by timestamp/version, so a migration that has the same SQL but a different timestamp is still a different migration to the CLI. The repository and production history therefore must not be allowed to drift.

## Deployment

Production migrations are deployed only by:

`.github/workflows/supabase-production-migrations.yml`

The workflow:

1. validates required Supabase credentials;
2. links the production project;
3. verifies production migration history is an exact prefix of the repository chain (no drift or unknown migrations);
4. runs `supabase db push --dry-run`;
5. applies `supabase db push`;
6. verifies history equality again.

The deployment job uses the `production` GitHub environment so repository protection/required reviewers can be applied there.

## Important safety rule

Do not use `supabase db push --include-all` against production to bypass a migration-history mismatch.

A mismatch means the repository and production may have different migration identities. Repair the history only after proving the underlying production schema already represents the intended state. Supabase documents `migration repair` as a history-only operation; it does not execute or undo SQL.

## Fresh-schema verification

`.github/workflows/supabase-migrations.yml` remains responsible for rebuilding the schema from zero.

A green fresh replay proves repository reproducibility. It does not, by itself, prove production equivalence.

Production history verification and production schema-diff verification are separate controls.
