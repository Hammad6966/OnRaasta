# R02 operation and verification

Run `npm test` in `backend`. The default suite uses controlled database fixtures,
real HTTP routes and real Socket.IO handshakes. It never loads application `.env`
or connects to production MongoDB. Node 22+ is needed for the test WebSocket client.

For real database concurrency validation, explicitly set `ONRAASTA_TEST_MONGO_URI`
to an isolated MongoDB replica-set test server and run the suite. This creates and
removes only a randomly named `onraasta_r02_test_*` database. Do not use a production
server. Without this setting the real database test is reported as skipped.

## Database requirements

Bid submission and acceptance now require MongoDB transactions: a replica set or
transaction-capable sharded cluster. Standalone MongoDB is unsupported for these
operations and returns 503; there is no unsafe nontransactional fallback. The
configured application URI uses SRV discovery, but its live topology was not
inspected or modified during development.

Startup builds these non-destructive unique partial indexes before listening:

- `one_pending_bid_per_mechanic`: `(jobId, mechanicId)` where status is `pending`.
- `one_accepted_bid_per_job`: `jobId` where status is `accepted`.

Before rollout, inspect existing duplicate pending/winning bids and job assignments.
Resolve any legacy inconsistencies through an authorized, backed-up migration.
Startup fails if the indexes cannot be created; it does not delete or rewrite data.
The former automatic email-index drop has been removed.

## Authentication and clients

Access tokens carry `tokenUse: access` and last 15 minutes, including admin login.
Refresh tokens carry `tokenUse: refresh` and last seven days. Existing untyped
tokens are intentionally rejected: users/admins must sign in again after rollout.
Refresh rotation and mobile refresh remain R09. Secrets remain environment-owned.

Admin login retains `{success, token, name}`. Other successful API response shapes
are unchanged, including job creation `{success, data: job}` required by R01.
Admin dashboard already sends its Bearer header. Unauthorized clients receive
401/403 instead of previously public data.

Only the owner can cancel before repair starts; admins can cancel any nonterminal
job. Only the assigned approved mechanic advances accepted -> en_route -> arrived
-> in_progress -> completed. Accepted -> arrived remains allowed for current M17.
Terminal jobs cannot reopen. Bid acceptance/creation writes the Job and bids in one
transaction; competing pending bids become declined.

Socket clients keep the existing event names and token handshake. Own personal
rooms are joined server-side. Job room joins are authorized from persisted data.
Client-generated bid/job/status notifications are rejected with `security:error`
and an optional acknowledgment. Tracking/reconnection/acceptance UI wiring is not
added here. Mechanic presence remains in memory, with approval checked again at
dispatch and explicit revocation removing presence.

Set `CORS_ORIGINS` to comma-separated allowed browser origins when deploying;
the default is `http://localhost:3000`. Native mobile clients do not require a
browser Origin. General API limit is 100/15 minutes; shared authentication limit
is 10/15 minutes, including admin login. These limits do not throttle Socket.IO.
Current limiter storage/presence assumes a single backend process.

## Administrative provisioning

Authorized operators may run `node src/scripts/seed_admin.js` with externally
supplied `ADMIN_EMAIL`, `ADMIN_PHONE` (ten digits), `ADMIN_PASSWORD` (12-128
characters), optional `ADMIN_NAME`, and the existing MongoDB configuration.
There are no default credentials; existing accounts are never silently elevated
or overwritten. Rotate any old default-seeded administrator password separately.

Job photo input accepts at most three HTTP(S) URLs. Actual file byte/MIME/5 MB
checks belong to the upload boundary in R10; this JSON API cannot verify remote
file contents. No storage, FCM, payment, tracking or admin-management UI is added.
