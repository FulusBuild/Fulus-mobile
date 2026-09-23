# Fulus AI Engineering Standard

## Purpose

Fulus is business-critical software. AI-assisted development must optimize for correctness, data integrity, recoverability, maintainability, and real-world usability—not merely code that compiles.

The product owner is not a software engineer. AI sessions are responsible for technical investigation, implementation, testing, and evidence, while explaining important conclusions in plain business language.

## Non-negotiable rules

1. Never assume previous AI-generated work is correct.
2. Inspect the actual repository before making technical claims.
3. Do not declare a feature or phase complete merely because code compiles or CI is green.
4. Preserve existing working functionality unless a change is explicitly required.
5. Avoid destructive changes and unnecessary rewrites.
6. Prefer small, reversible, well-tested changes.
7. For business-critical data, never silently lose, duplicate, overwrite, or falsely report data.
8. Test normal behavior and failure behavior.
9. Treat offline operation, retries, app crashes, restarts, migrations, backup/restore, synchronization, concurrency, and recovery as first-class concerns where relevant.
10. When a real defect is found, fix it, add regression coverage, validate it, and attempt to break the fix again.
11. Distinguish proven facts, plausible risks, and untested areas.
12. Never manufacture certainty. If something is unproven, say so.

## Business-critical invariants

Discover the complete set from the repository, but at minimum verify that:

- A completed sale cannot silently disappear.
- A business transaction cannot be counted twice.
- Stock changes have legitimate causes and remain consistent with transactions.
- Money records and balances remain consistent.
- Customer credit balances remain correct.
- Reports reconcile with underlying business records.
- A successful local transaction remains durable when cloud sync fails.
- Sync retries cannot duplicate business transactions.
- The UI does not falsely claim that an operation succeeded or is synced.
- Valid backups can be restored without silent data loss or corruption.

## Required engineering loop

For important work:

1. Understand the requirement and business consequence.
2. Inspect the actual implementation.
3. Identify failure modes and invariants.
4. Implement the smallest robust change.
5. Add or update tests.
6. Run relevant validation and CI.
7. Inspect the final diff for unintended changes.
8. Perform an adversarial review.
9. Report what is proven, what remains uncertain, and any accepted limitations.

## Communication

For important findings, use:

**BUSINESS IMPACT** — what could happen to a real business.

**WHAT WAS FOUND** — what the code actually does.

**WHAT CHANGED** — what was fixed or deliberately left unchanged.

**PROOF** — tests, CI, reproduction, or other evidence.

**REMAINING RISK** — what is still uncertain.

Do not flatter the product owner or optimize for reassurance. Optimize for evidence and trustworthy software.
