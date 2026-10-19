"""Deterministic weighted recommendation rules; no trained model is claimed."""
import json
import math
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from typing import Annotated
from fastapi import APIRouter
from pydantic import BaseModel, ConfigDict, Field, model_validator

router = APIRouter(prefix="/recommend", tags=["recommend"])
POLICY = json.loads((Path(__file__).parent.parent / "data" / "recommendation_policy.json").read_text())
Id = Annotated[str, Field(pattern=r"^[a-f0-9]{24}$")]
Unit = Annotated[float, Field(ge=0, le=1)]
Minor = Annotated[int, Field(ge=0, le=20_000_000_000)]

class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, allow_inf_nan=False)

class Coordinates(StrictModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)

    @model_validator(mode="after")
    def real_point(self):
        if self.lat == 0 and self.lng == 0:
            raise ValueError("An actual location is required")
        return self

class Diagnosis(StrictModel):
    fault_class: str = Field(default="unknown", max_length=64)
    skill_required: str | None = Field(default=None, max_length=100)

class JobInput(StrictModel):
    jobId: Id
    location: Coordinates
    aiDiagnosis: Diagnosis | None = None

class Candidate(Coordinates):
    bidId: Id
    mechanicId: Id
    skills: list[Annotated[str, Field(min_length=1, max_length=100)]] = Field(default_factory=list, max_length=16)
    rating: float | None = Field(default=None, ge=0, le=5)
    serviceRadius: float = Field(ge=1, le=100)
    labourMinor: Minor
    partsMinor: Minor
    totalMinor: Minor

    @model_validator(mode="after")
    def supported_quote(self):
        if self.labourMinor < 50000 or self.labourMinor > 10000000000 or self.partsMinor > 10000000000 or self.labourMinor + self.partsMinor != self.totalMinor:
            raise ValueError("Invalid quoted components")
        return self

class RecommendRequest(StrictModel):
    job: JobInput
    mechanics: list[Candidate] = Field(max_length=100)

    @model_validator(mode="after")
    def distinct_bids(self):
        if len({c.bidId for c in self.mechanics}) != len(self.mechanics):
            raise ValueError("Duplicate bid IDs")
        return self

class Components(StrictModel):
    skillMatch: Unit
    distanceScore: Unit
    ratingScore: Unit
    priceScore: Unit

class RankedCandidate(StrictModel):
    bidId: Id
    mechanicId: Id
    totalMinor: Minor
    score: Unit
    components: Components
    distanceKm: float = Field(ge=0, le=100)
    ratingMissing: bool
    matchedSkills: list[str]

class RecommendResponse(StrictModel):
    policyVersion: str
    mechanics: list[RankedCandidate]


def _haversine(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    a = math.sin(math.radians(lat2 - lat1) / 2) ** 2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(math.radians(lng2 - lng1) / 2) ** 2
    a = min(1.0, max(0.0, a))
    return 6371.0 * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _skill(value: str) -> str:
    key = " ".join(value.casefold().split())
    return POLICY["aliases"].get(key, key)


def rank(body: RecommendRequest) -> RecommendResponse:
    fault = body.job.aiDiagnosis.fault_class.strip().lower() if body.job.aiDiagnosis else "unknown"
    required = {_skill(s) for s in POLICY["faultSkills"].get(fault, [])}
    scored = []
    for candidate in body.mechanics:
        distance = _haversine(body.job.location.lat, body.job.location.lng, candidate.lat, candidate.lng)
        # Defense in depth: the Node presence snapshot also enforces radius.
        if distance > candidate.serviceRadius:
            continue
        matches = sorted({s for s in candidate.skills if _skill(s) in required})
        skill = Decimal(1) if matches else Decimal("0.5") if required and any(_skill(s) == "general mechanic" for s in candidate.skills) else Decimal(0)
        parts = {"skillMatch": skill,
                 "distanceScore": max(Decimal(0), Decimal(1) - Decimal(str(distance)) / Decimal(POLICY["distanceScaleKm"])),
                 "ratingScore": Decimal(str(candidate.rating)) / 5 if candidate.rating is not None else Decimal(0),
                 "priceScore": max(Decimal(0), Decimal(1) - Decimal(candidate.totalMinor) / Decimal(POLICY["priceScaleMinor"]))}
        score = sum(Decimal(POLICY["weights"][k]) * value for k, value in parts.items()).quantize(Decimal("0.000000000001"), rounding=ROUND_HALF_UP)
        scored.append(RankedCandidate(bidId=candidate.bidId, mechanicId=candidate.mechanicId, totalMinor=candidate.totalMinor,
            score=float(score), components=Components(**{k: float(v) for k, v in parts.items()}),
            distanceKm=distance, ratingMissing=candidate.rating is None, matchedSkills=matches))
    scored.sort(key=lambda c: (-Decimal(str(c.score)), c.bidId, c.mechanicId))
    return RecommendResponse(policyVersion=POLICY["version"], mechanics=scored)


@router.post("", response_model=RecommendResponse)
async def recommend(body: RecommendRequest) -> RecommendResponse:
    return rank(body)
