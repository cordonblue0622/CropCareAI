import asyncio
import json

import httpx
import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from fastapi.testclient import TestClient

from app.api.admin import get_admin_service
from app.core.config import Settings
from app.core.dependencies import get_auth_service, require_admin_user
from app.main import app
from app.schemas.user import AuthenticatedUser
from app.services.admin_service import AdminService


def _settings() -> Settings:
    return Settings(
        SUPABASE_URL="https://example.supabase.co",
        SUPABASE_SERVICE_ROLE_KEY="service-role-key",
    )


def _actor(role: str) -> AuthenticatedUser:
    return AuthenticatedUser(
        id="00000000-0000-0000-0000-000000000001",
        email=f"{role}@example.com",
        role=role,
        assurance_level="aal2",
    )


def _use_mock_transport(monkeypatch, handler) -> None:
    async_client = httpx.AsyncClient
    monkeypatch.setattr(
        httpx,
        "AsyncClient",
        lambda **kwargs: async_client(
            transport=httpx.MockTransport(handler),
            **kwargs,
        ),
    )


def test_announcement_payload_is_trimmed_and_validated() -> None:
    assert AdminService._clean_announcement_payload({
        "title": "  Rain advisory  ",
        "body": "  Inspect drainage this week.  ",
        "audience": "all_users",
        "recipient_ids": ["not-allowed"],
    }) == {
        "p_title": "Rain advisory",
        "p_body": "Inspect drainage this week.",
        "p_audience": "all_users",
    }

    for payload in (
        {"title": "", "body": "Message", "audience": "admin"},
        {"title": "Title", "body": " ", "audience": "admin"},
        {"title": "x" * 201, "body": "Message", "audience": "admin"},
        {"title": "Title", "body": "x" * 10001, "audience": "admin"},
        {"title": "Title", "body": "Message"},
        {"title": "Title", "body": "Message", "audience": "public"},
        {"title": "Title", "body": "Message", "audience": ["admin"]},
    ):
        with pytest.raises(HTTPException) as exc:
            AdminService._clean_announcement_payload(payload)
        assert exc.value.status_code == 422


def test_create_announcement_uses_atomic_alert_fanout_rpc(monkeypatch) -> None:
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(200, json={
            "id": "announcement-1",
            "title": "Rain advisory",
            "body": "Inspect drainage this week.",
            "audience": "all_users",
            "created_by": "00000000-0000-0000-0000-000000000001",
            "created_at": "2026-10-26T12:00:00Z",
            "recipient_count": 12,
        })

    _use_mock_transport(monkeypatch, handler)
    result = asyncio.run(AdminService(_settings()).create_announcement(
        {
            "title": "Rain advisory",
            "body": "Inspect drainage this week.",
            "audience": "all_users",
        },
        _actor("admin"),
    ))

    assert result["recipient_count"] == 12
    assert len(requests) == 1
    assert requests[0].url.path == "/rest/v1/rpc/create_announcement"
    assert json.loads(requests[0].content) == {
        "p_title": "Rain advisory",
        "p_body": "Inspect drainage this week.",
        "p_audience": "all_users",
        "p_created_by": "00000000-0000-0000-0000-000000000001",
    }


def test_announcement_history_loads_every_page(monkeypatch) -> None:
    offsets: list[int] = []

    def handler(request: httpx.Request) -> httpx.Response:
        payload = json.loads(request.content)
        assert payload["p_admin_id"] == _actor("admin").id
        assert payload["p_limit"] == 200
        offset = payload["p_offset"]
        offsets.append(offset)
        count = 200 if offset == 0 else 1
        return httpx.Response(200, json=[
            {"id": f"announcement-{offset + index}"} for index in range(count)
        ])

    _use_mock_transport(monkeypatch, handler)
    rows = asyncio.run(AdminService(_settings()).list_announcements(_actor("admin")))

    assert len(rows) == 201
    assert offsets == [0, 200]


