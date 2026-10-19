# R09 — Refresh rotation, session recovery and account isolation

## Backend sessions and contracts

New `RefreshSession` documents represent one device/login family. Fields: userId, role, SHA-256 tokenHash, previousHash, rotatedAt, revokedAt, expiresAt and timestamps. Random ObjectId is the signed session ID; refresh JWTs additionally contain a cryptographically random 256-bit jti. Only token digests are stored; raw refresh tokens and OTP/password/JWT values are never logged or returned in ordinary profile/admin records. Hash fields are excluded by default from Mongoose selection.

Access JWT lifetime stays **15 minutes**. Newly issued/rotated refresh JWTs last **7 days**; the device family's inactivity expiry moves with successful rotation. There is no new shorter/longer admin access lifetime. Refresh signing retains the existing JWT_REFRESH_SECRET; no environment/production credential file was changed.

Login/OTP keep their successful envelopes (`success`, `accessToken`, `refreshToken`, `user`). Both now persist a device session before returning credentials. Public mobile password login does not provision/admin-authenticate an admin; existing email/password `/api/admin/login` remains the admin entry point and retains its R02 role checks and auth rate limit.

`POST /api/auth/refresh` accepts exactly `{refreshToken}` and returns the same full token/user envelope as login. It verifies signature, expiry, purpose, session ID, random token identifier, current account active/verified status and original role. A single-document conditional `findOneAndUpdate` compares current digest, owner, role, revocation and expiry, then replaces the digest/expiry atomically. No multi-document refresh transaction or fallback is needed. Separate devices have independent families.

Concurrent use has one winner. For **3 seconds** after rotation, a duplicate of the immediately previous token returns **409** without credentials and without revoking the winning session. This avoids corrupting an immediately racing legitimate request. Older generations, or replay after that overlap, revoke the family and return **401**. The client never receives replacement credentials by replaying an old token. A lost committed refresh response can therefore require reauthentication on retry; the overlap is not a credential-recovery endpoint.

`POST /api/auth/logout` accepts `{refreshToken}`. A valid signed family token can revoke its family even if the access token has expired; repeated logout is idempotent. Invalid token/purpose is rejected. Other devices remain signed in. Same-instance sockets for that family are disconnected immediately. Suspension and role changes are enforced on every access verification/refresh, and refresh rejection revokes the affected family.

`GET /api/auth/session` uses the existing access/account middleware, requires a tracked mobile family and returns `{success:true,user:{id,name,phone,role}}`. It validates current account eligibility again before returning. Untracked pre-R09 mobile sessions require one-time sign-in; their old refresh tokens are never silently adopted. Existing legacy access JWTs remain bounded by their original 15-minute expiry on other protected routes. Admin access-only JWTs remain supported.

All auth responses use `Cache-Control: no-store`. Session reads use the general API limit; login, OTP, refresh and logout use the existing 10 requests/15 minutes auth limiter. General API limit stays 100/15 minutes.

Access verification returns optional public error code `ACCESS_TOKEN_EXPIRED` only when JWT expiration is rejected by authentication middleware before the business handler runs. `ACCOUNT_UNAVAILABLE` distinguishes suspension/role changes from ordinary ownership/role denials. Existing success/error envelopes and HTTP status contracts remain.

## Safe initialization

The new collection uses its default unique `_id`, a userId index and `expired_refresh_sessions` TTL index on expiresAt (`expireAfterSeconds:0`). Deploy using the project's normal Mongoose index initialization, or explicitly call `RefreshSession.createIndexes()` in the normal authorized deployment procedure. Deploy matching backend/mobile versions together. No destructive migration, index deletion or production database operation was performed. Expiry/revocation is checked in queries immediately; security does not depend on MongoDB's asynchronous TTL cleanup. Expired records are removed eventually by MongoDB.

The isolated optional database test now creates this collection/index in its existing randomly named test database, exercises racing rotation and logout, then cleans up only that database. No real test URI was available during this implementation; actual MongoDB behavior remains UNVERIFIED.

## Flutter session ownership

AuthService is the single session owner exposed through the existing Riverpod architecture. A canonical JSON `auth_session` snapshot in Flutter Secure Storage atomically stores token pair and server-confirmed identity. Existing secure keys remain compatibility mirrors; there is no SharedPreferences or insecure token persistence. Startup can read legacy keys but validates against the server before entering protected screens.

During logout cleanup, public credential reads are blocked immediately; successful sign-in advances the generation again so delayed anonymous requests cannot invalidate the new account. A serialized secure-write queue and synchronous session generation prevent old login, refresh or HTTP responses from overwriting a newer account/logout. Idle queue tails are released; no pending work is carried across disposed screen/test zones. API success responses from another generation are cancelled before screen controllers can consume them. Old errors cannot clear a newly signed-in account.

Access expiry decoding is used only for scheduling, never as proof of identity/authorization. Access refresh starts within 30 seconds of expiry or when a refresh credential exists but access is absent. Several concurrent failures share one refresh future. Delayed old-token 401s reuse the already stored replacement instead of rotating again.

ApiService uses a separate interceptor-free transport for refresh. Eligible failed requests retry **once** only after the explicit pre-handler expiry code. JSON job creation/bid/status/review mutations are safe in that case because their handlers did not run. There is **no retry** on network timeouts, generic 401s, 5xx, or ambiguous commit outcomes. Stream/multipart request bodies are not automatically replayed. A retried request cannot recursively refresh.

