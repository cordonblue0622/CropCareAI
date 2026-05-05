from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.chat import router as chat_router
from app.api.detect import router as detect_router
from app.api.health import router as health_router
from app.api.progress import router as progress_router
from app.api.transcribe import router as transcribe_router
from app.core.config import get_settings
from app.utils.logger import configure_logging


@asynccontextmanager
async def lifespan(_: FastAPI):
    settings = get_settings()
    configure_logging(settings.log_level)
    yield


settings = get_settings()

app = FastAPI(
    title="CropCare AI Backend",
    description="AI orchestration API for YOLO, Whisper, and GPT-5.4 mini.",
    version=settings.api_version,
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.parsed_cors_origins,
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health_router)
app.include_router(detect_router, prefix="/v1", tags=["detect"])
app.include_router(chat_router, prefix="/v1", tags=["chat"])
app.include_router(transcribe_router, prefix="/v1", tags=["transcribe"])
app.include_router(progress_router, prefix="/v1", tags=["progress"])


@app.get("/", tags=["root"])
async def root() -> dict[str, str]:
    return {
        "service": "cropcare-ai-backend",
        "docs": "/docs",
        "health": "/health",
    }