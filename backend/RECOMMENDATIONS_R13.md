# R13 — Mechanic recommendation integration

## Scope and authority

Recommendations are deterministic weighted rules, not a trained model or a
probability of successful repair. Existing text diagnosis remains keyword based;
image diagnosis and future DistilBERT/YOLO work are unchanged. Firebase Storage,
uploads and FCM remain deferred. No financial snapshots, commission rules,
transactional acceptance, JWT checks or socket permissions are changed.

The driver requests `GET /api/jobs/:id/recommendations` through the shared
authenticated Flutter API client. Only the authenticated owning driver may read
recommendations. The saved Job must be pending/bidding and unassigned. Invalid
IDs/queries return 400, missing/invalid authentication 401, foreign ownership 403,
missing jobs 404, and changed/closed jobs 409. Upstream configuration, timeout or
invalid scoring responses return a sanitized 503. No client candidate list is
accepted.

Node selects pending bids belonging to that Job, validates exact labour/parts
pricing using R12 accounting helpers, and resolves R04 presence. Candidates must
have a currently connected, active, verified, approved mechanic profile within
its configured 1–100 km service radius (15 km default). Presence expires after
90 seconds. The location source is the current foreground presence snapshot,
not a workshop fallback or another Job's private tracking coordinates.

At most 500 pending bids are scanned in stable ID order and 100 eligible bids
are scored. `truncated` identifies bounded results. Missing/invalid locations,
invalid prices and ineligible mechanics are excluded. Missing ratings contribute
zero without manufacturing a rating. Node rechecks the authorized snapshot after
scoring; changed candidates or job state return 409. This is a snapshot, not an
availability guarantee: acceptance retains its existing final security checks.

## Scoring policy

`ai-service/data/recommendation_policy.json` is the fault/skill and normalization
policy used by the scorer. Every component is bounded to [0,1]:

| Component | Normalization | Weight |
| --- | --- | --- |
| Skill | Any mapped declared skill: 1; General Mechanic fallback for a known fault: 0.5; otherwise 0 | 0.35 |
| Distance | max(0, 1 − Haversine distance in km / 15) | 0.25 |
| Rating | Actual persisted rating / 5; missing: 0 | 0.25 |
| Price | max(0, 1 − quoted total paisa / 5,000,000) | 0.15 |

The existing fixed anchors (15 km, PKR 50,000) are retained, independently of
mechanic-specific radius eligibility. Haversine uses Earth radius 6371 km.
Price inputs are exact integer paisa, with minimum labour PKR 500 and exact
labour + parts = total. No relative cheapest-price division gives zero/missing
prices a perfect score. One bid receives its actual score. Decimal weighted
arithmetic is rounded half-up to 12 decimal places; descending score, ascending
Bid ID and Mechanic ID provide deterministic ordering.

Skill matching folds case and whitespace and explicitly aliases tire/tyre:

| Fault | Matching declared skills |
| --- | --- |
| flat_tire | Tyre Specialist, Tyre Change |
| dead_battery | Auto Electrician, Battery, Electrical |
| engine_overheating | Engine Specialist, Engine Repair |
| oil_leak | General Mechanic, Engine Specialist, Engine Repair |
| brake_failure | Brake Specialist, Brakes |
| transmission_issue | Transmission Specialist |
| electrical_fault | Auto Electrician, Electrical |
| fuel_problem | General Mechanic, Engine Repair |
| ac_fault | AC Specialist, AC Repair |
| suspension_issue | Suspension Specialist |
| coolant_leak | Engine Specialist, Engine Repair |
| unknown / missing / unrecognized | No automatic qualification |

Multiple skills do not stack. The saved diagnosis is not modified. Free-form
`skill_required` is preserved as input metadata; canonical fault mapping controls
qualification rather than trusting arbitrary labels.

## Internal FastAPI contract

`POST /recommend` retains `{job, mechanics}` at the top level. Strict typed input
rejects extra properties, nonfinite numbers, bad IDs, invalid coordinates, wrong
price components, duplicate Bid IDs and more than 100 candidates (HTTP 422).

`job` contains `jobId`, saved `location:{lat,lng}`, and optional
`aiDiagnosis:{fault_class,skill_required}`. Each candidate contains `bidId`,
`mechanicId`, `skills`, nullable `rating`, presence `lat/lng`, `serviceRadius`,
`labourMinor`, `partsMinor`, and `totalMinor`.

The response is `{policyVersion:"weighted_rules_v1", mechanics:[...]}`. Each row
contains `bidId`, `mechanicId`, `totalMinor`, `score`, `components` (skillMatch,
distanceScore, ratingScore, priceScore), `distanceKm`, `ratingMissing`, and
`matchedSkills`. There are no private documents, customer contacts or JWTs.
Node validates IDs, quoted amounts, completeness, normalized components,
weighted score consistency and deterministic ordering before returning results.

The driver response is `{success:true,data:{jobId,policyVersion,generatedAt,
locationSource:"foreground_presence",distanceType:"straight_line_km",truncated,
expiresAt,rankings}}`. Rows additionally include actual nullable rating, skills,
labour/parts minor amounts and `presenceUpdatedAt` (server presence receipt
timestamp). `expiresAt` is the earliest candidate presence lease expiry; empty
results have null expiry. Empty eligibility results need no AI request.

