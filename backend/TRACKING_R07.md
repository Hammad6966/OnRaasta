# R07: assigned mechanic foreground GPS

## Scope and ownership

Tracking is permitted **only during en_route**. Accepted jobs must first use R06's explicit Start travel action. Explicit arrival stops GPS sharing; arrived/in_progress/completed/cancelled never publish or return tracking coordinates. Proximity never changes job status. All eight statuses, bid acceptance transactions, financial rules, design tokens and existing response envelopes are preserved.

Mechanic Home owns JobTrackingPublisher beneath pushed job screens. It remains mounted during Active Job and other foreground screens, and disposes on leaving that application flow. Active Job displays server-confirmed sharing state and Retry GPS without owning a second GPS stream. R06's confirmed HTTP status response also stops that job publisher if a status notification is missed.

DeviceForegroundLocation.shared wraps the existing Geolocator source in reference-counted broadcast streams. R04 availability and R07 job tracking share one native position subscription and one service-status subscription. The final consumer leaving cancels the underlying subscription; subsequent entry recreates it. Concurrent current-position acquisitions are coalesced. Native distance filter remains 25 m; Android requested interval remains 10 s. Publisher defaults are configurable constructor values: minimum 10 s and 10 m between sent observations (the effective native movement threshold is normally 25 m). Unchanged coordinates are suppressed. No periodic movement is generated.

Each eligible assigned job is matched against the authenticated mechanic profile document ID. Startup/reconnect/resume/retry reread approval and active assignments before obtaining fresh GPS. SocketService.ensureConnected uses the current access token and existing singleton transport. Session generations discard delayed GPS/API/ack results after logout, suspension or identity changes. Permission loss, disabled services, inaccurate/stale fixes and connectivity errors are visible. Rate-limit responses wait for the next real GPS observation rather than creating retry timers. Multiple assigned en_route jobs keep separate IDs/ack state.

## Socket input and acknowledgment

Authenticated mechanic → server, `job:mechanic_location`:

```text
{jobId, lat, lng, observedAt:<UTC ISO-8601>, accuracy?:<meters>}
```

No client userId, mechanicId, status, receipt time or arbitrary relay fields are accepted. Those extra fields are forbidden (403); malformed coordinates/time/accuracy are 400. The verified socket account must remain active/verified and its approved Mechanic document must match the saved Job.mechanicId. Job.acceptedBidId must exist, and Job.status must be en_route. Missing job:404; unassigned/unapproved:403; closed/ineligible/out-of-order:409; throttling:429. Refresh JWTs and forged room access remain prohibited by R02.

Validation rules:

- Finite latitude [-90,90], longitude [-180,180], rejecting the (0,0) fallback pair.
- Optional accuracy finite and between 0 and 100 m.
- UTC observation timestamp no more than 60 seconds old or 10 seconds ahead of server time; invalid calendar dates are rejected.
- Strictly increasing observation times. Exact repeated timestamp/coordinates return a duplicate acknowledgment without a relay/write.
- At least five seconds between accepted observations per job/mechanic.
- At most 60 attempted location submissions per authenticated mechanic per minute, including malformed requests, bounding database abuse.
- Reject geographic jumps beyond 70 m/s plus both accuracy allowances and 50 m GPS jitter allowance. This is plausibility checking, not device attestation or a driving-route calculation.

Success acknowledgment:

```text
{success:true,data:{accepted:true,persisted:<bool>,location:<canonical observation>}}
```

Duplicate acknowledgment:

```text
{success:true,data:{accepted:false,reason:'duplicate',location:<previous observation>}}
```

Failures retain `{success:false,status,message}` with an additive `event` identifying the rejected operation. R04 ignores job-domain errors for its own availability state; an ordinary tracking conflict must not silently take an otherwise eligible mechanic offline. Authentication failures still remove stale presence. Acknowledgment means server acceptance, never confirmed delivery to an offline driver.

## Authorized relay

Server → owning driver only, `job:mechanic_location`:

```text
{jobId, mechanicId, lat, lng, observedAt, receivedAt, accuracy?}
```

IDs are derived from persisted assignment; receivedAt is server-controlled. Active/verified account, approval, current assignment and en_route state are checked before relay. Only the driver's authenticated personal room receives it; losing bidders, unrelated drivers, mechanic opportunities and arbitrary job rooms do not. Membership is revalidated before emitting. One room emit avoids duplicate delivery through overlapping room memberships. Clients may submit only the authorized input contract, not forge the canonical relay.

An in-process job queue serializes GPS handling with R06 status persistence/publication, preventing an ordinary terminal transition from being followed by a queued location relay. MongoDB conditional location writes also include status and assignment IDs. Tracking never writes status, statusVersion, prices or semantic updatedAt.

## Latest-location storage, read and retention

GET `/api/jobs/:id/location` requires the owning driver, approved assigned mechanic, or administrator, plus existing active/verified authentication. No public/general mechanic tracking route is added.

```text
{success:true,data:{
  jobId, trackingAllowed, location:<canonical observation|null>,
  ageMs:<number|null>, fresh:<bool>, serverTime, freshForSeconds:60
}}
```

Absent or ineligible tracking is null, never a substituted coordinate. Revoked/inactive assigned mechanics produce no retrievable location. Location freshness reflects observation time; stored stale points are explicitly stale and never described as live.

Job.latestMechanicLocation is an additive hidden (`select:false`) subdocument containing only one latest point: mechanicId, acceptedBidId, coordinates, optional accuracy, observation/receipt dates and expiresAt. Normal Job responses/assignment projections do not expose this storage field. No trail collection is created. The first useful point is persisted, then writes are throttled to at least 15 seconds apart; intermediate accepted observations are held in a bounded process cache. Restart recovery can lose up to the unpersisted tail, so it returns the actual persisted observation and its original timestamps, never a fabricated replacement.

