# R06: authoritative repair lifecycle

## Existing schema and resulting transitions

Job.status remains exactly: `pending`, `bidding`, `accepted`, `en_route`, `arrived`, `in_progress`, `completed`, `cancelled`. Breakdown creation persists pending; bidding persists bidding; R02/R05 transactional acceptance persists accepted. Bid.status remains pending/accepted/declined/expired; its indexes and acceptance transaction are unchanged.

Repair mutations now require **accepted → en_route → arrived → in_progress → completed**, one explicit mechanic action at a time. The legacy controller shortcut accepted → arrived was justified only by an older UI comment, not a specification; R05 already provides Start travel. R06 removes that shortcut. Two existing security tests were updated to require the complete sequence and to race the first legal step; their security/concurrency assertions remain.

Only the assigned approved mechanic, with a current active/verified mechanic User, can advance repair stages. Driver cancellation remains allowed from pending/bidding/accepted/en_route; admin cancellation remains allowed from any nonterminal state. Mechanics cannot cancel through this endpoint. Completed/cancelled cannot reopen, cancel again, or repeat completion.

## API and atomicity

`PATCH /api/jobs/:id/status` keeps `{success:true,job:<persisted Job>}`.

Request body supports:

```json
{"status":"arrived","expectedStatus":"en_route","expectedVersion":1}
```

`status` is required. Expected state/version are optional for existing consumers; updated Flutter supplies its confirmed snapshot (version when present). All other body fields, including identities, finalCost and milestone metadata, are rejected. Bad body/ID:400; missing/invalid authentication:401; unauthorized/inactive/rejected account:403; missing Job:404; stale, skipped, backwards, repeated or terminal transitions:409.

The lifecycle service captures the initial Job snapshot outside the transaction retry callback. Within a MongoDB transaction it verifies and writes the active/verified User guard and approved Mechanic guard, verifies assignment again, and conditionally updates the Job using its status, version and assignment IDs. Transaction retry cannot reinterpret the original snapshot as permission for another stage. Concurrent account/approval changes conflict with those guarded writes. Losing/stale requests return 409 and require reconciliation. There is no nontransactional fallback.

New additive Job fields:

- statusVersion: number, default 0; increments once per successful status mutation.
- statusChangedAt: timestamp of that mutation.
- enRouteAt, arrivedAt, startedAt, completedAt, cancelledAt: optional milestone dates set by the server when reached.

Existing Jobs missing statusVersion are treated as zero, with missing-field support in the update predicate. Historical milestone dates are not fabricated. No backfill, destructive migration or new index is required. Existing Mongoose updatedAt continues to be maintained. Transactions require the same supported replica-set/sharded MongoDB deployment already required by R02/R05 acceptance.

Retries are deliberately deterministic **409 conflicts**, not repeated successful mutations. Milestones/version are not written twice. Accepted labour/parts/total/ETA and Job.finalCost are preserved. Completion does not mutate mechanic earnings, commission totals or totalJobs; R12 remains responsible for consistent aggregation. Displayed commission remains 15%, mechanic net 85%, with external payment.

## Realtime contract

Server-only `job:status_changed` is published after the transaction commits and the session ends:

```text
{jobId, status, version: statusVersion, changedAt: statusChangedAt,
 updatedAt: <when available>}
```

Only the owning driver's authenticated user_<userId> room and the assigned mechanic's authenticated user_<mechanicUserId> room receive this hint. Live account state and mechanic approval are rechecked before publishing; stale room members are removed/disconnected. A union room emit gives one delivery per socket, even when job/personal memberships overlap. Clients cannot forge the event. No customer/profile/price/document/security data is sent. Publication does not depend on joining a job room during navigation. Private job-room authorization remains intact.

Publication failure cannot turn a committed status into an apparent HTTP failure. Socket delivery remains best effort, not a durable event log. HTTP reads are authoritative.

## Flutter behavior and recovery

R05 AssignmentDetailController owns synchronized booking state for mechanic Active Job, driver Live Tracking, and driver Job In Progress. It filters status notifications by Job ID, ignores already confirmed older/equal versions, and fetches the authenticated assignment instead of applying event status directly. Bursts during a read queue another reconciliation. HTTP generations, session guards and persisted-version checks prevent stale responses from overwriting newer state. Listeners are removed individually.

