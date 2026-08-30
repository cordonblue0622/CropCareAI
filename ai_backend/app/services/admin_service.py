from __future__ import annotations

import logging
import re
from collections import Counter, defaultdict
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import uuid4

import httpx
from fastapi import HTTPException, status

from app.core.config import Settings
from app.schemas.user import AuthenticatedUser

logger = logging.getLogger(__name__)

PROFILE_FIELDS = (
    "full_name",
    "display_name",
    "phone",
    "barangay",
    "municipality",
    "province",
    "country",
    "preferred_language",
)


class AdminResource:
    def __init__(
        self,
        *,
        table: str,
        fields: tuple[str, ...],
        editable: tuple[str, ...],
        required: tuple[str, ...] = (),
        search_fields: tuple[str, ...] = (),
        can_create: bool = True,
        soft_delete_field: str | None = "is_deleted",
    ) -> None:
        self.table = table
        self.fields = fields
        self.editable = editable
        self.required = required
        self.search_fields = search_fields
        self.can_create = can_create
        self.soft_delete_field = soft_delete_field


RESOURCES: dict[str, AdminResource] = {
    "diseases": AdminResource(
        table="disease_knowledge_base",
        fields=(
            "id", "crop_type", "disease_name", "scientific_name",
            "description", "symptoms", "causes", "treatment_steps",
            "prevention_steps", "estimated_recovery_days", "severity",
            "severity_notes", "caution_notes", "treatment_title",
            "treatment_information", "is_active", "source_name", "source_url",
            "created_at", "updated_at",
        ),
        editable=(
            "crop_type", "disease_name", "scientific_name",
            "description", "symptoms", "causes", "treatment_steps",
            "prevention_steps", "estimated_recovery_days", "severity",
            "severity_notes", "caution_notes", "treatment_title",
            "treatment_information", "is_active", "source_name", "source_url",
        ),
        required=("crop_type", "disease_name"),
        search_fields=("disease_name", "scientific_name", "description"),
        soft_delete_field="is_active",
    ),
    "treatments": AdminResource(
        table="treatments",
        fields=(
            "id", "crop_id", "diagnosis_id", "user_id", "disease_name",
            "treatment_title", "treatment_steps", "expected_duration_days",
            "status", "started_at", "ended_at", "reassessment_required",
            "notes", "source", "is_deleted", "created_at", "updated_at",
        ),
        editable=(
            "crop_id", "diagnosis_id", "user_id", "disease_name",
            "treatment_title", "treatment_steps", "expected_duration_days",
            "status", "started_at", "ended_at", "reassessment_required",
            "notes", "source",
        ),
        required=("crop_id", "user_id", "disease_name", "treatment_title"),
        search_fields=("disease_name", "treatment_title", "notes"),
    ),
    "crops": AdminResource(
        table="crops",
        fields=(
            "id", "user_id", "crop_type", "crop_name", "plot_code",
            "location_label", "notes", "status", "planted_at",
            "last_checked_at", "latest_progress_status", "latest_health_score",
            "is_deleted", "created_at", "updated_at",
        ),
        editable=(
            "user_id", "crop_type", "crop_name", "plot_code", "location_label",
            "notes", "status", "planted_at", "last_checked_at",
            "latest_progress_status", "latest_health_score",
        ),
        required=("user_id", "crop_type", "crop_name"),
        search_fields=("crop_name", "plot_code", "location_label"),
    ),
    "diagnoses": AdminResource(
        table="diagnoses",
        fields=(
            "id", "crop_id", "user_id", "diagnosis_mode", "label_key",
            "disease_name", "confidence_score", "severity", "result_label",
            "summary", "model_name", "model_version", "diagnosed_at",
            "is_deleted", "created_at", "updated_at",
        ),
        editable=(
            "crop_id", "user_id", "diagnosis_mode", "label_key", "disease_name",
            "confidence_score", "severity", "result_label", "summary",
            "model_name", "model_version", "diagnosed_at",
        ),
        required=("crop_id", "user_id", "diagnosis_mode", "disease_name", "severity"),
        search_fields=("disease_name", "result_label", "summary", "model_name"),
    ),
}