Logical retention is ten minutes from receipt. Expired points are hidden immediately on reads. A startup/30-second sweep nulls expired fields, and leaving en_route nulls the field in the same R06 transaction, clearing cache during status publication. The cleanup never deletes Jobs. Physical expiry cleanup requires a running backend (expired data is scrubbed after restart); there is intentionally no TTL index on Job that could delete business records. Cache and attempt registries are bounded to 10,000 entries and swept; no indefinite history is accumulated.

## Driver UI

Live Tracking loads R05/R06 authoritative assignment state and latest location, filters exact Job/Mechanic IDs, rejects malformed points and ignores duplicate/older observations. REST snapshots cannot overwrite newer socket observations. Access denial/logout clears private coordinates and blocks late relays until fresh assignment authorization. Reconnect/resume/manual retry reauthorize and reload; manual retry can reconnect the current authenticated transport with bounded existing retry behavior.

The map keeps the saved breakdown marker, adds the mechanic marker on the first actual observation and moves it only on newer accepted observations. GPS updates do not move the camera. The existing recenter control centers on the latest mechanic point when present, otherwise on the saved breakdown/viewport. No straight-line polyline, driving-distance claim, paid routing subsystem, extrapolation or simulated movement is added. ETA is labeled **Mechanic ETA estimate**, sourced from the accepted Bid.

The label shows observation time and waiting/recent/stale/offline/error state. A 15-second display timer ages the warning text only; it never produces coordinates or lifecycle changes. A stationary mechanic may have no new movement observation, so a stale warning means no recent location, not proof of disconnection. Arrival clears the mechanic marker; R06 still owns navigation to Job In Progress and completion/review handling.

## Platform and operating limits

Android already had fine/coarse foreground and Internet permissions. Debug/profile manifests now explicitly allow cleartext local development networking; the release/main manifest and its credentials were not changed. iOS WhenInUse purpose text now includes assigned-job sharing. No background location permission, UIBackgroundModes location, foreground service, Gradle/package dependency or broad iOS ATS exemption was added.

iOS ATS remains HTTPS-only by default. Local HTTP testing on iOS requires a developer-scoped exception or HTTPS backend; this change does not weaken production transport. Existing Maps configuration remains in place, with no credentials included here. Background/hidden/paused operation stops subscriptions and publication. A pending one-shot OS position request can finish later, but its result is discarded after suspension. No background GPS capability is claimed.

The cache/queues/rooms remain single-process. Multiple backend instances need coordinated transport/presence later; persisted recovery remains authorized but may lag the in-memory tail. Device clocks should be synchronized within the documented observation tolerance. Physical GPS, actual two-device streaming, Android/iOS native builds and live MongoDB status/location races remain UNVERIFIED. The isolated MongoDB integration test remains SKIPPED without an isolated replica-set URI. R08 review submission and R12 earnings remain separate tasks.

## Tests and exact file manifest

New backend tests cover assigned publication, owner-only delivery, roles/approval/account state, malformed fields, all disallowed stages, stale/future time, accuracy, duplicate/reordered/rate-limited observations, impossible movement, persistence throttle, restart recovery, retention, explicit arrival, cancellation racing with GPS, hidden storage and availability isolation. Flutter tests cover shared native streams, acknowledgment gating, permission/service/accuracy failures, interval/movement filtering, foreground/reconnect/logout behavior, HTTP-denial privacy, latest recovery races, manual authenticated retry, first/later markers, staleness, no road polyline and no automatic arrival. All existing R01–R06 suites are retained.

Validation: all 239 Flutter tests passed (200 existing R01–R06 plus 39 new R07); all 111 controlled backend tests passed (88 existing plus 23 new R07), with the isolated MongoDB integration test skipped. JavaScript syntax passed for all 41 source/test files. Flutter analysis reports zero errors/new diagnostics; it exits nonzero with 89 existing diagnostics (one warning and 88 info, down from 90). Android manifest XML and iOS plist parsing passed, with no background-location permissions added. `git diff --check` passed. None of these checks verifies physical GPS or actual two-device streaming.

- backend/src/services/job-tracking.service.js
- backend/src/socket/socket.js
- backend/src/routes/jobs.routes.js
- backend/src/controllers/jobs.controller.js
- backend/src/services/job-lifecycle.service.js
- backend/src/models/Job.js
- backend/test/fixtures.js
- backend/test/tracking.test.js
- backend/TRACKING_R07.md
- mobile/lib/services/foreground_location.dart
- mobile/lib/services/socket_service.dart
- mobile/lib/services/job_location_service.dart
- mobile/lib/models/job_location.dart
- mobile/lib/providers/job_location_controller.dart
- mobile/lib/providers/job_tracking_publisher.dart
- mobile/lib/providers/mechanic_presence_controller.dart
- mobile/lib/features/mechanic/mechanic_home_screen.dart
- mobile/lib/features/mechanic/active_job_screen.dart
- mobile/lib/features/user/live_tracking_screen.dart
- mobile/lib/core/widgets/job_sharing_banner.dart
- mobile/test/tracking_test.dart
- mobile/test/tracking_map_test.dart
- mobile/android/app/src/debug/AndroidManifest.xml
- mobile/android/app/src/profile/AndroidManifest.xml
- mobile/ios/Runner/Info.plist

No production credentials/environment changes, destructive migration, live database reset, commits or pushes.