Refresh 400/401/403/409 or malformed successful credentials require secure sign-in again. Network/5xx/429 refresh failures retain stored credentials and surface retry errors. A generic protected 401 ends the session; ordinary ownership 403 does not. Account-unavailable 403 clears identity. The router listens for session invalidation and redirects protected routes to login. Login/OTP use the same manager rather than writing token keys independently.

## Startup, logout and UI

Splash preserves the existing theme/onboarding/server configuration UI. It shows loading while validating/refreshing the saved session, then uses the server-confirmed role for driver/mechanic routing. Offline startup shows explicit retry/sign-in controls and does not claim validated access to protected screens. No fixed delay gates authentication. An explicit sign-in alternative clears the saved identity first.

Logout invalidates the generation and authenticated socket immediately, then serially clears token/identity keys and attempts revocation with a bounded wait. Non-auth preferences (theme/server IP) remain. Network failure does not restore local tokens. Remote revocation cannot be guaranteed when the device is offline: copied credentials on another device may remain valid until server revocation/expiry. No credentials are queued in insecure storage for later logout.

## Socket and foreground recovery

SocketService resolves canonical credentials before connecting, preventing stale screen arguments from downgrading the handshake. Refresh replaces the transport while preserving individual listeners. Renewal sends a transport-disconnect notification (pause), not `session:ended` (logout). R04 retains availability intent, rechecks approval and obtains fresh GPS; R05 reconciles assignments, R06 refetches persisted status, and R07 rechecks eligible foreground assignment before sharing again. No new background GPS behavior or permission was introduced.

Expired/rejected handshakes and expired reconnect attempts use the shared refresh manager. Concurrent HTTP/socket refreshes share the same future. Failed authentication recovery has a bounded budget; temporary network failure pauses rather than spinning. A later successful HTTP refresh reconnects a still-desired paused socket. Explicit logout/background transport shutdown cancels that intent, and late credentials cannot recreate an old user's transport. Logout emits the existing session-ended lifecycle event, stopping presence/GPS and clearing assignment/location caches; protected-route disposal clears other screen-owned state.

Existing in-memory presence/Socket.IO deployment remains single-process. Mongo-backed refresh state and access checks work across instances, but immediate socket revocation delivery is local to the handling instance; coordinated cross-instance socket transport/revocation remains outside the current deployment architecture. No Redis/distributed service was introduced.

## Admin

Admin keeps access-only authentication and 15-minute expiry, with no browser refresh token. Access storage is now tab-scoped sessionStorage; legacy localStorage access is removed on login or unauthenticated dashboard entry. Missing/expired/forbidden admin sessions clear dashboard data and redirect for secure reauthentication. Network failures do not pretend token expiration. Stale responses from an earlier admin token cannot clear/populate a newly signed-in dashboard. Existing styling and protected endpoint/header usage remain.

## Validation

Final validation:

- All 309 Flutter tests passed: 270 retained R01?R08 tests plus 39 new R09 tests.
- All 145 controlled backend tests passed: 129 retained tests plus 16 new R09 tests; one isolated real MongoDB integration test remains skipped.
- All 47 backend source/test JavaScript files passed `node --check`.
- Admin TypeScript passed `tsc --noEmit --incremental false`.
- Flutter analysis has zero errors/new diagnostics; exits nonzero with 83 existing diagnostics (one warning, 82 info), down from 85 at the R08 baseline.
- `git diff --check` passed.
 R09 adds backend tests for issuance, rotation, overlap/replay, revocation, account roles/state, multi-device isolation, tracked startup, expiry, safe fields and socket family disconnection. Flutter tests cover concurrent 401 refresh, retry-once/mutation safety, offline recovery, secure storage, account switching/late responses, logout, splash retry and actual R04/R05/R07 controller recovery through the SocketService test transport. R01–R08 tests are retained without weakening their assertions.

Physical phone/end-to-end testing and live MongoDB integration remain UNVERIFIED/SKIPPED as applicable. Firebase Storage, photos and FCM remain deferred. No dependencies, design tokens, payments, production secrets, commits or pushes changed.

## Exact R09 file manifest

- backend/src/models/RefreshSession.js (new)
- backend/src/services/refresh-session.service.js (new)
- backend/src/services/access.service.js
- backend/src/controllers/auth.controller.js
- backend/src/routes/auth.routes.js
- backend/src/middleware/error.middleware.js
- backend/src/socket/socket.js
- backend/test/fixtures.js
- backend/test/session.test.js (new)
- backend/test/mongo-concurrency.test.js
- backend/SESSION_R09.md (new)
- mobile/lib/services/auth_service.dart
- mobile/lib/services/api_service.dart
- mobile/lib/services/socket_service.dart
- mobile/lib/features/auth/login_screen.dart
- mobile/lib/features/auth/otp_screen.dart
- mobile/lib/features/auth/splash_screen.dart
- mobile/lib/main.dart
- mobile/lib/providers/auth_provider.dart
- mobile/lib/features/user/user_profile_screen.dart
- mobile/lib/features/mechanic/mechanic_home_screen.dart
- mobile/lib/features/user/mechanics_found_screen.dart
- mobile/lib/features/user/report_breakdown_screen.dart
- mobile/test/session_test.dart (new)
- mobile/test/session_socket_test.dart (new)
- admin/app/page.tsx
- admin/app/login/page.tsx
