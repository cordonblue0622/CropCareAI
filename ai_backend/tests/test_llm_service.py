from app.core.config import Settings
from app.schemas.chat import ChatRequest, DiagnosisContext
from app.services.llm_service import LlmService


def test_explicit_crop_hint_overrides_scanner_crop_and_rejects_conflict() -> None:
    service = LlmService(Settings())
    payload = ChatRequest(
        user_message="This is eggplant.",
        hint_crop_type="eggplant",
        diagnosis=DiagnosisContext(
            crop_type="tomato",
            disease_name="Tomato Leaf Mold",
        ),
    )

    active_crop = service._resolve_active_crop(payload, [])

    assert active_crop == "eggplant"
    assert service._has_verified_crop_mismatch(
        active_crop,
        {"verified_crop": "tomato"},
    )
    assert not service._has_verified_crop_mismatch(
        active_crop,
        {"verified_crop": "eggplant"},
    )