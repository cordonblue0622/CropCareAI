import asyncio

from app.core.config import Settings
from app.schemas.chat import ChatRequest, DiagnosisContext
from app.services.llm_service import LlmService
from app.services.knowledge_service import KnowledgeService


class _TrackingKnowledgeSupabase:
    def __init__(self) -> None:
        self.fetch_calls = 0

    async def fetch_knowledge(
        self,
        crop_type: str | None,
        disease_name: str | None,
        label_key: str | None = None,
    ) -> list[dict[str, object]]:
        self.fetch_calls += 1
        return [
            {
                "title": "Tomato Early Blight",
                "crop_type": "tomato",
            }
        ]


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
    assert not service._has_verified_crop_mismatch(
        "",
        {"verified_crop": "squash"},
    )


def test_latest_crop_intent_overrides_stale_tomato_hint() -> None:
    service = LlmService(Settings())
    payload = ChatRequest(
        user_message="How do I treat powdery mildew?",
        hint_crop_type="tomato",
    )

    assert service._resolve_active_crop(payload, []) == "squash"


def test_image_fallback_does_not_repeat_unverified_scanner_diagnosis() -> None:
    service = LlmService(Settings())
    payload = ChatRequest(
        user_message="What is in this picture?",
        hint_crop_type="tomato",
        image_data_url="data:image/jpeg;base64,ZmFrZQ==",
        diagnosis=DiagnosisContext(
            crop_type="tomato",
            disease_name="Tomato Leaf Mold",
            confidence=0.98,
        ),
    )

    response = service._fallback_response(
        payload,
        [{"summary": "A common fungal disease affecting tomato leaves and stems."}],
    )

    assert "Tomato Leaf Mold" not in response.answer
    assert "common fungal disease" not in response.answer
    assert "cannot verify this photo" in response.answer
    assert response.recommended_actions == []
    assert response.show_treatment_ui is False


def test_knowledge_intent_selects_squash_over_stale_tomato_hint() -> None:
    service = KnowledgeService(Settings())
    payload = ChatRequest(
        user_message="How do I treat powdery mildew?",
        hint_crop_type="tomato",
    )

    matches = service._matching_inline_records(payload.user_message)

    assert [label_key for label_key, _ in matches] == ["squash_powdery_mildew"]


def test_text_fallback_answers_matching_disease_instead_of_tomato_intro() -> None:
    service = LlmService(Settings())
    payload = ChatRequest(
        user_message="How do I treat powdery mildew?",
        hint_crop_type="tomato",
    )

    response = service._fallback_response(
        payload,
        [
            {
                "title": "squash_powdery_mildew",
                "crop_type": "squash",
                "summary": "White powdery growth can spread across squash leaves.",
                "source": "test knowledge",
            }
        ],
    )

    assert "squash powdery mildew" in response.answer.lower()
    assert "I can help with your tomato" not in response.answer
    assert response.verified_crop == "squash"


def test_generic_greeting_ignores_stale_crop_hint_and_knowledge() -> None:
    service = LlmService(Settings())
    payload = ChatRequest(
        user_message="Hi",
        hint_crop_type="tomato",
    )

    response = service._fallback_response(
        payload,
        [
            {
                "title": "Tomato Early Blight",
                "crop_type": "tomato",
                "summary": "A common fungal disease.",
            }
        ],
    )

    assert response.answer == (
        "Hi. I'm CropCare AI. Tell me the crop and the problem you need help with, "
        "or send a close leaf photo if you want a diagnosis."
    )
    assert response.verified_crop == ""
    assert response.in_app_crop_scope is False


def test_greeting_with_explicit_crop_keeps_that_crop() -> None:
    service = LlmService(Settings())
    payload = ChatRequest(
        user_message="Hello, can you help with my eggplant crop?",
        hint_crop_type="tomato",
    )

    response = service._fallback_response(payload, [])

    assert "your eggplant crop" in response.answer
    assert "your tomato crop" not in response.answer
    assert response.verified_crop == "eggplant"


def test_unrelated_text_does_not_fetch_unfiltered_crop_knowledge() -> None:
    service = KnowledgeService(
        Settings(
            supabase_url="https://example.supabase.co",
            supabase_service_role_key="test-key",
        )
    )
    tracking_supabase = _TrackingKnowledgeSupabase()
    service._supabase = tracking_supabase

    records = asyncio.run(
        service.fetch_relevant_records(
            ChatRequest(user_message="Please remind me about tomorrow's meeting."),
        )
    )

    assert records == []
    assert tracking_supabase.fetch_calls == 0