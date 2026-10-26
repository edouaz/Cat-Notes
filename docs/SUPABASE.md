# Supabase — configuration and validation

The cloud integration has not been tested against a live service. No development project, accounts or credentials were available for that validation. Local notebooks work without this configuration.

## Development setup

1. Create a development Supabase project. Enable email/password authentication and configure email confirmation as appropriate.
2. Apply `supabase/migrations/202610210001_notebooks.sql` using the SQL editor or Supabase CLI. The migration is not idempotent; do not apply it twice.
3. Copy `Config/Supabase.example.plist` to `Config/Supabase.plist` (ignored by Git). Set the HTTPS project URL and **only a publishable key**, or a legacy JWT with the `anon` role. The configuration loader rejects secret keys and privileged-role JWTs.
4. Run `python3 scripts/generate-project.py` to include the local configuration, then rebuild the app.
5. In the account and cloud screen, create/confirm an account, sign in and explicitly link the library. A local library is linked to one account to avoid uploading one person's documents to another account after switching sessions.

Session tokens are stored in the device-only Keychain and become accessible after the first device unlock. Passwords and tokens are not logged. Signing out clears the local session; it does not delete notebooks. The existing Keychain service identifier is retained across the OpenNotes rename so updates can access the previous session.

## Data and recovery

- The private `notebooks` bucket stores native documents, including drawings and source PDFs. The initial storage object limit is 150 MiB; local imports are limited to 150 MB.
- Postgres stores notebook, revision and parent identifiers, SHA-256 values, object paths and timestamps. It does not store binary document data.
- Revisions and their Storage objects are immutable. No UPDATE/DELETE policy is enabled. Only the owner can read or insert their data.
- Saved local metadata provides the upload queue: the modified date and then checksum are compared with the locally retained sync state. The client checks every 30 seconds **while in the foreground**, and resumes on the next foreground transition or launch. Writing never waits for the network. Background transfer while iOS suspends the app is not guaranteed.
- The object is uploaded before the revision row. An interruption between these operations can leave an orphaned object; server maintenance is needed before production use.
- An unknown remote revision is imported with new local identifiers, without replacing a notebook. When versions diverge, both remain, and the remote copy is named accordingly. Merging and grouping a remote revision history into one notebook are still unfinished; this conservative protocol creates copies of updates from another device.
- An imported notebook becomes visible only after all its resources have been written. A concurrent local mutation cancels publication and preserves local data. Orphaned resources can remain on disk without appearing in the library.

**This is an experimental, non-overwriting cloud prototype, not validated production synchronization.** Interrupted transfers, retries, revision deduplication, session renewal, multiple-device conflicts and pagination still need automated tests against a real service. Tracking state uses UserDefaults and is not transactional with the library: a sudden stop may create an extra copy instead of replacing the original.

## Previously executed local SQL validation

`python3 scripts/test-rls-local.py` previously passed on PostgreSQL 16.14 in a disposable cluster using a Unix socket, without a network listener; the cluster was removed afterward. The script applies the real migration and checks owner/A/B access in both directions: owner SELECT/INSERT, cross-account invisibility and insert rejection, immutable metadata and files, and rejection of anonymous access.

The `auth` and `storage` schemas/functions are minimal stubs. This does not test Supabase Auth, the Storage HTTP API, service limits or policies already present in a real project.

## Two-account isolation test against Supabase

Use a **disposable** project and create/confirm two different users. Set these environment variables:

```text
SUPABASE_URL
SUPABASE_PUBLISHABLE_KEY
TEST_A_EMAIL
TEST_A_PASSWORD
TEST_B_EMAIL
TEST_B_PASSWORD
```

Run `python3 scripts/check-rls.py`. The script does not log secrets. It checks owner upload/read in both directions, invisibility of the other user's metadata, rejection of downloads of the other user's binary data, rejection of updates and owner impersonation. It deliberately leaves immutable fixtures in the disposable project. These HTTP assertions have not been run because test accounts were not available.

Review the policies alongside any already present in an existing project: additional permissive policies can widen access. Verify anonymous access after deployment as well.

References originally consulted on 21 October 2026: [row-level security](https://supabase.com/docs/guides/database/postgres/row-level-security), [Storage upload](https://supabase.com/docs/reference/swift/storage-from-upload). Check [current quotas and pricing](https://supabase.com/pricing) before operating a live service; no assumption of free service at scale is made.
