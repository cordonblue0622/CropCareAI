import asyncio

from app.api.progress import _assess
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