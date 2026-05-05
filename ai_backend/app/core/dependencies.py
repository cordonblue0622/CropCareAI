from functools import lru_cache

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.config import get_settings
from app.schemas.user import AuthenticatedUser
from app.services.auth_service import AuthService
from app.services.knowledge_service import KnowledgeService
from app.services.llm_service import LlmService
from app.services.whisper_service import WhisperService
from app.services.yolo_service import YoloService

bearer_scheme = HTTPBearer(auto_error=False)


@lru_cache
def get_auth_service() -> AuthService:
    return AuthService(settings=get_settings())


@lru_cache
def get_yolo_service() -> YoloService:
    return YoloService(settings=get_settings())


@lru_cache
def get_whisper_service() -> WhisperService:
    return WhisperService(settings=get_settings())


@lru_cache
def get_knowledge_service() -> KnowledgeService:
    return KnowledgeService(settings=get_settings())


@lru_cache
def get_llm_service() -> LlmService:
    return LlmService(settings=get_settings())


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    auth_service: AuthService = Depends(get_auth_service),
) -> AuthenticatedUser:
    settings = get_settings()
    if not settings.require_auth:
        return AuthenticatedUser(
            id="local-dev-user",
            email="local@example.com",
            role="developer",
        )
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token",
        )
    return await auth_service.verify_access_token(credentials.credentials)