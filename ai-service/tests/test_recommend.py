import copy
import json
import unittest
from fastapi import FastAPI
from pydantic import ValidationError
from routers.recommend import RecommendRequest, rank, _haversine, POLICY, router

JOB = "000000000000000000000001"
def candidate(number=2, **values):
    return {"bidId": f"{number:024x}", "mechanicId": f"{number + 100:024x}", "lat": 31.0, "lng": 74.0,
            "serviceRadius": 15.0, "skills": ["Battery"], "rating": 4.0,
            "labourMinor": 50000, "partsMinor": 0, "totalMinor": 50000, **values}
def body(candidates=None, fault="dead_battery"):
    return {"job": {"jobId": JOB, "location": {"lat": 31.0, "lng": 74.0}, "aiDiagnosis": {"fault_class": fault, "skill_required": "Auto Electrician"}},
            "mechanics": [candidate()] if candidates is None else candidates}
def score(**values):
    return rank(RecommendRequest.model_validate(body([candidate(**values)]))).mechanics[0]

class FormulaTests(unittest.TestCase):
    def test_exact_weights_and_bounded_components(self):
        result = score()
        self.assertEqual(result.score, 0.9485)
        self.assertEqual(result.components.model_dump(), {"skillMatch": 1.0, "distanceScore": 1.0, "ratingScore": 0.8, "priceScore": 0.99})
        self.assertEqual(sum(float(w) for w in POLICY["weights"].values()), 1.0)

    def test_multiple_skills_do_not_multiply_match(self):
        result = score(skills=["Brakes", "Battery", "Engine Repair"])
        self.assertEqual(result.components.skillMatch, 1)
        self.assertEqual(result.matchedSkills, ["Battery"])
        self.assertEqual(result.score, score().score)

    def test_profile_and_specialist_labels_match(self):
        for label in ["Battery", "Electrical", "Auto Electrician", "  battery  "]:
            self.assertEqual(score(skills=[label]).components.skillMatch, 1)

    def test_tire_alias_is_explicit(self):
        self.assertEqual(rank(RecommendRequest.model_validate(body([candidate(skills=["Tire Change"])], "flat_tire"))).mechanics[0].components.skillMatch, 1)

    def test_general_fallback_is_partial_for_known_fault(self):
        self.assertEqual(score(skills=["General Mechanic"]).components.skillMatch, 0.5)

    def test_unknown_fault_never_implies_qualification(self):
        for fault in ["unknown", "not_a_known_fault"]:
            result = rank(RecommendRequest.model_validate(body([candidate(skills=["General Mechanic", "Battery"])], fault))).mechanics[0]
            self.assertEqual(result.components.skillMatch, 0)
            self.assertEqual(result.matchedSkills, [])

    def test_empty_diagnosis_is_conservative(self):
        data = body(); data["job"]["aiDiagnosis"] = None
        self.assertEqual(rank(RecommendRequest.model_validate(data)).mechanics[0].components.skillMatch, 0)

    def test_missing_rating_contributes_zero_without_inventing_rating(self):
        result = score(rating=None)
        self.assertTrue(result.ratingMissing)
        self.assertEqual(result.components.ratingScore, 0)
        self.assertEqual(result.score, 0.7485)

    def test_rating_normalization(self):
        self.assertEqual(score(rating=5.0).components.ratingScore, 1)
        self.assertEqual(score(rating=0.0).components.ratingScore, 0)

    def test_haversine_known_arc_and_antipodes(self):
        self.assertAlmostEqual(_haversine(0, 1, 0, 2), 111.19492664455873, places=8)
        self.assertAlmostEqual(_haversine(31, 74, 31, 74), 0)
        self.assertGreater(_haversine(90, 0, -90, 180), 20000)

    def test_configured_radius_excludes_outside_candidate(self):
        data = body([candidate(lat=31.1, serviceRadius=1.0)])
        self.assertEqual(rank(RecommendRequest.model_validate(data)).mechanics, [])
        data["mechanics"][0]["serviceRadius"] = 15.0
        self.assertEqual(len(rank(RecommendRequest.model_validate(data)).mechanics), 1)

    def test_distance_scale_remains_fifteen_km(self):
        result = score(lat=31.05)
        self.assertAlmostEqual(result.components.distanceScore, 1 - result.distanceKm / 15)

    def test_price_scale_uses_exact_paisa(self):
        self.assertEqual(score().components.priceScore, 0.99)
        self.assertEqual(score(partsMinor=4950000, totalMinor=5000000).components.priceScore, 0)
        self.assertEqual(score(partsMinor=9950000, totalMinor=10000000).components.priceScore, 0)

    def test_single_bid_gets_its_actual_components(self):
        self.assertEqual(len(rank(RecommendRequest.model_validate(body())).mechanics), 1)
        self.assertLess(score().score, 1)

    def test_paisa_price_difference_preserves_order(self):
        data = body([candidate(3, partsMinor=1, totalMinor=50001), candidate(2)])
        result = rank(RecommendRequest.model_validate(data)).mechanics
        self.assertEqual([r.bidId for r in result], [f"{2:024x}", f"{3:024x}"])
        self.assertGreater(result[0].score, result[1].score)

    def test_equal_score_tie_breaks_by_bid_id(self):
        data = body([candidate(9), candidate(3)])
        self.assertEqual([r.bidId for r in rank(RecommendRequest.model_validate(data)).mechanics], [f"{3:024x}", f"{9:024x}"])

    def test_policy_matches_persisted_diagnosis_vocabulary(self):
        from pathlib import Path
        costs = json.loads((Path(__file__).parent.parent / "data" / "cost_ranges.json").read_text())
        self.assertEqual(set(costs), set(POLICY["faultSkills"]))
        for fault, entry in costs.items():
            if fault != "unknown": self.assertIn(entry["skill_required"], POLICY["faultSkills"][fault])

    def test_input_is_not_mutated(self):
        data = body(); original = copy.deepcopy(data)
        rank(RecommendRequest.model_validate(data))
        self.assertEqual(data, original)

    def test_duplicate_bid_and_oversized_input_rejected(self):
        for data in [body([candidate(), candidate()]), body([candidate(i) for i in range(101)])]:
            with self.assertRaises(ValidationError): RecommendRequest.model_validate(data)

    def test_invalid_numeric_and_price_values_rejected(self):
        for values in [{"lat": 91.0}, {"lng": -181.0}, {"lat": float("nan")}, {"rating": 6.0}, {"rating": float("inf")},
                       {"serviceRadius": 101.0}, {"totalMinor": 0}, {"partsMinor": -1}, {"totalMinor": 50000.5}, {"labourMinor": 49999, "totalMinor": 49999}]:
            with self.assertRaises(ValidationError): RecommendRequest.model_validate(body([candidate(**values)]))

    def test_missing_location_and_injected_properties_rejected(self):
        for prop in ["lat", "lng"]:
            data = body(); del data["mechanics"][0][prop]
            with self.assertRaises(ValidationError): RecommendRequest.model_validate(data)
        data = body(); data["mechanics"][0]["documents"] = {"cnic": "private"}
        with self.assertRaises(ValidationError): RecommendRequest.model_validate(data)

