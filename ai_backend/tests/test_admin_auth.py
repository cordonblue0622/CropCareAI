import asyncio

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from fastapi.testclient import TestClient

from app.main import app
from app.core.config import Settings
from app.core.dependencies import require_admin_user, require_superadmin_user
from app.schemas.user import AuthenticatedUser
from app.services.admin_service import AdminService, RESOURCES
from app.services.auth_service import AuthService


class _FakeSupabase:
    def __init__(self, payload: dict):
        self.payload = payload

    async def get_user(self, _access_token: str) -> dict:
        return self.payload


class _FakeAuthService:
    def __init__(self, role: str):
        self.role = role

    async def verify_access_token(self, _token: str) -> AuthenticatedUser:
        return AuthenticatedUser(id="user-1", email="user@example.com", role=self.role)


def _credentials() -> HTTPAuthorizationCredentials:
    return HTTPAuthorizationCredentials(scheme="Bearer", credentials="token")


def test_auth_service_uses_admin_role_from_app_metadata() -> None:
    service = AuthService(Settings())
    service._supabase = _FakeSupabase(
        {
            "id": "admin-1",
            "email": "admin@example.com",
            "role": "authenticated",
            "user_metadata": {"admin_role": "superadmin"},
            "app_metadata": {"admin_role": "admin"},
        }
    )

    user = asyncio.run(service.verify_access_token("token"))

    assert user.role == "admin"


def test_admin_dependency_rejects_authenticated_user() -> None:
    with pytest.raises(HTTPException) as exc:
        asyncio.run(
            require_admin_user(
                credentials=_credentials(),
                auth_service=_FakeAuthService("authenticated"),
            )
        )

    assert exc.value.status_code == 403


def test_admin_dependency_accepts_superadmin() -> None:
    user = asyncio.run(
        require_admin_user(
            credentials=_credentials(),
            auth_service=_FakeAuthService("superadmin"),
        )
    )

    assert user.role == "superadmin"


def test_superadmin_dependency_rejects_regular_admin() -> None:
    with pytest.raises(HTTPException) as exc:
        asyncio.run(
            require_superadmin_user(
                AuthenticatedUser(
                    id="admin-1",
                    email="admin@example.com",
                    role="admin",
                )
            )
        )

    assert exc.value.status_code == 403


def test_superadmin_dependency_accepts_superadmin() -> None:
    user = asyncio.run(
        require_superadmin_user(
            AuthenticatedUser(
                id="owner-1",
                email="owner@example.com",
                role="superadmin",
            )
        )
    )

    assert user.role == "superadmin"


def test_admin_api_requires_bearer_token_even_in_development() -> None:
    response = TestClient(app).get("/v1/admin/summary")

    assert response.status_code == 401


def test_admin_portal_has_no_store_and_frame_protection() -> None:
    response = TestClient(app).get("/admin")

    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["x-frame-options"] == "DENY"
    assert "frame-ancestors 'none'" in response.headers["content-security-policy"]


def test_admin_payload_allowlist_excludes_sensitive_and_immutable_fields() -> None:
    cleaned = AdminService._clean_payload(
        RESOURCES["diagnoses"],
        {
            "disease_name": "Leaf spot",
            "summary": "Observed lesions",
            "image_url": "https://private.example/image.jpg",
            "password": "never-store-this",
            "is_deleted": True,
            "created_at": "forged",
        },
    )

    assert cleaned == {
        "disease_name": "Leaf spot",
        "summary": "Observed lesions",
    }


def test_admin_resources_target_flutter_supabase_tables() -> None:
    assert {name: resource.table for name, resource in RESOURCES.items()} == {
        "diseases": "disease_knowledge_base",
        "treatments": "treatments",
        "crops": "crops",
        "diagnoses": "diagnoses",
    }