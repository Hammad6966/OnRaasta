# R15 — Account administration and manual mechanic approval

## Scope and security

R15 adds persisted administration to the existing Express/Mongoose and Next.js
applications. JWT purpose/account/role checks, 15-minute access tokens, admin
login rate limits and operator-only admin provisioning are preserved. Public
registration still cannot create administrators. There are no browser refresh
credentials; only the existing tab-scoped access token is retained.

Storage/uploads, FCM, analytics/disputes, payment processing and OBD-II remain
deferred. Analytics and Disputes pages retain their honest placeholders.

## API contracts

Every route below requires a current active, verified admin account and valid
admin access JWT. Responses use `{success:true,data}`; lists add
`pagination:{page,limit,total,hasMore}`. Errors use the existing safe middleware.

| Method/path under `/api/admin` | Contract |
| --- | --- |
| POST `/login` | Existing validated/rate-limited email/password login; `{success,token,name}` remains unchanged |
| GET `/users` | Driver/mechanic summaries; `page`, `limit`, `search`, `role=user|mechanic`, `active=true|false`, `approval=pending|approved|rejected|revoked` |
| GET `/users/:id` | Safe account detail plus linked safe mechanic summary; admin accounts are excluded |
| PATCH `/users/:id/status` | Strict `{isActive:boolean,expectedVersion:integer,reason:string}` |
| GET `/verification` | Mechanic application summaries, linked safe account, pagination and global `counts`; supports `page`, `limit`, `search`, `active`, `approval` |
| PATCH `/verification/:mechanicId` | Strict `{action:"approve"|"reject"|"revoke",expectedVersion:integer,reason:string}`; manual account approval only |
| GET `/audit-logs` | Protected, read-only audit listing; `page`, `limit`, optional `targetId` |
| GET `/stats` | Persisted role/eligibility/status counts and R12 booked financial totals |
| GET `/jobs-chart`, `/faults-chart`, `/recent-jobs` | Existing protected chart/recent-job contracts retained |

ID parameters are validated. Reasons are required for every mutation, trimmed,
3–500 characters, and reject control characters/angle brackets. The verified JWT
determines actor identity; role/credential/actor mass assignment is rejected.
Malformed requests return 400; authentication 401; forbidden access 403; missing
targets 404; stale/repeated/invalid state transitions 409. Unsupported transaction
deployment fails closed (503), never falls back to partial multi-document writes.

Pages default to 20 records, allow at most 50, and cap page at 200. Search is a
literal, escaped case-insensitive prefix of name/email/phone, at most 80 chars.
Unknown query parameters and object/array injection are rejected. Approval-filtered
account lookup and searched application-account lookup cap intermediate matches
at 1,000 and ask the operator to narrow the search rather than truncate silently.
Global count/statistics computations stream persisted records; these may need
aggregation optimization for much larger deployments.

Safe responses whitelist profile fields and omit password hashes, login attempts,
lockouts, OTPs, refresh records, emergency contacts, CNIC/permit URLs and document
contents. Mechanic `documents` exposes only recorded status, a boolean indicating
complete CNIC reference availability, and `verificationAvailable:false`. This
boolean does not assert that a file was inspected or is authentic.

## Account status and authorization

Only driver/mechanic accounts can be suspended/reactivated. Ordinary management
cannot mutate the current or any other admin account. Suspension persists
`User.isActive=false`, invalidates all current refresh sessions, and updates the
linked mechanic in the same transaction. Historical jobs, assignment ownership,
bids, reviews and accounting snapshots are untouched. Reactivation restores
account activity, never a previously revoked refresh session or online presence.

After commit, suspension synchronously removes local presence and disconnects
all sockets for that account in all local namespaces. Persisted account checks
continue to reject protected HTTP, refresh, socket operations and GPS publication.
The existing dispatch/bidding/recommendation eligibility checks remain final
authorities. In-memory socket/presence invalidation is process-local; multiple
instances require distributed invalidation infrastructure before claiming prompt
cross-instance disconnection. Persisted authorization remains authoritative.

## Manual approval policy and document deferral

`Mechanic.isApproved` remains the existing eligibility flag. The additive
`approval` metadata contains `status` (pending/approved/rejected/revoked),
`method:"manual_profile_review"`, `decidedBy`, `decidedAt`, and `reason`.
Read responses expose `accountApprovalStatus` separately from `documents.status`.