Mechanic Active Job shows only the next legal action. Pending requests disable repeated taps; state changes only after persisted confirmation. Conflicts/network errors reconcile and expose retry; 401/403 invalidate privileged display/actions. All three screens reload on foreground resume and socket reconnect, and use the same typed AcceptedBooking IDs/prices. No timers advance lifecycle state.

Live Tracking replaces itself once with `/job-in-progress` only after an authenticated read confirms in_progress/completed. Unrelated, duplicate and out-of-order hints cannot independently navigate or claim arrival. Job In Progress retains its map/cards/theme but removes local progress buttons, fake GPS/movement, invented prices/ratings, and blanket socket-listener removal. It displays the saved breakdown marker only; live mechanic location is honestly unavailable until R07. Cancelled/completed states are explicit.

Review navigation is enabled only for confirmed completed work and rechecks the persisted assignment on tap. The typed `/rate-review` route bridge preserves Job/Bid/Mechanic IDs and agreed component prices for the existing form. Full review submission is R08; its existing token handling/submission implementation is unchanged by R06.

Both home inboxes reconcile status changes and remove terminal Jobs from their active list. In-flight completion hints are queued rather than lost. Closed state cannot be reopened by a stale list response. An additive `GET /api/jobs/assignments?includeClosed=true` recovery option returns all owned active assignments plus at most ten recent owned completed/cancelled assignments. Default `/assignments` remains active-only. Approval and ownership checks/projections apply equally to closed reads. Homes use this option and explicitly mark closed entries, allowing completion while offline to be reopened after restart without resurrecting an active job. This is bounded recovery, not a replacement for the full job-history module.

## Verification

Controlled backend and Flutter fixtures cover the state machine, milestone/version persistence, protected input, role/account/approval rejection, cancellation, terminal/repeated/concurrent updates, rollback/no events, post-commit publication failure, intended recipients, missed-event recovery, room/event security, API/socket races, listener cleanup, stale/duplicate events, explicit mechanic actions, driver navigation, completion-gated review, and closed-job restart recovery. R01–R05 suites and the isolated MongoDB transaction test are retained.

Validation: all 200 Flutter tests passed (171 prior regressions plus 29 R06 tests); all 88 controlled backend tests passed (62 prior plus 26 R06 tests), with one isolated MongoDB transaction integration test skipped. All 39 JavaScript source/test files passed syntax checks. Flutter analysis has zero errors and no new diagnostics, but exits nonzero with the existing 90 diagnostics (one warning, 89 info). `git diff --check` passed.

The real MongoDB transaction test remains skipped without an isolated ONRAASTA_TEST_MONGO_URI. Physical-device/multiple-phone, deployment reconnection and live replica-set status contention remain unverified. Presence/rooms are process-local; multi-instance transport coordination and durable event replay are not introduced. R07 tracking, R08 review submission and R12 earnings aggregation remain separate work.

## Exact R06 file manifest

- backend/src/controllers/jobs.controller.js
- backend/src/models/Job.js
- backend/src/middleware/request-validation.js
- backend/src/services/job-lifecycle.service.js
- backend/src/services/assignment.service.js
- backend/src/socket/socket.js
- backend/test/security.test.js
- backend/test/lifecycle.test.js
- backend/LIFECYCLE_R06.md
- mobile/lib/main.dart
- mobile/lib/providers/assignment_controller.dart
- mobile/lib/services/assignment_service.dart
- mobile/lib/core/widgets/assignment_panel.dart
- mobile/lib/features/mechanic/active_job_screen.dart
- mobile/lib/features/mechanic/mechanic_home_screen.dart
- mobile/lib/features/user/live_tracking_screen.dart
- mobile/lib/features/user/job_in_progress_screen.dart
- mobile/lib/features/user/bidding_routes.dart
- mobile/lib/features/user/user_home_screen.dart
- mobile/test/lifecycle_state_test.dart
- mobile/test/lifecycle_navigation_test.dart

No dependency additions, production environment changes, live database mutations, commits/pushes, or unrelated resets.
