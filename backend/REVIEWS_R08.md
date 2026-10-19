# R08 — Verified reviews and reputation

## Submission

`POST /api/jobs/:id/review` retains its authenticated driver route, general API rate limit, `{success, message}` envelope and HTTP 200 success. The response now additionally includes:

```
data: {
  jobId, mechanicId,
  review: { stars, tags, comment, createdAt },
  reputation: { rating, reviewCount, distribution: {1,2,3,4,5} }
}
```

Only the active verified owning driver may submit. Identity comes from the access JWT. The saved Job must be completed and contain an existing Mechanic profile and an accepted Bid with matching Job/profile IDs. No mechanic/user/aggregate fields are accepted from the client. A revoked mechanic can still receive an honest review of previously completed work; current approval is not a prerequisite for reviewing historical work.

Stars must be an integer 1–5. At most three distinct supported tags are accepted, matching the existing UI: Professional, On Time, Fair Price, Quality Work, Friendly, Clean Work, Skilled, Fast Service. Comments are optional, maximum 300 JavaScript/Flutter string code units, trimmed, with HTML tags and control characters removed. Comments are plain text, never rendered as HTML.

Malformed input: 400. Missing/invalid/expired/wrong-purpose access token: 401. Foreign owner/wrong role/inactive or unverified account: 403. Missing Job: 404. Incomplete/cancelled/already-reviewed/inconsistent assignment: 409. Internal failures use existing safe error middleware.

## Atomicity and reputation

A MongoDB transaction writes the authenticated account guard, locks the assigned Mechanic document, conditionally writes the one Job review, recomputes valid evidence and updates rating/reviewCount before commit. All submissions for the same mechanic write the same Mechanic document, so transaction conflict retries obtain fresh snapshots rather than overwriting another review's aggregate. Duplicate submissions cannot commit two reviews. Failures roll back both the review and reputation. There is no standalone/nontransactional fallback.

Evidence uses the **Mechanic document ID**, not its User ID. Only completed Jobs with integer 1–5 stars, a valid review date and a matching accepted Bid contribute. Average is stored to two decimal places; existing compact UI displays one decimal place. Zero evidence produces rating 0/count 0 and all-zero distribution. Review submission does not change lifecycle status, accepted prices, earnings or commission.

`Mechanic.reviewCount` is additive with default zero; rating now has 0–5 bounds. The Job review schema validates integer stars and supported unique tags. No destructive migration or production data operation was performed. Review reads lazily repair stale historical cached reputation, in a transaction serialized with new submissions. No bulk backfill is required.

## Safe read contract

`GET /api/mechanics/:mechanicId/reviews?page=1&limit=10`

Requires an active verified authenticated account. Approved profiles are readable by authenticated accounts; unapproved profiles are readable only by their owning mechanic or an administrator. IDs and pagination are validated. Page is 1–999999; limit is 1–50, default 10; unknown query parameters are rejected.

```
{ success: true, data: {
  mechanicId, rating, reviewCount, distribution,
  reviews: [{stars, tags, comment, createdAt}],
  page, limit, hasMore
} }
```

Newest review first, with Job ID as deterministic internal tie breaker. No reviewer identity, phone, email, Job ID, credentials or documents are returned. UI labels authors anonymously as "Verified customer". Empty pages/reputations are explicit. Responses are bounded; the current FYP implementation scans selected evidence for the requested mechanic to validate historical assignment integrity and calculate aggregates. Very large review volumes would benefit from database-side aggregate/page optimization. Pagination is offset-based, not a snapshot across requests.

Stored reviewCount is included in existing bid population/socket bid payload, assignment safe projection and nearby discovery. Profile screens also use the fresh safe review summary, avoiding stale navigation snapshots.

## Flutter and lifecycle

The existing review layout, stars, animation, tags, comment field and design tokens are preserved. ReviewService uses the shared ApiService and its `access_token` interceptor; it never reads the obsolete `token` key. A shared ReviewFormController independently reloads assignment identity and completed state on entry and immediately before submission. Job, accepted Bid and Mechanic profile IDs must all match the navigation contract.

The form disables submission until verified, rejects duplicate pending taps and waits for a valid server confirmation. 401/403/404 disable further submission until re-verification. A 409 reloads authoritative review state; already reviewed Jobs display "Review submitted" without claiming a new successful write. Recoverable failures preserve stars, tags and comment. Confirmed success returns to the existing driver home. Typed R03/R05 navigation is retained.

R06 Job In Progress gates review entry on a fresh completed Job and now disables the action for already-reviewed Jobs. It reloads after returning from the form. R05's existing authenticated closed-assignment recovery permits recent completed Jobs to be reopened after restart; direct assignment retrieval retains saved IDs. The existing recovery list remains bounded to ten recent closed assignments; full history remains R12. Cancelled Jobs never become reviewable. No socket event automatically opens a review screen.

Mechanic Ratings and the driver-facing mechanic profile share the real-data review panel, retaining the original summary/distribution/card styles. The panel has loading, retry, zero-review and bounded load-more states. Fabricated reviews, names, historical dates, averages and distributions have been removed. A nonfunctional report tap was removed rather than pretending to submit reports. No R11 profile editor/R12 earnings/history implementation was added.

## Verification

- Flutter: 270 tests passed (239 retained plus 31 new R08 tests).
- Backend: 129 passed (111 retained plus 18 new R08 tests), one optional MongoDB integration test skipped.
- The existing optional isolated replica-set integration test was retained and extended with duplicate/concurrent review reputation checks. It uses only its randomly named test database. No test URI was available; real MongoDB transaction behavior remains UNVERIFIED.
- Two legacy Flutter assertions for the now-removed static "reviews unavailable" placeholder now assert the retry state when their old fixture does not supply the new review endpoint. Existing navigation/identity checks remain. The security fixture now seeds a legitimate accepted Bid for its completed-review success case.
- JavaScript syntax: all 44 source/test files passed.
- Flutter analysis: zero errors/new diagnostics; 85 existing diagnostics remain (one warning and 84 info; down from the 89-diagnostic baseline). Analysis exits nonzero because existing diagnostics remain.
- `git diff --check`: passed.
- Physical-device/end-to-end testing remains UNVERIFIED. No dependencies, platform permissions, environment/production credentials, payment model, commits or pushes changed.

## Exact R08 file manifest

- backend/src/services/review.service.js (new)
- backend/src/utils/review-policy.js (new)
- backend/src/routes/jobs.routes.js
- backend/src/routes/mechanics.routes.js
- backend/src/models/Job.js
- backend/src/models/Mechanic.js
- backend/src/middleware/request-validation.js
- backend/src/services/assignment.service.js
- backend/src/controllers/bids.controller.js
- backend/src/controllers/mechanics.controller.js
- backend/test/review.test.js (new)
- backend/test/security.test.js
- backend/test/mongo-concurrency.test.js
- backend/REVIEWS_R08.md (new)
- mobile/lib/services/review_service.dart (new)
- mobile/lib/providers/review_form_controller.dart (new)
- mobile/lib/core/widgets/mechanic_reviews_panel.dart (new)
- mobile/lib/features/user/rate_review_screen.dart
- mobile/lib/features/mechanic/mechanic_ratings_screen.dart
- mobile/lib/features/user/mechanic_profile_view.dart
- mobile/lib/features/user/job_in_progress_screen.dart
- mobile/lib/features/user/bidding_routes.dart
- mobile/test/review_test.dart (new)
- mobile/test/bidding_navigation_test.dart