- Pending, rejected or revoked applications can be approved after manual profile
  review only while the linked mechanic account is active and phone-verified.
- Only pending applications can be rejected; rejection requires a reason.
- Only approved mechanics can have approval revoked; revocation requires a reason.
- Repeated or stale decisions conflict rather than create duplicate actions.
- Existing approvals remain recognized through `isApproved`; absent historical
  decision metadata is not manufactured. An unapproved legacy profile without an
  explicit account decision needs manual review (pending), independently of any
  recorded document rejection.
- R11 skill changes still revoke approval and reset account approval to pending.
  Existing document evidence/status is now preserved independently. Version checks
  prevent an administrator from approving a stale qualification snapshot.

No manual action writes document status, uploads images, marks missing documents
verified, or invents verification timestamps. The old PATCH input
`{status:"verified"|"rejected",rejectionReason}` is deliberately rejected with 400;
all current admin consumers use the explicit account-action contract. The route
path is preserved. Actual document review remains unavailable.

Revocation immediately removes presence and prunes unauthorized private job rooms.
After commit, `mechanic:approval_changed` is emitted only to the mechanic's
authenticated `user_<userId>` room with
`{mechanicId,isApproved,accountApprovalStatus}`. Clients cannot forge this event.
It contains no document/account records. Flutter reloads the owning profile,
stops revoked availability and cleans up its individual listener. Toggle,
reconnect and resume continue to recheck server state even if the event was missed.
The profile UI displays rejection/revocation separately from document status.

## Atomicity and audit records

AdminLog stores only server-derived actor ID, target ID/type, action, bounded
previous/next state (activity/approval only), reason and server timestamp. Schema
validation is strict and fields are immutable through ordinary Mongoose document
updates. No ordinary update/delete log API exists. Read access is admin-only and
bounded by the pagination limits above. Logs are retained for administrative
traceability; R15 adds no automatic destructive TTL cleanup. Operators should
define archival/retention policy before production growth requires it.

Each mutation uses a MongoDB transaction containing an active-admin write lock,
target User/Mechanic writes, refresh revocation when applicable and audit insert.
The existing `__v` field is returned as `revision`; the client must submit it as
`expectedVersion`. Transaction retries rerun validation; compare-and-set filters
and write conflicts serialize stale decisions, suspension, critical profile edits
and existing transactional assignment operations. Bid submission and acceptance
add an account-state write lock inside the existing transactions, closing the
in-flight authentication/suspension window without changing winner selection or
response contracts. An audit insert failure rolls
back the administrative state. Notifications are post-commit, best effort; reload
uses MongoDB as source of truth. There is no successful notification before commit.

## Next.js behavior

Users and Verification use a shared management component with real listings,
prefix search, filters, pagination, safe detail, recent target audit history and a
reasoned confirmation form. Duplicate mutation taps are blocked synchronously.
Errors retain form input where recoverable; 404/409 close stale detail and refresh
the listing. Success appears only after the server confirms commit. Loading,
failure/retry and empty states are explicit. Generation/unmount guards prevent
older results from replacing newer pages or reopening stale details.

The centralized API helper sends the current tab token, disables response caching,
handles 401/403 by clearing credentials and requiring login, preserves sessions
on network/400/404/409/503 errors, and never automatically repeats mutations.
Token identity is rechecked after transport and JSON parsing. Login also rejects
late results after unmount/account change. The shell checks expiry on entry,
focus and an expiry timer; it provides explicit sign-out. No long-lived browser
refresh token is introduced. Signature and live account validation stay server-side.

The existing dark design tokens and navigation remain. Dashboard cards now label
registered drivers, approved active/verified mechanics and pending profile reviews
accurately. `jobsByStatus` uses all eight canonical statuses; assigned active counts
include arrived. R12 exact paisa summaries provide gross booked amount and booked
commission, never cash collected. Legacy completed jobs lacking valid financial
snapshots are excluded from priced totals and their count is displayed. Actual
charts/recent jobs remain; no fabricated growth/activity was added.

## Deployment and indexes

Transactions require the same replica-set/sharded transaction-capable MongoDB
deployment as R02–R12. Startup additively creates the AdminLog collection and its
indexes before listening; collection creation is not attempted inside a mutation.
No live initialization, migration, reset or production write was run here.

