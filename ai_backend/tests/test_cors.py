from fastapi.testclient import TestClient

from app.main import app


def test_development_cors_allows_private_lan_preflight() -> None:
    client = TestClient(app)
    origin = "http://192.168.1.42:8080"

    response = client.options(
        "/v1/chat",
        headers={
            "Origin": origin,
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type,authorization",
        },
    )

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == origin