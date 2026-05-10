import json
from pathlib import Path

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from routers import diagnose, recommend

app = FastAPI(title="OnRaasta AI Service", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(diagnose.router)
app.include_router(recommend.router)


@app.on_event("startup")
async def startup():
    data_path = Path(__file__).parent / "data" / "cost_ranges.json"
    with open(data_path, "r") as f:
        app.state.cost_ranges = json.load(f)
    print(f"Loaded {len(app.state.cost_ranges)} cost range entries")


@app.get("/health")
def health():
    return {"status": "ok"}


if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
