# R04 foreground mechanic availability

The process-local registry in `src/services/presence.service.js` is authoritative
for availability. MongoDB remains authoritative for account eligibility,
mechanic approval and configured service radius. Legacy `Mechanic.isOnline`
values are ignored; R04 never persists `isOnline=true`, changes existing records,
or resets the database. The mechanic profile response overlays live availability.

## Socket contracts

The handshake requires `auth: {token: <current access JWT>}`. The server joins
the verified user's personal room. Existing job-room authorization is unchanged.
All mechanic operations recheck account status, token expiry and role. Online
and location operations also recheck mechanic approval.

- `mechanic:go_online`: `{lat, lng}`. An optional legacy `mechanicId` must match
  the authenticated mechanic. Optional `serviceRadius` must equal the configured
  profile radius. The default radius is 15 km; valid configured radii are 1–100 km.
- `mechanic:update_location`: `{lat, lng}`; only the active session can update.
- `mechanic:go_offline`: `{}`; idempotent for the current session. Approval is
  not required to leave availability. An obsolete session receives 409.
- Success acknowledgment: `{success:true, data:{mechanicId,isOnline,lat,lng,
  serviceRadius}}`. Offline acknowledgments contain only `mechanicId,isOnline`.
- Failure acknowledgment: `{success:false,status,message}`; the same failure is
  emitted as `security:error`. Authentication/authorization rules are unchanged.
- Server-only `mechanic:availability`: `{isOnline:false,reason}` for session
  replacement, approval/account revocation, or lease expiry. It does not trigger
  automatic online restoration.
- Server-only `job:new_request`: `{jobId,description,location,lat,lng,aiDiagnosis,
  createdAt,distance}`. Optional stored diagnosis/time may be absent. `jobId` is
  the saved MongoDB Job ID. `distance` is Haversine kilometres from live presence.
  Client-triggered job/bid/status broadcasts remain forbidden.

Latest successfully registered session wins. Each mechanic receives a broadcast
once. An obsolete socket's offline/update/disconnect cannot remove its successor.
Availability operations are serialized per socket. Live leases expire after
90 seconds without a confirmed location update; an unref'ed 30-second sweep
also checks eligibility. Discovery and dispatch recheck eligibility immediately.

## HTTP

- Existing public `GET /api/mechanics/nearby?lat=&lng=` keeps `{success,data:[]}`
  and returns only eligible live mechanics within each mechanic's radius. Public
  projections exclude documents, earnings, credentials, tokens and socket data.
- New authenticated `GET /api/mechanics/requests` requires an approved mechanic
  with live presence. It returns up to 100 eligible open jobs, filtered by the
  same radius/distance rules. It recovers opportunities missed during transport
  loss, not accepted jobs or assignment state (R05).
- Job creation retains R01's `{success:true,data:job}` response. Dispatch reloads
  saved job location/open status; supplied socket location is not trusted.

## Mobile lifecycle

The mechanic UI waits for acknowledgments. Foreground position streams request
25 m distance updates (Android minimum interval 10 seconds). A 30-second GPS
heartbeat refreshes stationary presence and checks permission/service health.
It also reconciles open opportunities against the latest acknowledged location.
Fixes older than 60 seconds, invalid coordinates and placeholder (0,0) are rejected.
No substituted coordinates are sent. Backgrounding cancels subscriptions and
closes transport, retaining only the user's intent. Foreground/reconnection
restoration reloads approval and obtains a fresh fix before registering again.
Logout, account switching, authentication rejection and replacement clear intent.
Transport reconnect attempts are bounded to five; acknowledgments time out at
8 seconds and connection waits at 10 seconds. Access-token refresh is R09;
expired authentication requires signing in again.

Driver discovery refreshes every 30 seconds in the foreground and through the
existing recenter control. Failed refreshes remove stale mechanic markers.

## Deployment and verification limits

Run a **single Node process** for HTTP and sockets. Multiple workers/instances
would have independent registries; sticky sessions alone do not solve shared
discovery/dispatch. Redis/distributed presence is intentionally outside R04.
Presence is lost on restart and restored by authenticated foreground clients.

No background location, assigned-job tracking, room recovery for accepted jobs,
or refresh rotation is claimed. Physical GPS, Android/iOS background transitions,
two-phone delivery, iOS builds (Windows host), and a live MongoDB replica-set
transaction test still require device/infrastructure validation. The repository's
environment-dependent API/Maps configuration must be set for the target device;
R04 does not change credentials or production environment files.

## R04 file manifest

Validation: 119 Flutter tests passed (46 new R04 + 73 R01/R03), and 46 backend
tests passed (14 new R04 + 32 R02). The existing isolated replica-set test was
skipped because no test URI was supplied. JavaScript syntax passed for 35 source
and test files. Platform XML/plist permission checks and `git diff --check`
passed. `flutter analyze --no-pub` returns exit 1 for 94 remaining pre-existing
diagnostics (2 warnings and 92 informational notices), with no errors or new
diagnostics from R04. No device or live production database checks were run.

```text
backend/PRESENCE_R04.md
backend/src/controllers/mechanics.controller.js
backend/src/models/Mechanic.js
backend/src/routes/mechanics.routes.js
backend/src/services/presence.service.js
backend/src/socket/socket.js
backend/test/presence.test.js
mobile/android/app/src/main/AndroidManifest.xml
mobile/ios/Runner/Info.plist
mobile/lib/features/auth/login_screen.dart
mobile/lib/features/auth/otp_screen.dart
mobile/lib/features/mechanic/mechanic_home_screen.dart
mobile/lib/features/mechanic/new_request_detail.dart
mobile/lib/features/mechanic/submit_bid_screen.dart
mobile/lib/features/user/user_home_screen.dart
mobile/lib/features/user/user_profile_screen.dart
mobile/lib/models/job_request.dart
mobile/lib/providers/mechanic_presence_controller.dart
mobile/lib/services/api_service.dart
mobile/lib/services/auth_service.dart
mobile/lib/services/foreground_location.dart
mobile/lib/services/mechanic_service.dart
mobile/lib/services/socket_service.dart
mobile/test/foreground_location_test.dart
mobile/test/mechanic_discovery_test.dart
mobile/test/mechanic_home_presence_test.dart
mobile/test/mechanic_presence_test.dart
mobile/test/presence_fixtures.dart
mobile/test/socket_presence_test.dart
```
