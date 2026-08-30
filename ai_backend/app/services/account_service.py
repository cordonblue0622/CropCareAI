from __future__ import annotations

from typing import Any

import httpx
from fastapi import HTTPException, status

from app.core.config import Settings
from app.schemas.user import AuthenticatedUser


USER_TABLES = (
    "chat_messages",
    "notifications",
    "treatment_tasks",
    "progress_updates",
    "treatments",
    "diagnoses",
    "chat_sessions",
    "crops",
)


class AccountService:
    def __init__(self, settings: Settings):
        self._settings = settings

    def _headers(self) -> dict[str, str]:
        if not self._settings.supabase_url or not self._settings.supabase_service_role_key:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Account deletion is temporarily unavailable.",
            )
        return {
            "Authorization": f"Bearer {self._settings.supabase_service_role_key}",
            "apikey": self._settings.supabase_service_role_key,
            "Content-Type": "application/json",
        }

    @staticmethod
    def _raise_for_response(response: httpx.Response) -> None:
        if response.status_code < 400:
            return
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Your account could not be fully deleted. Your sign-in remains active; please try again.",
        )

    async def delete_account(self, user: AuthenticatedUser) -> None:
        if not user.id:
            raise HTTPException(status_code=401, detail="A valid signed-in account is required.")

        base_url = self._settings.supabase_url.rstrip("/")
        headers = self._headers()
        async with httpx.AsyncClient(timeout=30.0) as client:
            await self._delete_storage_objects(client, base_url, headers, user.id)

            for table in USER_TABLES:
                response = await client.delete(
                    f"{base_url}/rest/v1/{table}",
                    headers=headers,
                    params={"user_id": f"eq.{user.id}"},
                )
                self._raise_for_response(response)

            profile_response = await client.delete(
                f"{base_url}/rest/v1/profiles",
                headers=headers,
                params={"id": f"eq.{user.id}"},
            )
            self._raise_for_response(profile_response)

            auth_response = await client.delete(
                f"{base_url}/auth/v1/admin/users/{user.id}",
                headers=headers,
            )
            self._raise_for_response(auth_response)

    async def _delete_storage_objects(
        self,
        client: httpx.AsyncClient,
        base_url: str,
        headers: dict[str, str],
        user_id: str,
    ) -> None:
        list_response = await client.post(
            f"{base_url}/storage/v1/object/list/chat-images",
            headers=headers,
            json={"prefix": user_id, "limit": 1000, "offset": 0},
        )
        if list_response.status_code == 404:
            return
        self._raise_for_response(list_response)
        objects = list_response.json()
        paths = [
            f"{user_id}/{item['name']}"
            for item in objects
            if isinstance(item, dict) and item.get("name")
        ]
        if not paths:
            return
        delete_response = await client.request(
            "DELETE",
            f"{base_url}/storage/v1/object/chat-images",
            headers=headers,
            json={"prefixes": paths},
        )
        self._raise_for_response(delete_response)