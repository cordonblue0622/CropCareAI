import base64
import binascii
import json

from fastapi import HTTPException, status

from app.core.config import Settings
from app.schemas.user import AuthenticatedUser
from app.services.supabase_service import SupabaseService


class AuthService:
    def __init__(self, settings: Settings):
        self._settings = settings
        self._supabase = SupabaseService(settings)

    async def verify_access_token(self, access_token: str) -> AuthenticatedUser:
        if not self._settings.supabase_url or not self._settings.supabase_service_role_key:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Supabase auth is not configured on the backend.",
            )

        user_payload = await self._supabase.get_user(access_token)
        if not user_payload:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid access token.",
            )

        app_metadata = user_payload.get("app_metadata")
        trusted_metadata = app_metadata if isinstance(app_metadata, dict) else {}
        admin_role = str(trusted_metadata.get("admin_role") or "").strip().lower()

        return AuthenticatedUser(
            id=user_payload.get("id", ""),
            email=user_payload.get("email"),
            role=admin_role or "authenticated",
            assurance_level=self._assurance_level(access_token),
        )

    @staticmethod
    def _assurance_level(access_token: str) -> str:
        try:
            payload = access_token.split(".")[1]
            payload += "=" * (-len(payload) % 4)
            claims = json.loads(base64.urlsafe_b64decode(payload))
        except (IndexError, ValueError, binascii.Error, json.JSONDecodeError):
            return "aal1"
        return "aal2" if isinstance(claims, dict) and claims.get("aal") == "aal2" else "aal1"