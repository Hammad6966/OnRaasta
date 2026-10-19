# R12 ? history and booked commission accounting

## Canonical financial records
The accepted Bid provides agreed pricing. The existing acceptance transaction now freezes an additive `Job.agreedPricing` subdocument: currency=PKR, version=1, acceptedBidId, labourMinor, partsMinor, totalMinor. All amounts are integer paisa (100 paisa = PKR 1). Current labour/parts each retain the existing PKR 100,000,000 upper bound; labour minimum remains PKR 500. Total must equal labour + parts. API bid input accepts at most two decimal places; no epsilon-based acceptance of excess precision.

On the R06 `in_progress -> completed` transition, `Job.accounting` records the same price fields plus commissionBps=1500, commissionMinor, netMinor and recordedAt. Commission uses exact BigInt arithmetic: `(totalMinor * 15 + 50) / 100`, integer division, rounding half-up to the nearest paisa. Net is total minus rounded commission, conserving every paisa. Example: PKR 500.10 gross, PKR 75.02 commission, PKR 425.08 net. The one-paisa tie allocation favors the rounded commission; no independent rounding of the net creates extra currency.

Numeric legacy Bid fields are converted using their decimal string representation, not binary multiplication. Unsupported precision or inconsistent components fail safely. Existing confirmed snapshot values survive subsequent changes to Bid price fields. Assignment recovery uses frozen prices; legacy active assignments without a freeze may capture the intact accepted Bid when completed. Missing/foreign/inconsistent accepted records prevent completion with 409, without partial accounting. Valid existing snapshots are preserved. `finalCost` remains an untouched legacy optional field: there is no authorized price-adjustment workflow, so it is not a source for booked reports or a claim of final settlement.

## Exactly-once strategy
Completion uses the existing R06 MongoDB transaction and account/approved-mechanic guards, Job status/version compare-and-set, and terminal conflict behavior. Snapshot and completed status are one transactional Job update. Post-commit status events remain unchanged. Interrupted transactions roll back together; repeated/racing completion is 409 after one winner.

Reports derive from completed Job snapshots rather than incrementing mutable earnings counters. One Job contributes once; incomplete and cancelled jobs never contribute. Existing Mechanic.earnings and stored totalJobs are legacy caches, not the canonical report source. They are not incremented or relied on. Driver/mechanic self profiles, discovery, populated bid summaries and assignment summaries use actual completed-job counts. R08 ratings/reviews remain independent and unchanged.

## History APIs
All routes retain existing JWT purpose/session/account middleware. Identity comes from the verified JWT. Driver history uses the owning User ID. Mechanic history resolves the Mechanic document from that User. Mechanic self history/earnings remain readable while approval is pending/revoked, provided the account remains active and verified; this grants no dispatch, assignment mutation, or foreign Job access.

- GET /api/jobs: driver only; `{success:true,data:[safeJobRows],pagination}`. Default page 1, limit 20; max limit 50, max page 10000. Status may be any existing persisted enum or `active` (all six nonterminal states). Existing array envelope is preserved; old unbounded listing is now paginated. All actual mobile list consumers were updated; individual Job and assignment reads retain their routes.
- GET /api/mechanics/history: same pagination/status contract, scoped to the authenticated Mechanic document.
- GET /api/mechanics/earnings: mechanic only; `{success:true,data:{currency:'PKR',basis:'booked_not_paid',summary,jobs,pagination,undatedCompletedJobs}}`. Only completed jobs. Summary includes completedJobs, pricedJobs, unpricedJobs, exact decimal-string grossMinor/commissionMinor/netMinor, and up to 24 newest UTC monthly buckets plus moreMonths. Totals cover the entire selected range, not only the current row page. Sums use BigInt; strings prevent JSON number precision loss.
- History dates filter createdAt; earnings dates filter completedAt. Optional from/to use strict YYYY-MM-DD, UTC days with inclusive end day; reversed/invalid ranges are 400, explicit two-ended ranges at most 3660 days. Without dates, all-time reporting is supported. Unknown query keys, arbitrary mechanic IDs, invalid statuses and oversized pages are rejected.
- Rows contain real IDs, description, status, available dates/assignment IDs, safe mechanic name/shop summary and validated pricing. `pricingStatus` is booked, agreed, or unavailable. No phone/email, CNIC, credentials or contacts appear in history rows. Individual GET /api/jobs/:id remains ownership/assigned-mechanic/admin protected.
- GET /api/users/profile adds canonical driver statistics. GET /api/mechanics/profile adds booked statistics and overrides legacy totalJobs with the real completed count.
- Existing protected admin stats use the same canonical source. Legacy totalRevenue is a rupee display adapter; exact bookedTotals and revenueBasis clarify its meaning. Recent-job amounts are null if no valid completed snapshot exists. The existing admin table heading now says Booked Amount; no new admin pages/features were implemented.

## Legacy policy
Already-completed records without valid immutable accounting are unpriced, even if a live Bid or arbitrary finalCost exists. They count as completed work but not as zero-priced earnings. Reports disclose the unpriced count and totals cover priced jobs only. When every job is unpriced, Flutter shows Amount unavailable instead of a zero earning. Missing completion dates are disclosed separately; they cannot be placed into a dated period or monthly bucket.