def test_announcement_like_is_idempotent_and_actor_scoped(monkeypatch) -> None:
    announcement_id = "00000000-0000-0000-0000-000000000002"
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(200, json={
            "announcement_id": announcement_id,
            "liked": True,
            "likes_count": 3,
        })

    _use_mock_transport(monkeypatch, handler)
    result = asyncio.run(AdminService(_settings()).set_announcement_like(
        announcement_id,
        {"liked": True},
        _actor("superadmin"),
    ))

    assert result == {
        "announcement_id": announcement_id,
        "liked": True,
        "likes_count": 3,
    }
    assert requests[0].url.path == "/rest/v1/rpc/set_announcement_like"
    assert json.loads(requests[0].content) == {
        "p_announcement_id": announcement_id,
        "p_admin_id": _actor("superadmin").id,
        "p_liked": True,
    }

    for invalid_id, payload in (
        ("not-a-uuid", {"liked": True}),
        (announcement_id, {"liked": "yes"}),
        (announcement_id, {}),
    ):
        with pytest.raises(HTTPException) as exc:
            asyncio.run(AdminService(_settings()).set_announcement_like(
                invalid_id, payload, _actor("admin")
            ))
        assert exc.value.status_code == 422


def test_announcement_reply_is_trimmed_and_actor_scoped(monkeypatch) -> None:
    announcement_id = "00000000-0000-0000-0000-000000000002"
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(200, json={
            "id": "reply-1",
            "announcement_id": announcement_id,
            "body": "Confirmed with the field team.",
            "created_by": _actor("admin").id,
            "created_at": "2026-10-26T12:30:00Z",
            "author_name": "Aida Admin",
            "author_role": "admin",
        })

    _use_mock_transport(monkeypatch, handler)
    result = asyncio.run(AdminService(_settings()).create_announcement_reply(
        announcement_id,
        {"body": "  Confirmed with the field team.  "},
        _actor("admin"),
    ))

    assert result["author_name"] == "Aida Admin"
    assert requests[0].url.path == "/rest/v1/rpc/create_announcement_reply"
    assert json.loads(requests[0].content) == {
        "p_announcement_id": announcement_id,
        "p_body": "Confirmed with the field team.",
        "p_created_by": _actor("admin").id,
    }

    for invalid_id, payload in (
        ("not-a-uuid", {"body": "Reply"}),
        (announcement_id, {"body": " "}),
        (announcement_id, {"body": "x" * 5001}),
    ):
        with pytest.raises(HTTPException) as exc:
            asyncio.run(AdminService(_settings()).create_announcement_reply(
                invalid_id, payload, _actor("admin")
            ))
        assert exc.value.status_code == 422


class _FakeAuthService:
    def __init__(self, role: str):
        self.role = role

    async def verify_access_token(self, _token: str) -> AuthenticatedUser:
        return _actor(self.role)


class _FakeAnnouncementService:
    def __init__(self):
        self.actor = None

    async def create_announcement(self, payload, actor):
        self.actor = actor
        return {
            "id": "announcement-1",
            "title": payload["title"],
            "body": payload["body"],
            "audience": payload["audience"],
            "created_by": actor.id,
            "created_at": "2026-10-26T12:00:00Z",
            "recipient_count": 2 if payload["audience"] == "all_users" else 0,
        }

    async def list_announcements(self, actor):
        self.actor = actor
        return [{
            "id": "announcement-1",
            "title": "Rain advisory",
            "body": "Inspect drainage this week.",
            "audience": "all_users",
            "created_by": _actor("admin").id,
            "created_at": "2026-10-26T12:00:00Z",
            "author_name": "Aida Admin",
            "author_role": "admin",
            "likes_count": 1,
            "liked_by_current_admin": False,
            "replies_count": 0,
            "replies": [],
        }]

    async def set_announcement_like(self, announcement_id, payload, actor):
        self.actor = actor
        return {
            "announcement_id": announcement_id,
            "liked": payload["liked"],
            "likes_count": 2 if payload["liked"] else 1,
        }

    async def create_announcement_reply(self, announcement_id, payload, actor):
        self.actor = actor
        return {
            "id": "reply-1",
            "announcement_id": announcement_id,
            "body": payload["body"],
            "created_by": actor.id,
            "created_at": "2026-10-26T12:30:00Z",
            "author_name": "Aida Admin",
            "author_role": actor.role,
        }


