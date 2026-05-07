import json
from typing import Any

import httpx

from app.core.config import Settings


class SupabaseService:
    def __init__(self, settings: Settings):
        self._settings = settings

    @staticmethod
    def _parse_string_list(raw: Any) -> list[str]:
        if raw is None:
            return []
        if isinstance(raw, list):
            return [str(item).strip() for item in raw if str(item).strip()]
        if isinstance(raw, str):
            text = raw.strip()
            if not text:
                return []
            try:
                decoded = json.loads(text)
            except json.JSONDecodeError:
                return [text]
            if isinstance(decoded, list):
                return [str(item).strip() for item in decoded if str(item).strip()]
        return []

    async def get_user(self, access_token: str) -> dict[str, Any] | None:
        if not self._settings.supabase_url or not self._settings.supabase_service_role_key:
            return None

        url = f"{self._settings.supabase_url}/auth/v1/user"
        headers = {
            "Authorization": f"Bearer {access_token}",
            "apikey": self._settings.supabase_service_role_key,
        }

        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(url, headers=headers)
            if response.status_code >= 400:
                return None
            return response.json()

    async def fetch_knowledge(
        self,
        crop_type: str | None,
        disease_name: str | None,
        label_key: str | None = None,
    ) -> list[dict[str, Any]]:
        if not self._settings.supabase_url or not self._settings.supabase_service_role_key:
            return []

        url = f"{self._settings.supabase_url}/rest/v1/disease_knowledge"
        headers = {
            "apikey": self._settings.supabase_service_role_key,
            "Authorization": f"Bearer {self._settings.supabase_service_role_key}",
        }
        params = {
            "select": "label_key,disease_name,crop_type,description,source,treatment_steps",
            "limit": "5",
        }
        if label_key:
            params["label_key"] = f"eq.{label_key}"
        if crop_type:
            params["crop_type"] = f"eq.{crop_type}"
        if disease_name:
            params["disease_name"] = f"eq.{disease_name}"

        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(url, headers=headers, params=params)
            if response.status_code >= 400:
                return []
            rows = response.json()

        return [
            {
                "label_key": row.get("label_key") or "",
                "title": row.get("disease_name") or "Untitled",
                "crop_type": row.get("crop_type") or "unknown",
                "summary": row.get("description") or "",
                "source": row.get("source") or "supabase",
                "treatment_steps": self._parse_string_list(row.get("treatment_steps")),
            }
            for row in rows
        ]