No backfill or data migration was run. An optional future audited backfill must verify owner/Mechanic/Bid relationships, historical unmodified agreed prices, completion evidence and dates, preserve any valid snapshot, run in transactions, and emit an audit record. Do not blindly backfill from current Bid or finalCost values.

## Flutter integration
HistoryService uses the shared authenticated Dio client and the R09 session lifecycle. HistoryController owns screen data, pagination, filters, errors, exact IDs and earnings summaries. Epoch/generation checks ignore stale responses; logout/account changes and socket session end clear sensitive rows/totals. Newer filters cannot be overwritten by older requests. Failed refresh retains existing rows. Page merges deduplicate IDs. Socket reconnect/status notifications, foreground resume and explicit refresh reconcile with HTTP; listeners are removed individually. No polling, fake jobs, fake financial events or payment operations were added.

Driver history keeps dark cards, badges and All/Active/Completed/Cancelled filters. Real authorized Job details load by ID; confirmed assignment opening refetches the R05 contract and uses existing R06 routes, with completion still required before review. Fake receipt controls and sample cards were removed.

Mechanic earnings keeps the gradient and summary-card styling. All Time/This Month/This Year use actual UTC date queries. Gross booked, commission and calculated net are explicit; payment remains external. Real monthly subtotals, completed-job breakdowns, pagination and assigned-job history replace sample transactions and growth labels. Currency rendering uses BigInt paisa even for large aggregate strings. The existing bid preview uses the same integer commission convention and labels its amount Estimated Net.

## Deployment and verification limits
Additive Job subdocuments default to absent, leaving old records untouched. Declared non-unique indexes: `{userId:1,createdAt:-1,_id:-1}` and `{mechanicId:1,status:1,completedAt:-1}`. Initialize/verify via the controlled deployment process (`Job.createIndexes()`); no live index initialization occurred. Existing transaction-capable MongoDB replica-set requirement remains. No irreversible migration is required.

Financial reports stream the authenticated scope's completed records through a Mongo cursor and sum exactly in memory; they do not load whole history into a list. Output is bounded, but all-time report cost grows with completed history. Future materialized reporting can be added if measured scale requires it, while snapshots remain canonical. Offset pagination may shift under concurrent inserts; ID deduplication and refresh/reconnect reconciliation handle this, and summary totals never derive from the displayed page.

Physical phone verification and real replica-set transactions remain UNVERIFIED. The existing isolated integration test is retained and extended to race completion and verify snapshot/net totals, but remains SKIPPED without ONRAASTA_TEST_MONGO_URI. Firebase Storage, uploads, FCM, background GPS, payments, AI ranking and new admin pages remain deferred/out of scope. No production records, secrets, commits or pushes were changed.

## Exact R12 file manifest
backend/src/models/Job.js
backend/src/services/accounting.service.js
backend/src/services/history.service.js
backend/src/services/job-lifecycle.service.js
backend/src/services/assignment.service.js
backend/src/controllers/bids.controller.js
backend/src/controllers/jobs.controller.js
backend/src/controllers/mechanics.controller.js
backend/src/controllers/users.controller.js
backend/src/middleware/request-validation.js
backend/src/routes/jobs.routes.js
backend/src/routes/mechanics.routes.js
backend/src/routes/admin.routes.js
backend/test/fixtures.js
backend/test/security.test.js
backend/test/accounting.test.js
backend/test/mongo-concurrency.test.js
backend/ACCOUNTING_R12.md
mobile/lib/models/history_models.dart
mobile/lib/services/history_service.dart
mobile/lib/providers/history_controller.dart
mobile/lib/providers/profile_controller.dart
mobile/lib/providers/mechanic_presence_controller.dart
mobile/lib/core/widgets/history_job_card.dart
mobile/lib/features/user/job_history_screen.dart
mobile/lib/features/user/user_profile_screen.dart
mobile/lib/features/mechanic/mechanic_earnings_screen.dart
mobile/lib/features/mechanic/mechanic_home_screen.dart
mobile/lib/features/mechanic/submit_bid_screen.dart
mobile/lib/main.dart
mobile/test/history_test.dart
admin/app/page.tsx

## Final controlled validation
- Backend: 190 passed, 0 failed, 1 isolated MongoDB test skipped. Includes 25 new accounting/history tests. The pre-existing lifecycle security fixture now includes a genuine accepted Bid so its successful-completion assertion represents the actual assignment contract; authorization and state assertions were retained.
- Flutter: 356 passed, 0 failed, including 24 new history/earnings tests and the R01?R11 regression baseline.
- Flutter analyze --no-pub: 0 errors, 0 warnings, 66 remaining pre-existing informational diagnostics; no new R12 diagnostics. Analyzer exit code remains 1 because informational diagnostics remain.
- JavaScript syntax: all 52 backend source/test files passed node --check; the subsequently added schema test was also syntax-checked and executed.
- Admin TypeScript: tsc --noEmit --incremental false passed.
- git diff --check passed. Git's existing LF/CRLF notices are not whitespace failures.
- Real MongoDB transactions/index initialization and physical-phone behavior remain UNVERIFIED.
