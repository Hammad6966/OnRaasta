from typing import Any

from fastapi import APIRouter, File, Request, UploadFile
from pydantic import BaseModel

router = APIRouter(prefix="/diagnose", tags=["diagnose"])

# ── Keyword map ───────────────────────────────────────────────────────────────

FAULT_KEYWORDS: dict[str, list[str]] = {
    "flat_tire":          ["flat", "tyre", "tire", "puncture", "wheel"],
    "dead_battery":       ["battery", "start", "jump", "dead", "charge"],
    "engine_overheating": ["hot", "overheat", "smoke", "temperature", "radiator"],
    "oil_leak":           ["oil", "leak", "drip", "stain", "brown"],
    "brake_failure":      ["brake", "stop", "squeak", "grinding"],
    "transmission_issue": ["gear", "transmission", "clutch", "shift"],
    "electrical_fault":   ["electric", "light", "fuse", "spark", "wire"],
    "fuel_problem":       ["fuel", "petrol", "diesel", "empty", "gauge"],
    "ac_fault":           ["ac", "cool", "air", "cold", "compressor"],
    "suspension_issue":   ["bumpy", "suspension", "shock", "bounce"],
    "coolant_leak":       ["coolant", "green", "radiator", "water"],
}


# ── Schemas ───────────────────────────────────────────────────────────────────

class TextDiagnoseRequest(BaseModel):
    text: str


class CostRange(BaseModel):
    min_pkr: int
    max_pkr: int


class TextDiagnoseResponse(BaseModel):
    fault_class:    str
    confidence:     float
    cost_range:     CostRange
    skill_required: str


# ── Helpers ───────────────────────────────────────────────────────────────────

def _match_fault(text: str) -> str | None:
    lowered = text.lower()
    for fault_class, keywords in FAULT_KEYWORDS.items():
        if any(kw in lowered for kw in keywords):
            return fault_class
    return None


# ── Routes ────────────────────────────────────────────────────────────────────

@router.post("/text", response_model=TextDiagnoseResponse)
async def diagnose_text(body: TextDiagnoseRequest, request: Request) -> Any:
    cost_ranges: dict = request.app.state.cost_ranges

    fault_class = _match_fault(body.text)

    if fault_class:
        entry = cost_ranges[fault_class]
        return {
            "fault_class":    fault_class,
            "confidence":     0.85,
            "cost_range":     {"min_pkr": entry["min_pkr"], "max_pkr": entry["max_pkr"]},
            "skill_required": entry["skill_required"],
        }

    # No keyword match
    unknown = cost_ranges["unknown"]
    return {
        "fault_class":    "unknown",
        "confidence":     0.0,
        "cost_range":     {"min_pkr": unknown["min_pkr"], "max_pkr": unknown["max_pkr"]},
        "skill_required": unknown["skill_required"],
    }


@router.post("/image")
async def diagnose_image(images: list[UploadFile] = File(...)) -> dict:
    # Mock response — real model integration goes here
    return {
        "detections": [
            {
                "class":      "flat_tire",
                "confidence": 0.75,
                "bbox":       [0, 0, 100, 100],
            }
        ],
        "combined_fault_class": "flat_tire",
    }
