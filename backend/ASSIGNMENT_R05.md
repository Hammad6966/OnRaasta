# R05: persisted assignment handoff and recovery

R02's acceptance transaction and Bid indexes are unchanged. The transaction checks driver ownership, an open Job, a pending Bid and a currently eligible mechanic. It writes the Job's acceptedBidId/mechanicId/status, declines competing pending Bids, and accepts exactly one Bid. Publication runs only after `withTransaction` resolves successfully, outside its retry callback. Publication failure cannot turn a committed assignment into an HTTP error. Duplicate acceptance still returns 409; there is no nontransactional fallback.

## HTTP contracts

- `PATCH /api/bids/:bidId/accept`: existing authenticated owner-only `{success:true,data:bid}` contract unchanged. R03 still validates that Bid and reloads `/api/jobs/:jobId` before driver navigation.
- `GET /api/jobs/assignments`: authenticated active/verified driver gets their own active assignments; approved mechanic gets jobs assigned to their Mechanic document. Multiple records are returned. Admins use the individual read, not this participant list. Active statuses: accepted, en_route, arrived, in_progress. Empty means `data:[]`.
- `GET /api/jobs/:jobId/assignment`: authenticated owner, currently approved assigned mechanic, or admin. Completed/cancelled assignments can still be read; they are excluded from the active list. Missing Job:404; forbidden:403; inconsistent/missing accepted records:409; malformed ID:400; invalid authentication:401. Existing inactive/unverified-account rejection remains 403.
- `GET /api/jobs/:jobId/opportunity`: authenticated approved mechanic; returns only `{success:true,data:{jobId,isOpen}}`. No customer record is exposed to competitors. This narrowly supports stale bid-form preflight. The bid transaction remains the final authority if availability changes after this read.
- Existing `GET /api/jobs` driver history and eight-state lifecycle are preserved.

Assignment reads use `{success:true,data:assignment}` (or an array for the list):

```text
assignment = {
  jobId, acceptedBidId, mechanicId, mechanicUserId, userId, status,
  labourCost, partsCost, totalCost, eta,
  job: {
    _id, userId, mechanicId, acceptedBidId, status, location, description,
    aiDiagnosis, photos, vehicleId, finalCost, review, createdAt, updatedAt
  },
  bid: {
    _id, jobId, mechanicId: {
      _id, userId: {_id,name,phone}, skills, serviceRadius, shopAddress,
      isApproved, rating, totalJobs
    },
    labourCost, partsCost, totalCost, eta, status, createdAt, updatedAt
  },
  driver: {_id,name,phone}
}
```

Optional fields are omitted when absent. The mechanic's User reference remains an ID if that account is unavailable. No fabricated names, prices, coordinates, or accepted timestamps. The existing schema does not store acceptedAt; ordinary updatedAt is not described as an acceptance timestamp. The agreed price comes from the accepted Bid, not an invented Job.totalCost. No database migration, new dependencies, or configuration changes are required. MongoDB transactions still require a supported replica set/sharded deployment.

Explicit public projections exclude mechanic documents/CNIC, earnings, password hashes, OTP, JWT/refresh tokens, emergency contacts and unrelated account fields. Name/phone is shared only with authorized participants/admins.

## Socket events

All events below are server-only. Attempts to emit them from a client receive 403. Personal rooms are joined using the verified JWT account, never a submitted socket/User/Mechanic ID.

| Event | Recipient | Payload |
|---|---|---|
| bid:accepted | owning driver, user_<driverUserId> | {jobId,acceptedBidId,mechanicId,status} |
| job:assigned | winning mechanic, user_<mechanicUserId> | same hint |
| job:unavailable | authenticated mechanic sockets | {jobId} only |
| bid:declined | competing mechanic's own user room | {jobId,bidId,status:'declined'} |

The unavailable event contains no customer, winning-mechanic, location or price information. Decline contains only the recipient's own Bid ID. Live account state is rechecked before assignment publication. Owner/winner sockets may join the job room after commit; existing room members are pruned using live authorization. Administrative mechanic revocation awaits room pruning. Competitors cannot join job_<jobId>; approval is required for assigned-mechanic room/read access.

## Mobile behavior

