import asyncio
from datetime import UTC, datetime

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


def test_admin_profile_allowlist_excludes_auth_and_role_fields() -> None:
    cleaned = AdminService._clean_profile_payload(
        {
            "full_name": "  Ana Farmer  ",
            "barangay": "Poblacion",
            "email": "attacker@example.com",
            "password": "do-not-store",
            "admin_role": "superadmin",
            "app_metadata": {"admin_role": "superadmin"},
        }
    )

    assert cleaned == {
        "full_name": "Ana Farmer",
        "barangay": "Poblacion",
    }


def test_user_invitation_allowlist_never_accepts_admin_role_or_password() -> None:
    cleaned = AdminService._clean_invite_payload(
        {
            "first_name": "  Ana ",
            "last_name": " Farmer ",
            "farm_address": " Farm Road ",
            "phone": " 09171234567 ",
            "email": " ANA@EXAMPLE.COM ",
            "password": "not-accepted",
            "admin_role": "superadmin",
            "role": "admin",
        }
    )

    assert cleaned == {
        "first_name": "Ana",
        "last_name": "Farmer",
        "farm_address": "Farm Road",
        "phone": "09171234567",
        "email": "ana@example.com",
        "role": "admin",
    }


def test_user_invitation_defaults_to_non_admin_role() -> None:
    cleaned = AdminService._clean_invite_payload(
        {
            "first_name": "Ana",
            "last_name": "Farmer",
            "farm_address": "Farm Road",
            "email": "ana@example.com",
        }
    )

    assert cleaned["role"] == "user"


def test_user_invitation_rejects_unknown_role() -> None:
    with pytest.raises(HTTPException) as exc:
        AdminService._clean_invite_payload(
            {
                "first_name": "Ana",
                "last_name": "Farmer",
                "farm_address": "Farm Road",
                "email": "ana@example.com",
                "role": "superadmin",
            }
        )

    assert exc.value.status_code == 422


def test_regular_admin_cannot_invite_an_administrator() -> None:
    service = AdminService(Settings())
    actor = AuthenticatedUser(
        id="admin-1",
        email="admin@example.com",
        role="admin",
    )

    with pytest.raises(HTTPException) as exc:
        asyncio.run(
            service.invite_user(
                {
                    "first_name": "Ana",
                    "last_name": "Farmer",
                    "farm_address": "Farm Road",
                    "email": "ana@example.com",
                    "role": "admin",
                },
                actor,
            )
        )

    assert exc.value.status_code == 403


def test_treatment_protocol_rejects_incomplete_daily_steps_before_supabase_call() -> None:
    service = AdminService(Settings())
    actor = AuthenticatedUser(id="admin-1", email="admin@example.com", role="admin")

    with pytest.raises(HTTPException) as exc:
        asyncio.run(
            service.save_treatment_protocol(
                "disease-1",
                {
                    "treatment_title": "Leaf care",
                    "treatment_information": "Keep foliage dry.",
                    "expected_duration_days": 2,
                    "daily_steps": [{"tasks": ["Inspect leaves"]}],
                },
                actor,
            )
        )

    assert exc.value.status_code == 422


def test_admin_resources_target_flutter_supabase_tables() -> None:
    assert {name: resource.table for name, resource in RESOURCES.items()} == {
        "diseases": "disease_knowledge_base",
        "treatments": "treatments",
        "crops": "crops",
        "diagnoses": "diagnoses",
    }


def test_disease_resource_includes_admin_content_fields() -> None:
    assert {"severity", "treatment_title", "treatment_information"}.issubset(
        RESOURCES["diseases"].editable
    )
    assert "label_key" not in RESOURCES["diseases"].fields


def test_admin_content_and_invitation_routes_are_registered() -> None:
    paths = {route.path for route in app.routes}

    assert "/v1/admin/users/invite" in paths
    assert "/v1/admin/treatment-protocols" in paths
    assert "/v1/admin/treatment-protocols/{disease_id}" in paths
    assert "/v1/admin/analytics" in paths
    assert "/v1/admin/crops/{crop_id}/activity" in paths


def test_crop_activity_is_newest_first_and_carries_health_score() -> None:
    events = AdminService._build_crop_activity(
        crop={
            "crop_name": "North tomato",
            "crop_type": "tomato",
            "status": "completed",
            "latest_progress_status": "improving",
            "latest_health_score": 91,
            "is_deleted": False,
            "created_at": "2026-08-01T08:00:00Z",
            "updated_at": "2026-08-03T08:00:00Z",
        },
        progress=[{
            "note": "Leaves are recovering.",
            "health_score": 78,
            "progress_status": "improving",
            "completed_task_count": 1,
            "missed_task_count": 0,
            "update_date": "2026-08-02T08:00:00Z",
            "is_deleted": False,
        }],
        tasks=[{
            "title": "Day 1 sanitation",
            "description": "Removed affected leaves.",
            "status": "completed",
            "completed_at": "2026-08-02T12:00:00Z",
            "is_deleted": False,
        }],
        treatments=[],
        diagnoses=[],
        audit=[],
    )

    assert [event["type"] for event in events] == ["edit", "task", "progress", "created"]
    assert events[1]["health_score"] == 78


def test_admin_analytics_returns_aggregate_research_metrics() -> None:
    result = AdminService._build_analytics(
        users=[
            {"id": "user-1", "last_sign_in_at": "2026-08-29T14:00:00Z"},
            {"id": "pending-1", "admin_access_requested": True},
            {"id": "admin-1", "admin_role": "admin"},
        ],
        crops=[
            {
                "id": "crop-1",
                "crop_type": "tomato",
                "latest_progress_status": "improving",
                "latest_health_score": 82,
            },
            {
                "id": "crop-2",
                "crop_type": "pepper",
                "latest_progress_status": "worsening",
                "latest_health_score": 42,
            },
        ],
        tasks=[
            {"crop_id": "crop-1", "status": "completed"},
            {"crop_id": "crop-1", "status": "pending"},
            {"crop_id": "crop-2", "status": "pending"},
        ],
        progress=[{"crop_id": "crop-1", "update_date": "2026-08-29T00:00:00Z"}],
        diagnoses=[{"crop_id": "crop-1", "diagnosed_at": "2026-08-28T00:00:00Z"}],
        now=datetime(2026, 8, 30, tzinfo=UTC),
    )

    assert result["metrics"] == {
        "ordinary_users": 1,
        "active_users_30d": 1,
        "current_crops": 2,
        "treatment_task_completion_rate": 33.3,
        "improving_crops": 1,
        "crops_needing_attention": 1,
    }
    assert result["activity_by_day"][-3]["diagnoses"] == 1
    assert result["activity_by_day"][-2]["check_ins"] == 1
    assert result["sign_in_hours_utc"][14]["count"] == 1