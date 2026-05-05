from pathlib import Path

from fastapi import APIRouter

from app.core.config import get_settings

router = APIRouter(tags=["health"])


@router.get("/health")
async def health() -> dict[str, object]:
    settings = get_settings()
    return {
        "status": "ok",
        "environment": settings.app_env,
        "version": settings.api_version,
        "mockServices": settings.enable_mock_services,
        "models": {
            "yoloConfigured": Path(settings.yolo_model_path).exists(),
            "whisperConfigured": bool(settings.whisper_model_size),
            "openaiConfigured": bool(settings.openai_api_key),
        },
    }