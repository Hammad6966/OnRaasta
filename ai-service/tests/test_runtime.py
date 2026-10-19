import unittest
from routers.diagnose import _match_fault


class DiagnosisRuntimeTests(unittest.TestCase):
    def test_all_supported_fault_examples(self):
        examples = {
            "flat_tire": "flat tyre", "dead_battery": "battery dead",
            "engine_overheating": "engine overheating", "oil_leak": "oil dripping",
            "brake_failure": "brake failure", "transmission_issue": "transmission problem",
            "electrical_fault": "broken fuse", "fuel_problem": "petrol empty",
            "ac_fault": "air conditioner", "suspension_issue": "bumpy suspension",
            "coolant_leak": "coolant leak", "unknown": "unrecognized issue",
        }
        for expected, text in examples.items():
            with self.subTest(fault=expected):
                self.assertEqual(_match_fault(text) or "unknown", expected)

    def test_coolant_does_not_match_generic_oil_or_ac_keywords(self):
        for text in ["coolant", "Coolant leak", "green coolant dripping"]:
            self.assertEqual(_match_fault(text), "coolant_leak")
