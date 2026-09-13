from fastapi.testclient import TestClient

from app.main import app


def test_health() -> None:
    client = TestClient(app)
    response = client.get("/health")

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "ok"
    assert "models" in payload
    assert sorted(payload["models"].keys()) == [
        "openaiConfigured",
        "openaiModel",
        "tfliteConfigured",
        "whisperConfigured",
    ]
    assert payload["models"]["openaiModel"]