Additive indexes are declared for User `(role,createdAt,_id)`, Mechanic
`(isApproved,approval.status,createdAt,_id)`, and AdminLog `(createdAt,_id)` plus
`(targetId,createdAt)`. Review/create User/Mechanic indexes explicitly when
production disables Mongoose auto-indexing. No `syncIndexes`, index drops or data
backfill is performed. Legacy approval metadata can remain absent.

Set `NEXT_PUBLIC_ADMIN_API_URL` at admin build time to the HTTPS admin API base
(including `/api/admin`) in deployment; localhost:5000 is the existing development
default. Keep CORS origins configured for the actual admin origin. Use the
existing operator-controlled seed script to provision admins; no default
credentials or environment values were added or changed.

## Exact R15 file manifest

- `backend/src/models/AdminLog.js`
- `backend/src/models/Mechanic.js`
- `backend/src/models/User.js`
- `backend/src/services/admin.service.js`
- `backend/src/services/access.service.js`
- `backend/src/controllers/bids.controller.js`
- `backend/src/utils/profile-policy.js`
- `backend/src/routes/admin.routes.js`
- `backend/src/controllers/mechanics.controller.js`
- `backend/src/socket/socket.js`
- `backend/src/index.js`
- `backend/test/admin.test.js`
- `backend/test/fixtures.js`
- `backend/test/security.test.js`
- `backend/test/mongo-concurrency.test.js`
- `backend/ADMIN_R15.md`
- `admin/lib/admin-api.ts`
- `admin/lib/types.ts`
- `admin/app/components/account-management.tsx`
- `admin/app/users/page.tsx`
- `admin/app/verification/page.tsx`
- `admin/app/page.tsx`
- `admin/app/layout.tsx`
- `admin/app/login/page.tsx`
- `admin/test/admin-api.test.ts`
- `mobile/lib/providers/mechanic_presence_controller.dart`
- `mobile/lib/features/mechanic/mechanic_profile_edit.dart`
- `mobile/test/mechanic_presence_test.dart`
- `mobile/test/profile_test.dart`

Existing security rejection tests now use explicit reasoned account revocation,
and count actual dispatch events independently of the new private approval hint.
The Mongo integration test is preserved and extended with admin decision and
audit conflict assertions. Its safe isolated replica-set requirement is unchanged.

## Validation

Final results (2026-10-18):

| Check | Result |
| --- | --- |
| Full backend suite, local FastAPI HTTP enabled | 234 passed, 0 failed, 1 isolated MongoDB integration test skipped; 25 new R15 tests |
| Admin TypeScript | Passed (`tsc --noEmit --incremental false`) |
| Admin API/session tests | 12 passed, 0 failed |
| Full Flutter suite | 387 passed, 0 failed; 3 new R15 tests |
| Flutter analysis | 0 errors, 0 warnings; the same 66 pre-existing informational diagnostics (analyzer exits 1 for infos) |
| JavaScript syntax | 57 source/test files passed |
| `git diff --check` | Passed; existing Git LF/CRLF conversion notices remain |

The first parallel full backend run had one existing local FastAPI fixture
startup timeout (8-second deadline). Subsequent full reruns passed, including the
local HTTP integration. No production recommendation logic was changed to mask
that timeout. The real MongoDB integration test remains skipped without an
explicit safe isolated replica-set URI; its R15 assertions have not been executed.

Tests cover authorization, redaction, literal search/pagination/filtering,
suspension/reactivation, refresh revocation, presence/socket invalidation, manual
decisions, legacy document independence, critical skill edits, concurrent admin
conflicts, audit rollback/actor/time, canonical dashboard counts, R12 money,
in-flight bidding suspension guards, session expiry/account switching, and mobile
approval display/listener cleanup. Tests use controlled fixtures and never
production records. Lightweight admin tests compile with the
existing TypeScript compiler and run through Node's built-in test runner; no
frontend framework or dependency was added.

Reproduce admin service tests from `admin`:

```powershell
./node_modules/.bin/tsc --module commonjs --moduleResolution node --target es2020 --esModuleInterop --outDir .r15-test-build --skipLibCheck test/admin-api.test.ts lib/admin-api.ts
node --test .r15-test-build/test/admin-api.test.js
```

Backend regressions run through `npm test` in `backend`; set
`ONRAASTA_TEST_AI_HTTP=true` to include the controlled local Node/FastAPI HTTP
fixture. Flutter regressions run through `flutter test --no-pub` in `mobile`.

Real MongoDB transaction/index verification, rendered browser workflows,
physical-phone behavior and two-device testing remain UNVERIFIED.