- AcceptedBooking validates canonical/nested Job/Bid IDs, owning driver, mechanic User ID, exact cost components, ETA and persisted status. The same typed contract is used by both driver acceptance paths and the mechanic Active Job route. Malformed route arguments render the existing recoverable invalid-booking page.
- Both homes load assignments on startup, reconnect and foreground resume, and expose refresh/retry. Socket hints trigger a guarded single-record authorized read. Lists deduplicate by saved Job ID, reconcile racing HTTP/socket results, and never automatically push a page on repeated notifications/reconnects. Users explicitly open the assignment; multiple jobs remain visible.
- Mechanic request feeds remove unavailable/assigned IDs and cannot resurrect them through an older HTTP feed or duplicate socket request. Assignment-list recovery invalidates stale opportunities even when the acceptance event was missed.
- Active Job and Live Tracking reload the same assignment on entry/reconnect/retry and request server-authorized room membership after a successful read. Disconnects show a connection message. Network errors retain confirmed identity/prices with retry; forbidden/session-ended states hide private screen content. Mechanic actions require a successful current read and confirmed API mutations. Missing status is never defaulted to en_route. Earnings retain the existing 85%/15% calculation.
- Request detail and Submit Bid check availability and listen for invalidation. Bidding is disabled while unknown/loading/closed. Submit Bid checks again before its authenticated POST, guards duplicate taps, validates the actual bid confirmation, and surfaces 401/403/404/409 without apparent success.
- No simulated movement, arrival, assignment or price. Full status propagation remains R06; assigned-job GPS remains R07. Existing layout, fonts, tokens and navigation paths remain.

## Verification and infrastructure limits

Automated fixtures cover successful assignment, IDs/prices/ETA, owner/winner notification, losing-mechanic privacy, competing decline, duplicate/racing acceptance, rollback/no events, post-commit notification failure, private room authorization, revocation, missed-event recovery, multiple jobs, opportunity removal, assigned-job bid rejection, malformed routes, UI retry, duplicate submit, and session/reload races. Existing R01–R04 suites are retained.

Validation: 171 Flutter tests passed (119 preserved R01–R04 plus 52 new R05); backend 62 passed (46 preserved plus 16 new R05), with the isolated MongoDB integration test skipped. JavaScript syntax was verified for all 37 source/test files. Flutter analysis has zero errors/new diagnostics, but exits nonzero with 90 existing diagnostics (one warning and 89 info); the pre-R05 report had 94. `git diff --check` passed. The optional real MongoDB test remains gated by an isolated ONRAASTA_TEST_MONGO_URI and was skipped because it was unavailable. No production environment or database records were used by controlled tests.

Socket publication is best effort, with no durable outbox/replay; authenticated MongoDB reads recover assignments after missed events/restarts. R04 presence and socket rooms remain process-local: multiple backend instances need shared/distributed transport infrastructure later. Physical multi-device acceptance/reconnect, native GPS/background behavior, and real replica-set transaction behavior still require deployment/device verification. R05 does not add tracking or background GPS claims.

## Exact R05 file manifest

Backend (existing files modified):

- backend/src/controllers/bids.controller.js
- backend/src/routes/jobs.routes.js
- backend/src/routes/admin.routes.js
- backend/src/services/access.service.js
- backend/src/socket/socket.js

Backend (added):

- backend/src/services/assignment.service.js
- backend/test/assignment.test.js
- backend/ASSIGNMENT_R05.md

Mobile (existing files modified, including pre-existing uncommitted R03/R04 sources):

- mobile/lib/main.dart
- mobile/lib/models/booking_arguments.dart
- mobile/lib/providers/mechanic_presence_controller.dart
- mobile/lib/features/user/bidding_routes.dart
- mobile/lib/features/user/mechanics_found_screen.dart
- mobile/lib/features/user/mechanic_profile_view.dart
- mobile/lib/features/user/live_tracking_screen.dart
- mobile/lib/features/user/user_home_screen.dart
- mobile/lib/features/mechanic/mechanic_home_screen.dart
- mobile/lib/features/mechanic/new_request_detail.dart
- mobile/lib/features/mechanic/submit_bid_screen.dart
- mobile/lib/features/mechanic/active_job_screen.dart
- mobile/test/mechanic_home_presence_test.dart (injects empty assignments in existing presence-only fixtures; assertions retained)

Mobile (added):

- mobile/lib/services/assignment_service.dart
- mobile/lib/providers/assignment_controller.dart
- mobile/lib/providers/opportunity_controller.dart
- mobile/lib/core/widgets/assignment_panel.dart
- mobile/lib/core/widgets/assignment_state_banner.dart
- mobile/lib/core/widgets/opportunity_banner.dart
- mobile/test/assignment_fixtures.dart
- mobile/test/assignment_recovery_test.dart
- mobile/test/assignment_navigation_test.dart

No commits/pushes, secrets/environment changes, schema/index changes, production data operations, or unrelated rewrites.