@pytest.mark.parametrize("role", ["admin", "superadmin"])
def test_announcement_routes_allow_admin_roles(role: str) -> None:
    user = asyncio.run(require_admin_user(
        credentials=HTTPAuthorizationCredentials(
            scheme="Bearer",
            credentials="token",
        ),
        auth_service=_FakeAuthService(role),
    ))
    service = _FakeAnnouncementService()
    app.dependency_overrides[require_admin_user] = lambda: user
    app.dependency_overrides[get_admin_service] = lambda: service
    try:
        client = TestClient(app)
        created = client.post(
            "/v1/admin/announcements",
            headers={"Authorization": "Bearer token"},
            json={
                "title": "Rain advisory",
                "body": "Inspect drainage this week.",
                "audience": "all_users",
            },
        )
        timeline = client.get(
            "/v1/admin/announcements",
            headers={"Authorization": "Bearer token"},
        )
        announcement_id = "00000000-0000-0000-0000-000000000002"
        liked = client.put(
            f"/v1/admin/announcements/{announcement_id}/like",
            headers={"Authorization": "Bearer token"},
            json={"liked": True},
        )
        replied = client.post(
            f"/v1/admin/announcements/{announcement_id}/replies",
            headers={"Authorization": "Bearer token"},
            json={"body": "Confirmed with the field team."},
        )
    finally:
        app.dependency_overrides.pop(require_admin_user, None)
        app.dependency_overrides.pop(get_admin_service, None)

    assert created.status_code == 201
    assert created.json()["recipient_count"] == 2
    assert service.actor.role == role
    assert timeline.status_code == 200
    assert timeline.json()["items"][0]["author_name"] == "Aida Admin"
    assert liked.status_code == 200
    assert liked.json()["likes_count"] == 2
    assert replied.status_code == 201
    assert replied.json()["author_role"] == role


def test_announcement_routes_require_sign_in() -> None:
    client = TestClient(app)
    announcement_id = "00000000-0000-0000-0000-000000000002"
    assert client.get("/v1/admin/announcements").status_code == 401
    assert client.post(
        "/v1/admin/announcements",
        json={"title": "Title", "body": "Message", "audience": "admin"},
    ).status_code == 401
    assert client.put(
        f"/v1/admin/announcements/{announcement_id}/like",
        json={"liked": True},
    ).status_code == 401
    assert client.post(
        f"/v1/admin/announcements/{announcement_id}/replies",
        json={"body": "Reply"},
    ).status_code == 401


def test_announcement_routes_reject_ordinary_authenticated_users() -> None:
    app.dependency_overrides[get_auth_service] = lambda: _FakeAuthService("authenticated")
    announcement_id = "00000000-0000-0000-0000-000000000002"
    headers = {"Authorization": "Bearer ordinary-user-token"}
    try:
        client = TestClient(app)
        responses = [
            client.get("/v1/admin/announcements", headers=headers),
            client.post(
                "/v1/admin/announcements",
                headers=headers,
                json={"title": "Title", "body": "Message", "audience": "admin"},
            ),
            client.put(
                f"/v1/admin/announcements/{announcement_id}/like",
                headers=headers,
                json={"liked": True},
            ),
            client.post(
                f"/v1/admin/announcements/{announcement_id}/replies",
                headers=headers,
                json={"body": "Reply"},
            ),
        ]
    finally:
        app.dependency_overrides.pop(get_auth_service, None)

    assert [response.status_code for response in responses] == [403, 403, 403, 403]

