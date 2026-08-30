from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.api.account import router as account_router
from app.api.admin import router as admin_router
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
    description="AI orchestration API for v2 TFLite detection, Whisper, and GPT-5.4 mini.",
    version=settings.api_version,
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.parsed_cors_origins,
    allow_origin_regex=settings.cors_origin_regex,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health_router)
app.include_router(detect_router, prefix="/v1", tags=["detect"])
app.include_router(chat_router, prefix="/v1", tags=["chat"])
app.include_router(transcribe_router, prefix="/v1", tags=["transcribe"])
app.include_router(progress_router, prefix="/v1", tags=["progress"])
app.include_router(admin_router, prefix="/v1", tags=["admin"])
app.include_router(account_router, prefix="/v1", tags=["account"])

public_dir = Path(__file__).resolve().parents[1] / "public"
app.mount("/admin/assets", StaticFiles(directory=public_dir), name="admin-assets")


@app.middleware("http")
async def browser_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
    if request.url.path.startswith("/admin") or request.url.path.startswith("/v1/admin"):
        supabase_origin = settings.supabase_url.rstrip("/")
        response.headers["Cache-Control"] = "no-store"
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; "
            "script-src 'self'; "
            "style-src 'self'; "
            "img-src 'self' data: https://images.unsplash.com; "
            f"connect-src 'self' {supabase_origin}; "
            "font-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"
        )
    return response


@app.get("/admin/config", include_in_schema=False)
async def admin_public_config() -> dict[str, str | bool]:
    return {
        "supabaseUrl": settings.supabase_url,
        "supabaseAnonKey": settings.supabase_anon_key,
        "adminDataConfigured": bool(settings.supabase_service_role_key),
        "adminAuthRedirectUrl": settings.admin_auth_redirect_url,
    }


@app.get("/admin", include_in_schema=False)
async def admin_portal() -> FileResponse:
    return FileResponse(public_dir / "admin.html")


@app.get("/", tags=["root"])
async def root() -> dict[str, str]:
    return {
        "service": "cropcare-ai-backend",
        "docs": "/docs",
        "health": "/health",
    }