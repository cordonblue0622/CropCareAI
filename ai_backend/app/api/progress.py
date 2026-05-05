from __future__ import annotations

import json

from fastapi import APIRouter, Depends

from app.core.config import get_settings
from app.core.dependencies import get_current_user
from app.schemas.progress import ProgressCheckInRequest, ProgressCheckInResponse
from app.schemas.user import AuthenticatedUser

router = APIRouter()


@router.post("/progress", response_model=ProgressCheckInResponse)
async def assess_crop_progress(
    payload: ProgressCheckInRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> ProgressCheckInResponse:
    settings = get_settings()
    return await _assess(payload, settings.openai_api_key, settings.openai_model)


async def _assess(
    payload: ProgressCheckInRequest,
    api_key: str | None,
    model: str,
) -> ProgressCheckInResponse:
    prev_score = payload.current_health_score or 50.0

    if not api_key:
        boost = min(10.0, len(payload.completed_tasks) * 2.5)
        return ProgressCheckInResponse(
            health_score=round(min(95.0, prev_score + boost), 1),
            progress_status="stable",
            assessment=(
                "AI model unavailable — score estimated from completed tasks."
            ),
            next_steps=["Continue your treatment plan", "Re-scan in 2–3 days"],
        )

    from openai import OpenAI

    client = OpenAI(api_key=api_key)

    task_text = (
        "\n".join(f"- {t}" for t in payload.completed_tasks)
        if payload.completed_tasks
        else "None reported"
    )

    system_prompt = (
        "You are CropCare AI, an expert plant health assessor. "
        "Analyze the attached crop photo and the context below to rate the plant's "
        "current health on a 0–100 scale (0 = dying, 100 = fully healthy). "
        "Return ONLY valid JSON with this exact structure: "
        '{"health_score": <number 0-100>, '
        '"progress_status": "<improving|stable|declining|critical>", '
        '"assessment": "<2-3 sentences describing what you observe>", '
        '"next_steps": ["<step 1>", "<step 2>", "<step 3>"]}'
    )

    user_content: list[dict] = [
        {
            "type": "input_text",
            "text": (
                f"Crop type: {payload.crop_type}\n"
                f"Known condition: {payload.disease_name}\n"
                f"Days since treatment started: {payload.days_since_treatment}\n"
                f"Previous health score: {prev_score}/100\n"
                f"Tasks completed today:\n{task_text}\n"
                f"Farmer note: {payload.note or 'None'}\n\n"
                "Rate the current health of this crop."
            ),
        }
    ]
    if payload.image_data_url:
        user_content.append(
            {"type": "input_image", "image_url": payload.image_data_url}
        )

    try:
        response = client.responses.create(
            model=model,
            input=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_content},
            ],
        )
        raw = response.output_text.strip()
        if raw.startswith("```"):
            raw = raw.split("\n", 1)[1].rsplit("```", 1)[0].strip()
        data = json.loads(raw)
        return ProgressCheckInResponse(
            health_score=float(max(0, min(100, data.get("health_score", prev_score)))),
            progress_status=str(data.get("progress_status", "stable")),
            assessment=str(data.get("assessment", "Assessment not available.")),
            next_steps=[str(s) for s in data.get("next_steps", [])],
        )
    except Exception as exc:
        return ProgressCheckInResponse(
            health_score=round(min(95.0, prev_score + len(payload.completed_tasks) * 2.0), 1),
            progress_status="stable",
            assessment=f"AI unavailable: {str(exc)[:80]}. Score estimated from tasks.",
            next_steps=["Continue treatment", "Try scanning again in 2 days"],
        )
