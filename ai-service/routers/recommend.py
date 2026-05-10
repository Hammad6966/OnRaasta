import math
from typing import Any

from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter(prefix="/recommend", tags=["recommend"])


# ── Haversine (km) ────────────────────────────────────────────────────────────

def _haversine(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    R = 6371.0
    d_lat = math.radians(lat2 - lat1)
    d_lng = math.radians(lng2 - lng1)
    a = (
        math.sin(d_lat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(d_lng / 2) ** 2
    )
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


# ── Schema ────────────────────────────────────────────────────────────────────

class RecommendRequest(BaseModel):
    job:       dict
    mechanics: list


# ── Scoring ───────────────────────────────────────────────────────────────────

def _score(job: dict, mechanic: dict) -> float:
    # 1. Skill match
    required_skill: str = (
        job.get("aiDiagnosis", {}) or {}
    ).get("skill_required", "")
    skills: list[str] = mechanic.get("skills", [])

    if required_skill and required_skill in skills:
        skill_match = 1.0
    elif "General Mechanic" in skills:
        skill_match = 0.5
    else:
        skill_match = 0.0

    # 2. Inverse distance
    job_lat  = (job.get("location") or {}).get("lat", 0.0)
    job_lng  = (job.get("location") or {}).get("lng", 0.0)
    m_lat    = mechanic.get("lat", 0.0) or 0.0
    m_lng    = mechanic.get("lng", 0.0) or 0.0
    distance = _haversine(job_lat, job_lng, m_lat, m_lng)
    inverse_distance = max(0.0, min(1.0, 1.0 - (distance / 15.0)))

    # 3. Rating score
    rating_score = (mechanic.get("rating") or 0.0) / 5.0

    # 4. Inverse price (lowest accepted bid totalCost)
    bids: list[dict] = mechanic.get("bids", [])
    if bids:
        lowest = min((b.get("totalCost", 50000) for b in bids), default=50000)
    else:
        lowest = 50000
    inverse_price = max(0.0, min(1.0, 1.0 - (lowest / 50000.0)))

    return (
        0.35 * skill_match
        + 0.25 * inverse_distance
        + 0.25 * rating_score
        + 0.15 * inverse_price
    )


# ── Route ─────────────────────────────────────────────────────────────────────

@router.post("")
async def recommend(body: RecommendRequest) -> Any:
    scored = [
        {**mechanic, "score": round(_score(body.job, mechanic), 4)}
        for mechanic in body.mechanics
    ]
    scored.sort(key=lambda m: m["score"], reverse=True)
    return {"mechanics": scored}