## Flutter behavior

The Recommended tab uses FastAPI rank mapped by exact Bid and Mechanic IDs and
unchanged prices. Unknown result IDs never create bid cards. Real offers without
a ranking remain visible below ranked offers in deterministic Bid ID order.
Loading, unavailable, expired and truncated results are explicit. A failed AI
call leaves acceptance available and labels Bid ID ordering as a fallback.
Scores are labeled rules scores, and distances are labeled straight-line.

Cheapest uses validated exact quoted paisa. Fastest uses actual ETA with unknown
values last. Both use stable Bid ID ties. Tab changes sort cached bids without
refetching. Bid arrivals coalesce for 300 ms; generation guards reject late
results. Assignment/status notifications invalidate existing scores immediately.
Resume/reconnect/refresh reconcile bids and scores. Expiry clears stale ranking
without a polling loop. Session epoch checks clear rankings and reject responses
from an old account. Existing typed profile and booking navigation is retained;
the route is keyed by saved Job ID.

An inspection also found breakdown POSTs substituting map viewport coordinates
when GPS was unavailable. New submissions now require actual valid GPS and offer
a GPS retry; the viewport default remains visual only. R01 response validation,
data preservation and duplicate submission guards remain intact. Old persisted
coordinate provenance cannot be inferred or repaired automatically.

## Deployment and operational limits

Copy the variable names from `backend/recommendation.env.example` into operator
configuration; no existing environment values were edited. `AI_SERVICE_URL` is
the private FastAPI base URL, without `/recommend`; Node appends that path.
`AI_RECOMMEND_TIMEOUT_MS` defaults to 2000 and accepts 250–5000. Node disables
redirects and automatic retries and bounds request/response sizes. No mobile
internal service URL or credentials are introduced. Deploy FastAPI on a private
network: its pure scoring endpoint does not authenticate against MongoDB and
must not be treated as the private Job authorization boundary.

No new packages, indexes, schema migrations, paid routing requests or model
downloads are required. Process-local R04 presence still requires sticky/single
instance operation for consistent discovery; distributed presence is outside
R13. Distance is geographic, not driving distance or traffic ETA. Displayed ETA
remains the mechanic's quote.

## Files changed for R13

- `ai-service/data/recommendation_policy.json`
- `ai-service/routers/recommend.py`
- `ai-service/tests/test_recommend.py`
- `backend/src/services/recommendation.service.js`
- `backend/src/routes/jobs.routes.js`
- `backend/src/middleware/error.middleware.js`
- `backend/test/recommendation.test.js`
- `backend/recommendation.env.example`
- `backend/RECOMMENDATIONS_R13.md`
- `mobile/lib/models/recommendation.dart`
- `mobile/lib/providers/recommendation_controller.dart`
- `mobile/lib/services/ai_service.dart`
- `mobile/lib/features/user/mechanics_found_screen.dart`
- `mobile/lib/features/user/bidding_routes.dart`
- `mobile/lib/features/user/report_breakdown_screen.dart`
- `mobile/test/recommendation_test.dart`
- `mobile/test/bidding_navigation_test.dart`
- `mobile/test/breakdown_handoff_test.dart`

The existing temporary R03 rating-sort expectation was intentionally replaced
with an honest AI-unavailable fallback assertion; Cheapest/Fastest and booking
regressions remain. R01 GPS fixtures now provide controlled observations rather
than relying on production fallback coordinates. No unrelated work is removed.

## Validation

Final validation (2026-10-18):

| Check | Result |
| --- | --- |
| Full Flutter regression suite | 384 passed, 0 failed (28 additional R13 tests) |
| Full backend regression suite with local AI HTTP enabled | 209 passed, 0 failed, 1 isolated MongoDB integration test skipped (19 additional R13 tests) |
| FastAPI recommendation unittest suite | 23 passed, 0 failed |
| JavaScript syntax | 54 source/test files passed |
| Python AST syntax | 5 source/test files passed |
| Flutter analysis | 0 errors, 0 warnings; 66 pre-existing informational diagnostics; analyzer exits 1 for infos |
| `git diff --check` | Passed; Git also reports existing LF/CRLF conversion notices |

Tests cover formula/mapping/normalization, exact money, deterministic ties,
eligibility/radius/lease/account checks, privacy and ownership, upstream timeout
and malformed results, candidate limits, mutation during scoring, real local HTTP,
bid mapping, debounce/invalidation/expiry/stale responses, session isolation,
fallback/retry, Cheapest/Fastest, profile navigation, acceptance, and GPS failure.

The optional controlled Node-to-FastAPI HTTP integration runs with
`ONRAASTA_TEST_AI_HTTP=true` during backend tests. It launches an isolated local
FastAPI process and uses mocked MongoDB records, never production credentials.
Without that flag it is explicitly skipped. The existing isolated real MongoDB
transaction test remains subject to its separate safe replica-set requirement.

Physical-device GPS, two-phone behavior, deployed service connectivity, live
MongoDB transaction behavior and operational scaling remain UNVERIFIED.