class AdminService:
    def __init__(self, settings: Settings):
        self._settings = settings

    def _ensure_configured(self) -> None:
        if not self._settings.supabase_url or not self._settings.supabase_service_role_key:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Administrator data access is not configured.",
            )

    def _headers(self, *, return_representation: bool = False) -> dict[str, str]:
        self._ensure_configured()
        headers = {
            "apikey": self._settings.supabase_service_role_key,
            "Authorization": f"Bearer {self._settings.supabase_service_role_key}",
            "Content-Type": "application/json",
        }
        if return_representation:
            headers["Prefer"] = "return=representation"
        return headers

    def _resource(self, name: str) -> AdminResource:
        resource = RESOURCES.get(name)
        if resource is None:
            raise HTTPException(status_code=404, detail="Unknown administrator resource.")
        return resource

    @staticmethod
    def _clean_search(value: str) -> str:
        return re.sub(r"[^\w\s-]", "", value, flags=re.UNICODE).strip()[:80]

    @staticmethod
    def _clean_payload(resource: AdminResource, payload: dict[str, Any]) -> dict[str, Any]:
        cleaned = {key: value for key, value in payload.items() if key in resource.editable}
        for key, value in list(cleaned.items()):
            if isinstance(value, str):
                cleaned[key] = value.strip()[:10000]
            elif isinstance(value, list):
                cleaned[key] = [str(item).strip()[:1000] for item in value[:100]]
        return cleaned

    @staticmethod
    def _clean_profile_payload(payload: dict[str, Any]) -> dict[str, Any]:
        return {
            key: (value.strip()[:500] if isinstance(value, str) else value)
            for key, value in payload.items()
            if key in PROFILE_FIELDS and (value is None or isinstance(value, str))
        }

    @staticmethod
    def _clean_invite_payload(payload: dict[str, Any]) -> dict[str, str | None]:
        email = str(payload.get("email") or "").strip().lower()[:320]
        first_name = str(payload.get("first_name") or "").strip()[:100]
        last_name = str(payload.get("last_name") or "").strip()[:100]
        farm_address = str(payload.get("farm_address") or "").strip()[:500]
        phone = str(payload.get("phone") or "").strip()[:50] or None
        role = str(payload.get("role") or "user").strip().lower()
        if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
            raise HTTPException(status_code=422, detail="A valid email address is required.")
        if not first_name or not last_name or not farm_address:
            raise HTTPException(
                status_code=422,
                detail="First name, last name, and farm address are required.",
            )
        if role not in {"user", "admin"}:
            raise HTTPException(status_code=422, detail="Role must be user or admin.")
        return {
            "email": email,
            "first_name": first_name,
            "last_name": last_name,
            "farm_address": farm_address,
            "phone": phone,
            "role": role,
        }

    @staticmethod
    def _raise_for_response(response: httpx.Response) -> None:
        if response.status_code < 400:
            return
        logger.warning("Admin Supabase request failed with status %s", response.status_code)
        if response.status_code == 404:
            detail = "The requested record was not found."
        elif response.status_code == 409:
            detail = "That record conflicts with existing data."
        else:
            detail = "The administrator data operation could not be completed."
        raise HTTPException(status_code=response.status_code, detail=detail)

    async def list_resource(
        self,
        name: str,
        *,
        query: str = "",
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict[str, Any]]:
        resource = self._resource(name)
        params: dict[str, str] = {
            "select": ",".join(resource.fields),
            "limit": str(min(max(limit, 1), 100)),
            "offset": str(max(offset, 0)),
            "order": "updated_at.desc",
        }
        cleaned_query = self._clean_search(query)
        if cleaned_query and resource.search_fields:
            terms = ",".join(
                f"{field}.ilike.*{cleaned_query}*" for field in resource.search_fields
            )
            params["or"] = f"({terms})"

        url = f"{self._settings.supabase_url}/rest/v1/{resource.table}"
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.get(url, headers=self._headers(), params=params)
        self._raise_for_response(response)
        rows = response.json()
        return rows if isinstance(rows, list) else []

    async def create_resource(
        self,
        name: str,
        payload: dict[str, Any],
        actor: AuthenticatedUser,
    ) -> dict[str, Any]:
        resource = self._resource(name)
        if not resource.can_create:
            raise HTTPException(status_code=405, detail="Creation is disabled for this resource.")
        data = self._clean_payload(resource, payload)
        missing = [field for field in resource.required if not data.get(field)]
        if missing:
            raise HTTPException(status_code=422, detail=f"Required fields: {', '.join(missing)}")
        now = datetime.now(UTC).isoformat()
        data.update({"id": str(uuid4()), "created_at": now, "updated_at": now})
        url = f"{self._settings.supabase_url}/rest/v1/{resource.table}"
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.post(
                url,
                headers=self._headers(return_representation=True),
                json=data,
            )
        self._raise_for_response(response)
        rows = response.json()
        result = rows[0] if isinstance(rows, list) and rows else data
        await self._audit(actor, "create", name, result.get("id"), data)
        return result

    async def update_resource(
        self,
        name: str,
        record_id: str,
        payload: dict[str, Any],
        actor: AuthenticatedUser,
    ) -> dict[str, Any]:
        resource = self._resource(name)
        data = self._clean_payload(resource, payload)
        if not data:
            raise HTTPException(status_code=422, detail="No editable fields were supplied.")
        data["updated_at"] = datetime.now(UTC).isoformat()
        url = f"{self._settings.supabase_url}/rest/v1/{resource.table}"
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.patch(
                url,
                headers=self._headers(return_representation=True),
                params={"id": f"eq.{record_id}", "select": ",".join(resource.fields)},
                json=data,
            )
        self._raise_for_response(response)
        rows = response.json()
        if not isinstance(rows, list) or not rows:
            raise HTTPException(status_code=404, detail="The requested record was not found.")
        await self._audit(actor, "update", name, record_id, data)
        return rows[0]

    async def archive_resource(
        self,
        name: str,
        record_id: str,
        actor: AuthenticatedUser,
    ) -> None:
        resource = self._resource(name)
        if resource.soft_delete_field is None:
            raise HTTPException(status_code=405, detail="Archiving is disabled for this resource.")
        archived_value = False if resource.soft_delete_field == "is_active" else True
        data = {
            resource.soft_delete_field: archived_value,
            "updated_at": datetime.now(UTC).isoformat(),
        }
        url = f"{self._settings.supabase_url}/rest/v1/{resource.table}"
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.patch(
                url,
                headers=self._headers(),
                params={"id": f"eq.{record_id}"},
                json=data,
            )
        self._raise_for_response(response)
        await self._audit(actor, "archive", name, record_id, data)

    async def list_users(self, *, page: int = 1, per_page: int = 50) -> list[dict[str, Any]]:
        url = f"{self._settings.supabase_url}/auth/v1/admin/users"
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.get(
                url,
                headers=self._headers(),
                params={"page": max(page, 1), "per_page": min(max(per_page, 1), 100)},
            )
        self._raise_for_response(response)
        payload = response.json()
        users = payload.get("users", []) if isinstance(payload, dict) else []
        user_ids = [str(user.get("id")) for user in users if isinstance(user, dict) and user.get("id")]
        profiles: dict[str, dict[str, Any]] = {}
        if user_ids:
            profile_url = f"{self._settings.supabase_url}/rest/v1/profiles"
            async with httpx.AsyncClient(timeout=15.0) as client:
                profile_response = await client.get(
                    profile_url,
                    headers=self._headers(),
                    params={
                        "select": f"id,{','.join(PROFILE_FIELDS)}",
                        "id": f"in.({','.join(user_ids)})",
                    },
                )
            self._raise_for_response(profile_response)
            profile_rows = profile_response.json()
            if isinstance(profile_rows, list):
                profiles = {
                    str(profile.get("id")): profile
                    for profile in profile_rows
                    if isinstance(profile, dict) and profile.get("id")
                }
        return [
            {
                "id": user.get("id"),
                "email": user.get("email"),
                "created_at": user.get("created_at"),
                "last_sign_in_at": user.get("last_sign_in_at"),
                "confirmed_at": user.get("confirmed_at"),
                "banned_until": user.get("banned_until"),
                "admin_role": (user.get("app_metadata") or {}).get("admin_role"),
                "admin_access_requested": (user.get("user_metadata") or {}).get(
                    "admin_access_requested"
                ) is True,
                "profile": {
                    field: profiles.get(str(user.get("id")), {}).get(field)
                    for field in PROFILE_FIELDS
                },
            }
            for user in users
            if isinstance(user, dict)
        ]

    async def _get_auth_user(self, user_id: str) -> dict[str, Any]:
        url = f"{self._settings.supabase_url}/auth/v1/admin/users/{user_id}"
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.get(url, headers=self._headers())
        self._raise_for_response(response)
        payload = response.json()
        if not isinstance(payload, dict):
            raise HTTPException(status_code=404, detail="The requested user was not found.")
        return payload

    @staticmethod
    def _target_role(user: dict[str, Any]) -> str:
        metadata = user.get("app_metadata")
        return str(metadata.get("admin_role") if isinstance(metadata, dict) else "").strip().lower()

    async def update_user_profile(
        self,
        user_id: str,
        payload: dict[str, Any],
        actor: AuthenticatedUser,
    ) -> dict[str, Any]:
        target = await self._get_auth_user(user_id)
        if (
            self._target_role(target) in {"admin", "superadmin"}
            and actor.id != user_id
            and actor.role != "superadmin"
        ):
            raise HTTPException(status_code=403, detail="Only a superadmin can edit an administrator profile.")

        data = self._clean_profile_payload(payload)
        if not data:
            raise HTTPException(status_code=422, detail="No editable profile fields were supplied.")
        data.update({"id": user_id, "email": target.get("email"), "updated_at": datetime.now(UTC).isoformat()})
        url = f"{self._settings.supabase_url}/rest/v1/profiles"
        headers = self._headers(return_representation=True)
        headers["Prefer"] = "resolution=merge-duplicates,return=representation"
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.post(
                url,
                headers=headers,
                params={"on_conflict": "id", "select": f"id,{','.join(PROFILE_FIELDS)}"},
                json=data,
            )
        self._raise_for_response(response)
        rows = response.json()
        if not isinstance(rows, list) or not rows:
            raise HTTPException(status_code=404, detail="The user profile could not be updated.")
        await self._audit(actor, "update", "user_profiles", user_id, data)
        return rows[0]

    async def invite_user(
        self,
        payload: dict[str, Any],
        actor: AuthenticatedUser,
    ) -> dict[str, Any]:
        data = self._clean_invite_payload(payload)
        if data["role"] == "admin" and actor.role != "superadmin":
            raise HTTPException(
                status_code=403,
                detail="Only a superadmin can invite an administrator.",
            )
        full_name = f"{data['first_name']} {data['last_name']}"
        metadata = {
            "full_name": full_name,
            "farm_address": data["farm_address"],
            "phone": data["phone"],
        }
        invite_url = f"{self._settings.supabase_url}/auth/v1/invite"
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.post(
                invite_url,
                headers=self._headers(),
                params={"redirect_to": self._settings.admin_invite_redirect_url},
                json={"email": data["email"], "data": metadata},
            )
        self._raise_for_response(response)
        invited = response.json()
        user_id = str(invited.get("id") if isinstance(invited, dict) else "")
        if not user_id:
            raise HTTPException(status_code=502, detail="Supabase did not return the invited account.")

        if data["role"] == "admin":
            existing_metadata = invited.get("app_metadata") if isinstance(invited, dict) else {}
            app_metadata = dict(existing_metadata) if isinstance(existing_metadata, dict) else {}
            app_metadata["admin_role"] = "admin"
            async with httpx.AsyncClient(timeout=15.0) as client:
                role_response = await client.put(
                    f"{self._settings.supabase_url}/auth/v1/admin/users/{user_id}",
                    headers=self._headers(),
                    json={"app_metadata": app_metadata},
                )
            self._raise_for_response(role_response)

        profile = {
            "id": user_id,
            "email": data["email"],
            "full_name": full_name,
            "display_name": data["first_name"],
            "phone": data["phone"],
            "barangay": data["farm_address"],
            "updated_at": datetime.now(UTC).isoformat(),
        }
        headers = self._headers(return_representation=True)
        headers["Prefer"] = "resolution=merge-duplicates,return=representation"
        async with httpx.AsyncClient(timeout=15.0) as client:
            profile_response = await client.post(
                f"{self._settings.supabase_url}/rest/v1/profiles",
                headers=headers,
                params={"on_conflict": "id"},
                json=profile,
            )
        self._raise_for_response(profile_response)
        await self._audit(actor, "create", "users", user_id, {**profile, "role": data["role"]})
        return {
            "id": user_id,
            "email": data["email"],
            "role": data["role"],
            "profile": profile,
        }

    async def list_treatment_protocols(self) -> list[dict[str, Any]]:
        diseases = await self.list_resource("diseases", limit=100)
        disease_ids = [str(row["id"]) for row in diseases if row.get("id")]
        steps_by_disease: dict[str, list[dict[str, Any]]] = {}
        if disease_ids:
            async with httpx.AsyncClient(timeout=15.0) as client:
                response = await client.get(
                    f"{self._settings.supabase_url}/rest/v1/disease_treatment_day_steps",
                    headers=self._headers(),
                    params={
                        "select": "id,disease_knowledge_base_id,day_number,day_title,tasks,notes,is_active",
                        "disease_knowledge_base_id": f"in.({','.join(disease_ids)})",
                        "is_active": "eq.true",
                        "order": "day_number.asc",
                    },
                )
            self._raise_for_response(response)
            rows = response.json()
            if isinstance(rows, list):
                for step in rows:
                    if not isinstance(step, dict):
                        continue
                    key = str(step.get("disease_knowledge_base_id") or "")
                    steps_by_disease.setdefault(key, []).append(step)
        return [
            {**disease, "daily_steps": steps_by_disease.get(str(disease.get("id")), [])}
            for disease in diseases
        ]

    async def save_treatment_protocol(
        self,
        disease_id: str,
        payload: dict[str, Any],
        actor: AuthenticatedUser,
    ) -> dict[str, Any]:
        duration = payload.get("expected_duration_days")
        if not isinstance(duration, int) or isinstance(duration, bool) or not 1 <= duration <= 90:
            raise HTTPException(status_code=422, detail="Treatment duration must be between 1 and 90 days.")
        title = str(payload.get("treatment_title") or "").strip()[:300]
        information = str(payload.get("treatment_information") or "").strip()[:10000]
        raw_steps = payload.get("daily_steps")
        if not title or not information or not isinstance(raw_steps, list) or len(raw_steps) != duration:
            raise HTTPException(
                status_code=422,
                detail="Treatment title, information, and one step for every treatment day are required.",
            )

        existing_url = f"{self._settings.supabase_url}/rest/v1/disease_treatment_day_steps"
        async with httpx.AsyncClient(timeout=15.0) as client:
            disease_response = await client.get(
                f"{self._settings.supabase_url}/rest/v1/disease_knowledge_base",
                headers=self._headers(),
                params={"select": "id", "id": f"eq.{disease_id}", "limit": "1"},
            )
            existing_response = await client.get(
                existing_url,
                headers=self._headers(),
                params={
                    "select": "id,day_number",
                    "disease_knowledge_base_id": f"eq.{disease_id}",
                },
            )
        self._raise_for_response(disease_response)
        if not disease_response.json():
            raise HTTPException(status_code=404, detail="The selected disease was not found.")
        self._raise_for_response(existing_response)
        existing_rows = existing_response.json()
        existing_ids = {
            int(row["day_number"]): str(row["id"])
            for row in existing_rows
            if isinstance(row, dict) and row.get("day_number") and row.get("id")
        }

        normalized_steps: list[dict[str, Any]] = []
        for index, raw_step in enumerate(raw_steps, start=1):
            if not isinstance(raw_step, dict):
                raise HTTPException(status_code=422, detail=f"Day {index} is invalid.")
            tasks = raw_step.get("tasks")
            if not isinstance(tasks, list):
                tasks = [line.strip() for line in str(tasks or "").splitlines() if line.strip()]
            clean_tasks = [str(task).strip()[:1000] for task in tasks if str(task).strip()][:20]
            if not clean_tasks:
                raise HTTPException(status_code=422, detail=f"Day {index} needs at least one treatment step.")
            normalized_steps.append(
                {
                    "id": existing_ids.get(index, str(uuid4())),
                    "disease_knowledge_base_id": disease_id,
                    "day_number": index,
                    "day_title": str(raw_step.get("day_title") or f"Day {index}").strip()[:300],
                    "tasks": clean_tasks,
                    "notes": str(raw_step.get("notes") or "").strip()[:5000] or None,
                    "is_active": True,
                }
            )

        parent_data = {
            "treatment_title": title,
            "treatment_information": information,
            "estimated_recovery_days": duration,
            "treatment_steps": [task for step in normalized_steps for task in step["tasks"]],
            "updated_at": datetime.now(UTC).isoformat(),
        }
        async with httpx.AsyncClient(timeout=15.0) as client:
            parent_response = await client.patch(
                f"{self._settings.supabase_url}/rest/v1/disease_knowledge_base",
                headers=self._headers(return_representation=True),
                params={"id": f"eq.{disease_id}", "select": ",".join(RESOURCES["diseases"].fields)},
                json=parent_data,
            )
            deactivate_response = await client.patch(
                existing_url,
                headers=self._headers(),
                params={"disease_knowledge_base_id": f"eq.{disease_id}"},
                json={"is_active": False},
            )
        self._raise_for_response(parent_response)
        self._raise_for_response(deactivate_response)
        step_headers = self._headers(return_representation=True)
        step_headers["Prefer"] = "resolution=merge-duplicates,return=representation"
        async with httpx.AsyncClient(timeout=15.0) as client:
            steps_response = await client.post(
                existing_url,
                headers=step_headers,
                params={"on_conflict": "disease_knowledge_base_id,day_number"},
                json=normalized_steps,
            )
        self._raise_for_response(steps_response)
        parent_rows = parent_response.json()
        await self._audit(actor, "update", "diseases", disease_id, parent_data)
        return {
            **(parent_rows[0] if isinstance(parent_rows, list) and parent_rows else parent_data),
            "daily_steps": steps_response.json(),
        }

    async def send_password_reset(self, user_id: str, actor: AuthenticatedUser) -> None:
        target = await self._get_auth_user(user_id)
        if self._target_role(target) in {"admin", "superadmin"} and actor.role != "superadmin":
            raise HTTPException(status_code=403, detail="Only a superadmin can reset an administrator account.")
        email = str(target.get("email") or "").strip()
        if not email:
            raise HTTPException(status_code=409, detail="This account does not have an email address.")
        url = f"{self._settings.supabase_url}/auth/v1/recover"
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.post(
                url,
                headers={
                    "apikey": self._settings.supabase_anon_key,
                    "Content-Type": "application/json",
                },
                params={"redirect_to": self._settings.password_reset_redirect_url},
                json={"email": email},
            )
        self._raise_for_response(response)
        await self._audit(actor, "password_reset", "users", user_id, {})

    async def set_user_suspension(
        self,
        user_id: str,
        *,
        suspended: bool,
        actor: AuthenticatedUser,
    ) -> None:
        if actor.id == user_id and suspended:
            raise HTTPException(status_code=409, detail="You cannot suspend your own account.")
        url = f"{self._settings.supabase_url}/auth/v1/admin/users/{user_id}"
        async with httpx.AsyncClient(timeout=15.0) as client:
            lookup = await client.get(url, headers=self._headers())
        self._raise_for_response(lookup)
        target = lookup.json()
        target_metadata = target.get("app_metadata") if isinstance(target, dict) else {}
        target_role = str(
            target_metadata.get("admin_role") if isinstance(target_metadata, dict) else ""
        ).strip().lower()
        if (
            target_role in {"admin", "superadmin"}
            and actor.id != user_id
            and actor.role != "superadmin"
        ):
            raise HTTPException(
                status_code=403,
                detail="Only a superadmin can suspend another administrator.",
            )

        payload = {"ban_duration": "876000h" if suspended else "none"}
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.put(url, headers=self._headers(), json=payload)
        self._raise_for_response(response)
        await self._audit(actor, "suspend" if suspended else "restore", "users", user_id, {})

    async def set_user_admin_role(
        self,
        user_id: str,
        *,
        approved: bool,
        actor: AuthenticatedUser,
    ) -> None:
        if actor.role != "superadmin":
            raise HTTPException(status_code=403, detail="Superadmin access is required.")
        if actor.id == user_id:
            raise HTTPException(status_code=409, detail="You cannot change your own administrator role.")

        url = f"{self._settings.supabase_url}/auth/v1/admin/users/{user_id}"
        async with httpx.AsyncClient(timeout=15.0) as client:
            lookup = await client.get(url, headers=self._headers())
        self._raise_for_response(lookup)
        target = lookup.json()
        existing_metadata = target.get("app_metadata") if isinstance(target, dict) else {}
        metadata = dict(existing_metadata) if isinstance(existing_metadata, dict) else {}
        current_role = str(metadata.get("admin_role") or "").strip().lower()
        if current_role == "superadmin":
            raise HTTPException(
                status_code=409,
                detail="Superadmin roles can only be managed by the Supabase project owner.",
            )

        if approved:
            metadata["admin_role"] = "admin"
        else:
            metadata.pop("admin_role", None)
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.put(
                url,
                headers=self._headers(),
                json={"app_metadata": metadata},
            )
        self._raise_for_response(response)
        await self._audit(
            actor,
            "approve" if approved else "revoke",
            "users",
            user_id,
            {"admin_role": "admin" if approved else None},
        )

    async def summary(self) -> dict[str, Any]:
        counts: dict[str, int | None] = {}
        async with httpx.AsyncClient(timeout=15.0) as client:
            for name, resource in RESOURCES.items():
                url = f"{self._settings.supabase_url}/rest/v1/{resource.table}"
                response = await client.get(
                    url,
                    headers={**self._headers(), "Prefer": "count=exact"},
                    params={"select": "id", "limit": "1"},
                )
                content_range = response.headers.get("content-range", "")
                total = content_range.rsplit("/", 1)[-1] if "/" in content_range else ""
                counts[name] = int(total) if total.isdigit() else None
        counts["users"] = len(await self.list_users(per_page=100))
        return {"counts": counts, "generated_at": datetime.now(UTC).isoformat()}

    async def analytics(self) -> dict[str, Any]:
        users = await self.list_users(per_page=100)
        requests = {
            "crops": (
                "crops",
                "id,crop_type,status,latest_progress_status,latest_health_score,created_at",
            ),
            "tasks": (
                "treatment_tasks",
                "crop_id,status,completed_at,due_at,created_at",
            ),
            "progress": (
                "progress_updates",
                "crop_id,progress_status,health_score,completed_task_count,missed_task_count,created_at,update_date",
            ),
            "diagnoses": (
                "diagnoses",
                "crop_id,created_at,diagnosed_at",
            ),
        }
        datasets: dict[str, list[dict[str, Any]]] = {}
        async with httpx.AsyncClient(timeout=20.0) as client:
            for key, (table, fields) in requests.items():
                response = await client.get(
                    f"{self._settings.supabase_url}/rest/v1/{table}",
                    headers=self._headers(),
                    params={
                        "select": fields,
                        "is_deleted": "eq.false",
                        "limit": "5000",
                    },
                )
                self._raise_for_response(response)
                rows = response.json()
                datasets[key] = rows if isinstance(rows, list) else []
        return self._build_analytics(
            users=users,
            crops=datasets["crops"],
            tasks=datasets["tasks"],
            progress=datasets["progress"],
            diagnoses=datasets["diagnoses"],
        )

    @staticmethod
    def _parse_datetime(value: Any) -> datetime | None:
        if not isinstance(value, str) or not value.strip():
            return None
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(UTC)
        except ValueError:
            return None

    @classmethod
    def _build_analytics(
        cls,
        *,
        users: list[dict[str, Any]],
        crops: list[dict[str, Any]],
        tasks: list[dict[str, Any]],
        progress: list[dict[str, Any]],
        diagnoses: list[dict[str, Any]],
        now: datetime | None = None,
    ) -> dict[str, Any]:
        generated_at = (now or datetime.now(UTC)).astimezone(UTC)
        ordinary_users = [
            user
            for user in users
            if not user.get("admin_role") and not user.get("admin_access_requested")
        ]
        crop_by_id = {str(crop.get("id")): crop for crop in crops if crop.get("id")}
        crop_counts = Counter(str(crop.get("crop_type") or "unspecified") for crop in crops)
        crop_stats: dict[str, dict[str, Any]] = defaultdict(
            lambda: {
                "crop_type": "",
                "crop_count": 0,
                "improving": 0,
                "stable": 0,
                "worsening": 0,
                "insufficient_data": 0,
                "health_scores": [],
                "completed_tasks": 0,
                "total_tasks": 0,
            }
        )
        good_crop_ids: set[str] = set()
        attention_crop_ids: set[str] = set()
        for crop in crops:
            crop_id = str(crop.get("id") or "")
            crop_type = str(crop.get("crop_type") or "unspecified")
            stats = crop_stats[crop_type]
            stats["crop_type"] = crop_type
            stats["crop_count"] += 1
            progress_status = str(crop.get("latest_progress_status") or "insufficient_data")
            if progress_status not in {"improving", "stable", "worsening", "insufficient_data"}:
                progress_status = "insufficient_data"
            stats[progress_status] += 1
            score = crop.get("latest_health_score")
            if isinstance(score, (int, float)) and not isinstance(score, bool):
                stats["health_scores"].append(float(score))
                if float(score) < 50:
                    attention_crop_ids.add(crop_id)
            if progress_status == "improving":
                good_crop_ids.add(crop_id)
            elif progress_status == "worsening":
                attention_crop_ids.add(crop_id)

        total_tasks = 0
        completed_tasks = 0
        for task in tasks:
            crop = crop_by_id.get(str(task.get("crop_id") or ""))
            if crop is None:
                continue
            crop_type = str(crop.get("crop_type") or "unspecified")
            done = str(task.get("status") or "").lower() == "completed" or bool(task.get("completed_at"))
            crop_stats[crop_type]["total_tasks"] += 1
            total_tasks += 1
            if done:
                crop_stats[crop_type]["completed_tasks"] += 1
                completed_tasks += 1

        adaptation = []
        for crop_type, stats in sorted(crop_stats.items()):
            scores = stats.pop("health_scores")
            task_total = stats["total_tasks"]
            adaptation.append(
                {
                    **stats,
                    "average_health_score": round(sum(scores) / len(scores), 1) if scores else None,
                    "task_completion_rate": round(stats["completed_tasks"] * 100 / task_total, 1) if task_total else None,
                }
            )

        day_start = generated_at.date() - timedelta(days=13)
        activity = {
            (day_start + timedelta(days=offset)).isoformat(): {"diagnoses": 0, "check_ins": 0}
            for offset in range(14)
        }
        for row, field_names, metric in (
            *((row, ("diagnosed_at", "created_at"), "diagnoses") for row in diagnoses),
            *((row, ("update_date", "created_at"), "check_ins") for row in progress),
        ):
            timestamp = next((cls._parse_datetime(row.get(field)) for field in field_names if row.get(field)), None)
            if timestamp and timestamp.date().isoformat() in activity:
                activity[timestamp.date().isoformat()][metric] += 1

        sign_in_hours = [0] * 24
        active_users_30d = 0
        cutoff = generated_at - timedelta(days=30)
        for user in ordinary_users:
            signed_in = cls._parse_datetime(user.get("last_sign_in_at"))
            if signed_in:
                sign_in_hours[signed_in.hour] += 1
                if signed_in >= cutoff:
                    active_users_30d += 1

        return {
            "metrics": {
                "ordinary_users": len(ordinary_users),
                "active_users_30d": active_users_30d,
                "current_crops": len(crops),
                "treatment_task_completion_rate": round(completed_tasks * 100 / total_tasks, 1) if total_tasks else None,
                "improving_crops": len(good_crop_ids),
                "crops_needing_attention": len(attention_crop_ids),
            },
            "crop_distribution": [
                {"crop_type": crop_type, "count": count}
                for crop_type, count in sorted(crop_counts.items(), key=lambda item: (-item[1], item[0]))
            ],
            "treatment_adaptation": adaptation,
            "activity_by_day": [
                {"date": date, **values} for date, values in activity.items()
            ],
            "sign_in_hours_utc": [
                {"hour": hour, "count": count} for hour, count in enumerate(sign_in_hours)
            ],
            "generated_at": generated_at.isoformat(),
        }

    async def list_audit_events(self, *, limit: int = 50) -> list[dict[str, Any]]:
        url = f"{self._settings.supabase_url}/rest/v1/admin_audit_events"
        params = {
            "select": "id,actor_id,actor_email,action,resource,record_id,created_at",
            "order": "created_at.desc",
            "limit": str(min(max(limit, 1), 100)),
        }
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(url, headers=self._headers(), params=params)
        if response.status_code == 404:
            return []
        self._raise_for_response(response)
        rows = response.json()
        return rows if isinstance(rows, list) else []

    async def _audit(
        self,
        actor: AuthenticatedUser,
        action: str,
        resource: str,
        record_id: Any,
        changes: dict[str, Any],
    ) -> None:
        logger.info(
            "admin_action actor=%s action=%s resource=%s record=%s",
            actor.id,
            action,
            resource,
            record_id,
        )
        url = f"{self._settings.supabase_url}/rest/v1/admin_audit_events"
        payload = {
            "id": str(uuid4()),
            "actor_id": actor.id,
            "actor_email": actor.email,
            "action": action,
            "resource": resource,
            "record_id": str(record_id or ""),
            "changed_fields": sorted(changes.keys()),
            "created_at": datetime.now(UTC).isoformat(),
        }
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.post(url, headers=self._headers(), json=payload)
            if response.status_code >= 400:
                logger.error(
                    "Could not persist administrator audit event; status=%s",
                    response.status_code,
                )
        except httpx.HTTPError:
            logger.exception("Could not persist administrator audit event.")
