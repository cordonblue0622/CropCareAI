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

    @staticmethod
    def _format_day_steps(day_rows: list[dict[str, Any]]) -> list[str]:
        lines: list[str] = []
        for row in sorted(day_rows, key=lambda r: int(r.get("day_number") or 0)):
            day_n = row.get("day_number")
            title = (row.get("day_title") or "").strip()
            tasks = SupabaseService._parse_string_list(row.get("tasks"))
            note = (row.get("notes") or "").strip()
            head = f"Day {day_n}: {title}".strip()
            if tasks:
                task_text = "; ".join(tasks)
                lines.append(f"{head} — {task_text}" + (f" (Note: {note})" if note else ""))
            elif head:
                lines.append(head + (f" — {note}" if note else ""))
        return lines

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

    async def _fetch_treatment_day_steps(
        self,
        client: httpx.AsyncClient,
        base_headers: dict[str, str],
        dkb_id: str,
    ) -> list[dict[str, Any]]:
        url = f"{self._settings.supabase_url}/rest/v1/disease_treatment_day_steps"
        params = {
            "disease_knowledge_base_id": f"eq.{dkb_id}",
            "is_active": "eq.true",
            "select": "day_number,day_title,tasks,notes",
            "order": "day_number.asc",
        }
        response = await client.get(url, headers=base_headers, params=params)
        if response.status_code >= 400:
            return []
        rows = response.json()
        return rows if isinstance(rows, list) else []

    async def fetch_knowledge(
        self,
        crop_type: str | None,
        disease_name: str | None,
        label_key: str | None = None,
    ) -> list[dict[str, Any]]:
        """Load rows from public.disease_knowledge_base (+ day-level steps)."""
        if not self._settings.supabase_url or not self._settings.supabase_service_role_key:
            return []

        _ = label_key  # Schema may not include label_key; TFLite hint is in diagnosis fields.

        url = f"{self._settings.supabase_url}/rest/v1/disease_knowledge_base"
        headers = {
            "apikey": self._settings.supabase_service_role_key,
            "Authorization": f"Bearer {self._settings.supabase_service_role_key}",
        }
        params: dict[str, str] = {
            "select": "id,disease_name,crop_type,description,treatment_steps,"
            "prevention_steps,source_name,source_url",
            "is_active": "eq.true",
            "limit": "5",
        }
        if crop_type and crop_type.strip():
            params["crop_type"] = f"eq.{crop_type.strip()}"
        if disease_name and disease_name.strip():
            params["disease_name"] = f"eq.{disease_name.strip()}"

        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(url, headers=headers, params=params)
            if response.status_code >= 400:
                return []
            rows = response.json()
            if not isinstance(rows, list):
                return []

            out: list[dict[str, Any]] = []
            for row in rows:
                dkb_id = row.get("id")
                day_step_rows: list[dict[str, Any]] = []
                if isinstance(dkb_id, str) and dkb_id:
                    day_step_rows = await self._fetch_treatment_day_steps(
                        client, headers, dkb_id
                    )
                day_lines = self._format_day_steps(day_step_rows)
                treatment_flat = self._parse_string_list(row.get("treatment_steps"))
                merged_steps = list(treatment_flat)
                for line in day_lines:
                    if line not in merged_steps:
                        merged_steps.append(line)

                out.append(
                    {
                        "label_key": "",
                        "title": row.get("disease_name") or "Untitled",
                        "crop_type": row.get("crop_type") or "unknown",
                        "summary": row.get("description") or "",
                        "source": row.get("source_name") or "supabase",
                        "treatment_steps": merged_steps,
                        "prevention_steps": self._parse_string_list(row.get("prevention_steps")),
                        "treatment_day_lines": day_lines,
                    }
                )
            return out

    async def fetch_knowledge_for_crop_overview(
        self,
        crop_type: str,
        *,
        limit: int = 18,
    ) -> list[dict[str, Any]]:
        """Shallow listing for vision-only chats (no TFLite diagnosis)."""
        if not self._settings.supabase_url or not self._settings.supabase_service_role_key:
            return []
        if not crop_type.strip():
            return []

        url = f"{self._settings.supabase_url}/rest/v1/disease_knowledge_base"
        headers = {
            "apikey": self._settings.supabase_service_role_key,
            "Authorization": f"Bearer {self._settings.supabase_service_role_key}",
        }
        params = {
            "select": "id,disease_name,crop_type,description,treatment_steps,prevention_steps,source_name",
            "is_active": "eq.true",
            "crop_type": f"eq.{crop_type.strip()}",
            "limit": str(limit),
            "order": "disease_name.asc",
        }
        async with httpx.AsyncClient(timeout=12.0) as client:
            response = await client.get(url, headers=headers, params=params)
            if response.status_code >= 400:
                return []
            rows = response.json()
            if not isinstance(rows, list):
                return []

            return [
                {
                    "label_key": "",
                    "title": row.get("disease_name") or "Untitled",
                    "crop_type": row.get("crop_type") or crop_type,
                    "summary": (row.get("description") or "")[:800],
                    "source": row.get("source_name") or "supabase",
                    "treatment_steps": self._parse_string_list(row.get("treatment_steps")),
                    "prevention_steps": self._parse_string_list(row.get("prevention_steps")),
                    "treatment_day_lines": [],
                }
                for row in rows
            ]
