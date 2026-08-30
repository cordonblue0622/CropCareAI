import asyncio

import httpx
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.core.config import Settings
from app.main import app
from app.schemas.user import AuthenticatedUser
from app.services.account_service import AccountService, USER_TABLES


def _settings() -> Settings:
    return Settings(
        SUPABASE_URL="https://example.supabase.co",
        SUPABASE_SERVICE_ROLE_KEY="service-role-key",
    )


def test_account_api_requires_authentication() -> None:
    client = TestClient(app)
    response = client.delete("/v1/account")
    assert response.status_code == 401


def test_account_deletion_removes_auth_identity_last(monkeypatch) -> None:
    requests: list[httpx.Request] = []
    async_client = httpx.AsyncClient

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if "/storage/v1/object/list/" in str(request.url):
            return httpx.Response(200, json=[])
        return httpx.Response(204)

    transport = httpx.MockTransport(handler)
    monkeypatch.setattr(
        httpx,
        "AsyncClient",
        lambda **kwargs: async_client(transport=transport, **kwargs),
    )

    service = AccountService(_settings())
    asyncio.run(
        service.delete_account(
            AuthenticatedUser(id="user-123", email="farmer@example.com")
        )
    )

    urls = [str(request.url) for request in requests]
    assert len([url for url in urls if "/rest/v1/" in url]) == len(USER_TABLES) + 1
    assert all("eq.user-123" in url for url in urls if "/rest/v1/" in url)
    assert urls[-1].endswith("/auth/v1/admin/users/user-123")


def test_account_deletion_keeps_auth_identity_when_data_cleanup_fails(monkeypatch) -> None:
    requests: list[httpx.Request] = []
    async_client = httpx.AsyncClient

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if "/storage/v1/object/list/" in str(request.url):
            return httpx.Response(200, json=[])
        return httpx.Response(500, json={"message": "database error"})

    transport = httpx.MockTransport(handler)
    monkeypatch.setattr(
        httpx,
        "AsyncClient",
        lambda **kwargs: async_client(transport=transport, **kwargs),
    )

    service = AccountService(_settings())
    with pytest.raises(HTTPException) as exc:
        asyncio.run(
            service.delete_account(
                AuthenticatedUser(id="user-123", email="farmer@example.com")
            )
        )

    assert exc.value.status_code == 502
    assert "sign-in remains active" in exc.value.detail
    assert not any("/auth/v1/admin/users/" in str(request.url) for request in requests)