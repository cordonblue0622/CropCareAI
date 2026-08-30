from __future__ import annotations

import logging
import re
from datetime import UTC, datetime
from typing import Any
from uuid import uuid4

import httpx
from fastapi import HTTPException, status

from app.core.config import Settings
from app.schemas.user import AuthenticatedUser

logger = logging.getLogger(__name__)


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
            "id", "crop_type", "label_key", "disease_name", "scientific_name",
            "description", "symptoms", "causes", "treatment_steps",
            "prevention_steps", "estimated_recovery_days", "severity_notes",
            "caution_notes", "is_active", "source_name", "source_url",
            "created_at", "updated_at",
        ),
        editable=(
            "crop_type", "label_key", "disease_name", "scientific_name",
            "description", "symptoms", "causes", "treatment_steps",
            "prevention_steps", "estimated_recovery_days", "severity_notes",
            "caution_notes", "is_active", "source_name", "source_url",
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
        return [
            {
                "id": user.get("id"),
                "email": user.get("email"),
                "created_at": user.get("created_at"),
                "last_sign_in_at": user.get("last_sign_in_at"),
                "confirmed_at": user.get("confirmed_at"),
                "banned_until": user.get("banned_until"),
                "admin_role": (user.get("app_metadata") or {}).get("admin_role"),
            }
            for user in users
            if isinstance(user, dict)
        ]

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
        if suspended and target_role in {"admin", "superadmin"} and actor.role != "superadmin":
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
