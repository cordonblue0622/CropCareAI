from __future__ import annotations

from pydantic import BaseModel, Field


class ProgressCheckInRequest(BaseModel):
    crop_type: str
    disease_name: str
    days_since_treatment: int = 0
    image_data_url: str | None = None
    completed_tasks: list[str] = []
    note: str | None = None
    current_health_score: float | None = None


class ProgressCheckInResponse(BaseModel):
    health_score: float = Field(..., ge=0, le=100)
    progress_status: str  # improving | stable | declining | critical
    assessment: str
    next_steps: list[str] = []