class EndpointTests(unittest.IsolatedAsyncioTestCase):
    async def post(self, payload):
        app = FastAPI(); app.include_router(router)
        messages = []; sent = False
        async def receive():
            nonlocal sent
            if sent: return {"type": "http.disconnect"}
            sent = True
            return {"type": "http.request", "body": json.dumps(payload).encode(), "more_body": False}
        async def send(message): messages.append(message)
        await app({"type": "http", "asgi": {"version": "3.0"}, "http_version": "1.1", "method": "POST", "scheme": "http", "path": "/recommend", "raw_path": b"/recommend", "query_string": b"", "headers": [(b"content-type", b"application/json")], "client": ("127.0.0.1", 1), "server": ("fixture", 80)}, receive, send)
        return messages[0]["status"], json.loads(b"".join(m.get("body", b"") for m in messages[1:]))

    async def test_route_returns_typed_safe_ids_and_factors(self):
        status, result = await self.post(body())
        self.assertEqual(status, 200)
        self.assertEqual(result["policyVersion"], "weighted_rules_v1")
        self.assertEqual(result["mechanics"][0]["bidId"], f"{2:024x}")
        self.assertNotIn("lat", result["mechanics"][0])

    async def test_malformed_http_input_returns_422(self):
        for data in [{}, body([{"mechanicId": f"{3:024x}"}]), body([candidate(totalMinor=0)]), body([candidate(bidId="forged")])]:
            status, _ = await self.post(data)
            self.assertEqual(status, 422)

if __name__ == "__main__": unittest.main()
