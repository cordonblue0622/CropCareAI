import asyncio
import sys
from types import SimpleNamespace

from app.api.progress import _assess, _normalize_crop
from app.schemas.progress import ProgressCheckInRequest


def test_unavailable_ai_keeps_the_existing_health_score() -> None:
    result = asyncio.run(
        _assess(
            ProgressCheckInRequest(
                crop_type="tomato",
                disease_name="late blight",
                current_health_score=45.0,
                completed_tasks=["Remove damaged leaves", "Clean tools"],
            ),
            api_key=None,
            model="unused",
        )
    )

    assert result.accepted is True
    assert result.health_score == 45.0
    assert result.progress_status == "insufficient_data"


def test_crop_aliases_normalize_to_the_tracked_crop() -> None:
    assert _normalize_crop("Bell Pepper") == "pepper"
    assert _normalize_crop("bok choy") == "pechay"


def test_mismatched_observed_crop_rejects_the_check_in(monkeypatch) -> None:
    class FakeResponses:
        def create(self, **_kwargs):
            return SimpleNamespace(
                output_text=(
                    '{"accepted": true, "observed_crop": "tomato", '
                    '"health_score": 20, "progress_status": "declining", '
                    '"assessment": "Tomato symptoms are visible.", '
                    '"next_steps": ["Spray treatment"]}'
                )
            )

    class FakeOpenAI:
        def __init__(self, **_kwargs):
            self.responses = FakeResponses()

    monkeypatch.setitem(sys.modules, "openai", SimpleNamespace(OpenAI=FakeOpenAI))
    result = asyncio.run(
        _assess(
            ProgressCheckInRequest(
                crop_type="eggplant",
                disease_name="leaf spot",
                current_health_score=55,
                image_data_url="data:image/jpeg;base64,abc",
            ),
            api_key="test-key",
            model="unused",
        )
    )

    assert result.accepted is False
    assert result.health_score == 55
    assert result.progress_status == "stable"
    assert result.next_steps == []