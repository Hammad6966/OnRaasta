# R11 ? authenticated profiles, vehicles and emergency contacts

All endpoints use the existing JWT/account/session middleware. Successful responses retain `{success:true,data:...}`. Mutations reject unknown/protected fields with 400; unauthenticated/forbidden access is 401/403; missing or foreign vehicles are 404; duplicate identities, referenced deletion, and primary conflicts are 409. No Firebase integration was added.

## Contracts
- GET /api/users/profile: authenticated self only. Explicit projection: _id, name, email, phone, role, isVerified (phone verification), createdAt, vehicleIds, emergencyContacts. Email is contact information, not verified email or a login identity for drivers.
- PATCH /api/users/profile: name (trimmed 2?100), email (normalised lowercase valid address), emergencyContacts (driver only). Phone, role, active/verification flags, security fields and ownership arrays cannot be changed. Email uniqueness is database-enforced as well as prechecked. An omitted email remains unchanged.
- Contacts are replaced atomically as a complete self-owned array of `{name,phone}`; at most five, name 1?100, phone optional plus and 10?15 digits, exact duplicate phones rejected. Existing contact child IDs are not trusted on write. Concurrent edits use last successful write; no emergency messages or SOS dispatch are performed.
- GET /api/users/vehicles: driver-only own vehicles.
- POST /api/users/vehicles: make/model (1?80) and plate (2?30 alphanumeric, spaces/hyphens) required; optional year (integer 1900?next year), color (1?80), isPrimary boolean.
- PATCH /api/users/vehicles/:id: same editable fields, partial update; no userId mutation. Plate normalised uppercase. Selecting another vehicle makes it primary. A primary cannot be unset without selecting another; first vehicle becomes primary.
- DELETE /api/users/vehicles/:id: only own vehicle, refused if ANY active, completed or cancelled Job references it. A remaining vehicle becomes primary when the primary is removed.
- GET /api/mechanics/profile: mechanic-only self; explicit safe fields with populated user's name/phone/email/role. Includes skills, radius (15 default), shopAddress, approval, actual reputation/job count and document decision status/reason only. No CNIC URLs, permit numbers, authentication data or document images.
- PATCH /api/mechanics/profile: name, skills, shopAddress (up to 500), serviceRadius (1?100). Name updates User in the same transaction. Skills must be distinct members of utils/profile-policy.js: existing UI skills plus the AI classification's actual specialist labels. No client coordinates or approval/reputation/document mutations. GPS remains owned by R04/R07.

## Approval and availability
Any actual change to an approved mechanic's skills resets isApproved=false and document review status to pending; this does not assert any documents exist or have been verified. Existing assignments, reviews and financial fields are preserved. Assigned actions requiring approval remain blocked pending legitimate reapproval. Reordering unchanged skills does not trigger review. Address/radius/name edits retain approval. Qualification revocation removes online presence immediately. Name/address/radius edits preserve eligible availability; discovery, dispatch and location updates reread the persisted radius through R04. Home and tracking controllers reconcile after a confirmed edit.

## Concurrency and deployment
Vehicle mutations and job creation WITH a vehicle acquire a write lock on the same User document inside MongoDB transactions. This serializes concurrent primary choices, keeps vehicleIds aligned, and prevents delete/create-reference races. No unique-primary index is required (a transaction may switch primary without a transient unique-index conflict). No nontransactional fallback is used. Existing replica-set/transaction-capable deployment requirement remains.

User.email now has a sparse unique index; Vehicle.userId has a lookup index. Before deployment, inspect existing email data for duplicates/empty values and arrange an explicit administrative resolution if necessary. Ensure these declared indexes have successfully built (User.createIndexes()/Vehicle.createIndexes() in the controlled deployment process). Index creation must fail visibly on duplicates; no code deletes or rewrites existing records. No live index initialization or migration was performed here. Existing malformed primary/vehicleIds data is reconciled on the next successful vehicle mutation rather than silently writing during reads.

## Flutter
Screen-owned ProfileController uses shared authenticated Dio through ProfileService. It guards session epoch/generation, deduplicates loads, blocks duplicate saves, clears account data on session change, and ignores late reads/writes. Forms retain input on failed saves, dialogs close on session changes, and successful screens reload persisted data. Driver cards show real vehicles/contacts and no fabricated statistics. Breakdown reporting allows optional saved-vehicle selection and preserves the R01 response/navigation contract. Mechanic form loads real data, locks phone, supports radius 1?100, shows approval and requires legacy unsupported skills to be removed before saving. No account profile cache is persisted outside secure authentication infrastructure.

Photo/document upload controls explicitly report unavailable/deferred, cannot toggle fake uploaded state, and cannot report successful submission. Push notification settings are labelled deferred. No SDKs, environment values or credentials were changed.

## Verification limits
Controlled tests use fixtures and fake API/GPS/native UI boundaries only. The existing isolated MongoDB test now also covers concurrent primary choices and vehicle-delete/job-create races; it remains SKIPPED without ONRAASTA_TEST_MONGO_URI. Real database index/transaction behavior and physical-device behavior are UNVERIFIED until those checks are run. Contacts have no cross-device optimistic edit-version UI; email verification/change-of-phone flows remain separate. R12 earnings/history, R10 uploads and R14 FCM remain deferred/out of scope.

## R11 file manifest
backend/src/controllers/users.controller.js
backend/src/controllers/mechanics.controller.js
backend/src/controllers/jobs.controller.js
backend/src/controllers/auth.controller.js
backend/src/routes/users.routes.js
backend/src/routes/mechanics.routes.js
backend/src/models/User.js
backend/src/models/Vehicle.js
backend/src/middleware/request-validation.js
backend/src/utils/profile-policy.js
backend/test/fixtures.js
backend/test/profile.test.js
backend/test/mongo-concurrency.test.js
backend/PROFILES_R11.md
mobile/lib/services/profile_service.dart
mobile/lib/providers/profile_controller.dart
mobile/lib/core/widgets/profile_edit_dialog.dart
mobile/lib/features/user/user_profile_screen.dart
mobile/lib/features/user/report_breakdown_screen.dart
mobile/lib/features/mechanic/mechanic_profile_edit.dart
mobile/lib/features/mechanic/mechanic_home_screen.dart
mobile/lib/features/mechanic/document_upload_screen.dart
mobile/lib/features/auth/signup_screen.dart
mobile/test/profile_test.dart

## Final controlled validation
- Backend: 165 passed, 0 failed, 1 isolated MongoDB integration test skipped; 20 new R11 backend tests.
- Flutter: 332 passed, 0 failed; 23 new R11 Flutter tests. Existing R01?R09 regressions included.
- Flutter analyze --no-pub: 0 errors, 0 warnings, 74 remaining pre-existing informational diagnostics. Analyzer exits 1 because informational diagnostics remain. No new R11 diagnostics.
- JavaScript syntax: all 49 backend source/test files passed node --check.
- git diff --check: passed; Git's existing LF/CRLF notices are not whitespace failures.
- Physical phones, real MongoDB transactions and index initialization: UNVERIFIED, not reported as passed.
- No commits/pushes, production environment changes, database resets or Firebase integration performed.
