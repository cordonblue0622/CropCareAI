from __future__ import annotations

import asyncio
import json
import logging
import math
import time

from fastapi import APIRouter, Depends, HTTPException

from app.core.config import get_settings
from app.core.dependencies import get_current_user
from app.schemas.progress import ProgressCheckInRequest, ProgressCheckInResponse
from app.schemas.user import AuthenticatedUser

router = APIRouter()
logger = logging.getLogger(__name__)
PROGRESS_TIMEOUT_SECONDS = 65


def _normalize_crop(value: object) -> str:
    normalized = str(value or "").strip().lower()
    aliases = {
        "bell pepper": "pepper",
        "capsicum": "pepper",
        "bok choy": "pechay",
        "bokchoy": "pechay",
    }
    return aliases.get(normalized, normalized)


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
    prev_score = payload.current_health_score if payload.current_health_score is not None else 50.0
    if not payload.image_data_url or not payload.image_data_url.strip():
        raise HTTPException(status_code=422, detail="Please attach a clear current crop photo.")

    if not api_key:
        raise HTTPException(status_code=503, detail="Photo validation is temporarily unavailable. Please try again.")

    from openai import AsyncOpenAI

    task_text = (
        "\n".join(f"- {t}" for t in payload.completed_tasks)
        if payload.completed_tasks
        else "None reported"
    )

    system_prompt = (
        "You are CropCare AI, an expert crop progress assessor for daily check-ins. "
        "Compare the CURRENT check-in photo against the PREVIOUS progress context when it is provided. "
        "Rate the crop's current health on a 0–100 scale (0 = dying, 100 = fully healthy) and decide whether the daily check-in should be accepted. "
        "Reject the check-in if the current photo is clearly NOT showing the tracked crop at all (e.g., a random selfie, a completely unrelated object, or obviously a different type of plant entirely), "
        "or if it is obviously a screenshot or screen photo of another image. "
        "Accept identifiable crop photos even if the crop looks healthy, partially recovered, at an unusual angle, or the disease is no longer visible — these are all valid progress check-ins. "
        "If the crop cannot be identified confidently because the photo is unclear, return accepted=false and ask for a clearer photo. "
        "Validate crop type, not whether it is the exact same individual plant. "
        "DISEASE SCORING RULE: If 'Known condition' names a specific disease (not just the crop name or 'None'), "
        "and the current check-in photo shows visible disease symptoms (discoloration, lesions, wilting, mold, spots, etc.), "
        "the health score MUST reflect the active disease burden — score between 20 and 65 for active visible disease. "
        "Do NOT score above 70 unless the photo clearly shows the disease symptoms have substantially resolved or are absent. "
        "Return ONLY valid JSON with this exact structure: "
        '{"accepted": <true|false>, "observed_crop": "<tomato|pepper|squash|eggplant|pechay|unknown>", '
        '"rejection_reason": "<short redo instruction or empty>", '
        '"health_score": <number 0-100>, '
        '"progress_status": "<improving|stable|declining|critical>", '
        '"assessment": "<2-3 sentences describing what you observe and how it changed>", '
        '"next_steps": ["<step 1>", "<step 2>", "<step 3>"]}. '
        "If accepted is false, keep health_score close to the previous score, set progress_status to stable unless the image clearly shows a serious issue, keep next_steps empty, and use rejection_reason to ask for a new proper crop photo."
    )

    previous_assessment = payload.previous_assessment or "None"
    previous_status = payload.previous_progress_status or "unknown"
    previous_update_date = payload.previous_update_date or "unknown"

    user_content: list[dict] = [
        {
            "type": "input_text",
            "text": (
                f"Crop type: {payload.crop_type}\n"
                f"Known condition: {payload.disease_name}\n"
                f"Days since treatment started: {payload.days_since_treatment}\n"
                f"Previous health score: {prev_score}/100\n"
                f"Previous progress status: {previous_status}\n"
                f"Previous update date: {previous_update_date}\n"
                f"Previous assessment summary: {previous_assessment}\n"
                f"Tasks completed today:\n{task_text}\n"
                f"Farmer note: {payload.note or 'None'}\n\n"
                "Compare the current check-in against the previous progress context when available, then decide whether to accept this check-in."
            ),
        }
    ]
    if payload.previous_image_reference:
        user_content.append(
            {"type": "input_text", "text": "Previous progress photo for comparison:"}
        )
        user_content.append(
            {"type": "input_image", "image_url": payload.previous_image_reference}
        )
    if payload.image_data_url:
        user_content.append(
            {"type": "input_text", "text": "Current check-in photo to assess now:"}
        )
        user_content.append(
            {"type": "input_image", "image_url": payload.image_data_url}
        )

    started = time.monotonic()
    try:
        async with AsyncOpenAI(api_key=api_key, timeout=60.0, max_retries=0) as client:
            response = await asyncio.wait_for(
                client.responses.create(
                    model=model,
                    input=[
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": user_content},
                    ],
                ),
                timeout=PROGRESS_TIMEOUT_SECONDS,
            )
        raw = response.output_text.strip()
        if raw.startswith("```"):
            raw = raw.split("\n", 1)[1].rsplit("```", 1)[0].strip()
        data = json.loads(raw)
        if not isinstance(data, dict) or type(data.get("accepted")) is not bool:
            raise ValueError("Missing or invalid acceptance decision")
        score = data.get("health_score")
        if type(score) not in (int, float) or not math.isfinite(score) or not 0 <= score <= 100:
            raise ValueError("Invalid health score")
        if data.get("progress_status") not in {"improving", "stable", "declining", "critical"}:
            raise ValueError("Invalid progress status")
        if not isinstance(data.get("assessment"), str) or not data["assessment"].strip():
            raise ValueError("Missing assessment")
        if not isinstance(data.get("next_steps"), list) or not all(isinstance(s, str) for s in data["next_steps"]):
            raise ValueError("Invalid next steps")
        accepted = data["accepted"]
        tracked_crop = _normalize_crop(payload.crop_type)
        observed_crop = _normalize_crop(data.get("observed_crop"))
        raw_reason = data.get("rejection_reason")
        rejection_reason = raw_reason.strip() or None if isinstance(raw_reason, str) else None
        health_score = float(max(0, min(100, data.get("health_score", prev_score))))
        progress_status = str(data.get("progress_status", "stable"))
        assessment = str(data.get("assessment", "Assessment not available."))
        next_steps = [str(s) for s in data.get("next_steps", [])]
        if observed_crop != tracked_crop:
            accepted = False
            rejection_reason = (
                f"The photo could not be verified as your tracked {tracked_crop} crop. "
                "Please submit a clear close-up photo of that crop."
            )
            health_score = prev_score
            progress_status = "stable"
            assessment = (
                f"The AI could not confirm that this image shows the tracked {tracked_crop} crop, "
                "so it was not used to update the health trend."
            )
            next_steps = []
        if not accepted:
            health_score = prev_score
            next_steps = []
            progress_status = "stable"
            rejection_reason = rejection_reason or "Please upload a clear photo of the crop you are monitoring and try again."
        logger.info("Progress validation decision: accepted=%s", accepted)
        return ProgressCheckInResponse(
            accepted=accepted,
            rejection_reason=rejection_reason,
            health_score=health_score,
            progress_status=progress_status,
            assessment=assessment,
            next_steps=next_steps,
        )
    except (TimeoutError, asyncio.TimeoutError) as exc:
        raise HTTPException(status_code=504, detail="Photo validation timed out. Please try again.") from exc
    except Exception as exc:
        logger.warning("Progress validation failed: %s", type(exc).__name__)
        raise HTTPException(status_code=502, detail="Photo validation could not finish. Please try again.") from exc
    finally:
        logger.info("Progress validation finished in %.3fs", time.monotonic() - started)
