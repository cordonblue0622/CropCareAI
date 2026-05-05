from app.core.config import Settings
from app.schemas.chat import ChatRequest, ChatResponse
from app.schemas.user import AuthenticatedUser

# Human-readable names for every label the trained EfficientNet model recognises.
_TRAINED_LABEL_NAMES: dict[str, str] = {
    "corn_cercospora_leaf_spot_gray_leaf_spot": "Corn – Cercospora Leaf Spot / Gray Leaf Spot",
    "corn_common_rust": "Corn – Common Rust",
    "corn_northern_leaf_blight": "Corn – Northern Leaf Blight",
    "corn_healthy": "Corn – Healthy",
    "eggplant_healthy": "Eggplant – Healthy",
    "eggplant_insect_pest": "Eggplant – Insect Pest Damage",
    "eggplant_leaf_spot": "Eggplant – Leaf Spot",
    "eggplant_mosaic_virus": "Eggplant – Mosaic Virus",
    "eggplant_small_leaf": "Eggplant – Small Leaf (Phyllody / Big Bud)",
    "eggplant_white_mold": "Eggplant – White Mold (Sclerotinia)",
    "eggplant_wilt": "Eggplant – Wilt (Fusarium / Bacterial)",
    "pepper_bacterial_spot": "Bell Pepper – Bacterial Spot",
    "pepper_healthy": "Bell Pepper – Healthy",
    "squash_powdery_mildew": "Squash – Powdery Mildew",
    "tomato_bacterial_spot": "Tomato – Bacterial Spot",
    "tomato_early_blight": "Tomato – Early Blight",
    "tomato_late_blight": "Tomato – Late Blight",
    "tomato_leaf_mold": "Tomato – Leaf Mold",
    "tomato_septoria_leaf_spot": "Tomato – Septoria Leaf Spot",
    "tomato_spider_mites": "Tomato – Spider Mites (Two-spotted)",
    "tomato_target_spot": "Tomato – Target Spot",
    "tomato_yellow_leaf_curl_virus": "Tomato – Yellow Leaf Curl Virus (TYLCV)",
    "tomato_mosaic_virus": "Tomato – Mosaic Virus (ToMV)",
    "tomato_healthy": "Tomato – Healthy",
}

_SYSTEM_PROMPT = """You are CropCare AI, an expert crop disease assistant trained to support Filipino smallholder farmers.

The app's AI model was trained specifically on the following 24 crop conditions. When the user asks about a diagnosis, ALWAYS tie your answer to the exact condition identified:

CORN: Cercospora Leaf Spot/Gray Leaf Spot · Common Rust · Northern Leaf Blight · Healthy
EGGPLANT: Healthy · Insect Pest Damage · Leaf Spot · Mosaic Virus · Small Leaf (Phyllody) · White Mold (Sclerotinia) · Wilt (Fusarium/Bacterial)
PEPPER (Bell): Bacterial Spot · Healthy
SQUASH: Powdery Mildew
TOMATO: Bacterial Spot · Early Blight · Late Blight · Leaf Mold · Septoria Leaf Spot · Spider Mites · Target Spot · Yellow Leaf Curl Virus · Mosaic Virus · Healthy

Rules:
1. Base your response on the diagnosis label provided. If knowledge records are supplied, incorporate their treatment steps directly.
2. Structure every disease response with: What it is → Key symptoms → Immediate action → Treatment → Prevention tip.
3. If the photo has no match or is unclear, advise the farmer to retake a close-up shot of the affected leaf in good lighting.
4. Prefer organic/integrated pest management options first; mention chemical options with exact safety notes.
5. Use simple English. Avoid jargon. Keep answers under 250 words unless the farmer asks for more detail.
6. If confidence is below 40%, explicitly tell the farmer the result is uncertain and recommend a follow-up scan.
7. Return plain text only – no markdown, no bullet symbols."""


class LlmService:
    def __init__(self, settings: Settings):
        self._settings = settings

    async def generate_response(
        self,
        payload: ChatRequest,
        current_user: AuthenticatedUser,
        knowledge_records: list[dict[str, str]],
    ) -> ChatResponse:
        if not self._settings.openai_api_key:
            return self._fallback_response(payload, knowledge_records)

        from openai import OpenAI

        client = OpenAI(api_key=self._settings.openai_api_key)

        # ── Build knowledge block ────────────────────────────────────────────
        knowledge_text = "\n".join(
            f"- {record.get('title', 'Untitled')}: {record.get('summary', '')}"
            for record in knowledge_records
        )

        # ── Build user context ───────────────────────────────────────────────
        user_context_lines = [f"Question: {payload.user_message}"]

        if knowledge_text:
            user_context_lines.append(f"\nRelevant knowledge:\n{knowledge_text}")

        if payload.diagnosis:
            label_key = payload.diagnosis.label_key or ""
            disease_label = _TRAINED_LABEL_NAMES.get(label_key, payload.diagnosis.disease_name or label_key)
            confidence_pct = (
                f"{payload.diagnosis.confidence * 100:.0f}%"
                if payload.diagnosis.confidence is not None
                else "unknown"
            )
            user_context_lines.append(
                f"\nDiagnosis from the AI model:"
                f"\n- Identified condition: {disease_label}"
                f"\n- Model label key: {label_key}"
                f"\n- Confidence: {confidence_pct}"
                f"\n- Crop: {payload.diagnosis.crop_type or 'unknown'}"
                f"\n- Severity: {payload.diagnosis.severity or 'unknown'}"
            )

        if payload.weather:
            w = payload.weather
            user_context_lines.append(
                f"\nCurrent weather: {w.condition or 'N/A'}, "
                f"Temp {w.temperature_c or 'N/A'}°C, "
                f"Humidity {w.humidity or 'N/A'}%"
            )

        user_context = "\n".join(user_context_lines)

        user_content: list[dict[str, str]] = [
            {"type": "input_text", "text": user_context}
        ]
        if payload.image_data_url:
            user_content.append(
                {"type": "input_image", "image_url": payload.image_data_url}
            )

        try:
            response = client.responses.create(
                model=self._settings.openai_model,
                input=[
                    {
                        "role": "system",
                        "content": [{"type": "input_text", "text": _SYSTEM_PROMPT}],
                    },
                    {"role": "user", "content": user_content},
                ],
            )

            answer = getattr(response, "output_text", None) or (
                "I could not generate an answer from the configured model."
            )

            return ChatResponse(
                answer=answer,
                recommended_actions=self._recommended_actions(payload, knowledge_records),
                warnings=self._warnings(payload),
                sources=[record.get("source", "knowledge-base") for record in knowledge_records]
                or ["openai-vision" if payload.image_data_url else "openai"],
                model=self._settings.openai_model,
            )
        except Exception:
            return self._fallback_response(payload, knowledge_records)

    def _recommended_actions(
        self,
        payload: ChatRequest,
        knowledge_records: list[dict[str, str]],
    ) -> list[str]:
        actions: list[str] = []
        if payload.image_data_url:
            actions.append("Compare the AI read with the actual leaf symptoms in the photo.")
        if knowledge_records:
            actions.extend(
                record.get("title", "").strip()
                for record in knowledge_records
                if record.get("title", "").strip()
            )

        actions.extend(
            [
                "Inspect the affected crop again within 24 hours.",
                "Confirm any spray or treatment plan before field application.",
            ]
        )

        deduped: list[str] = []
        for action in actions:
            if action not in deduped:
                deduped.append(action)
        return deduped[:3]

    def _warnings(self, payload: ChatRequest) -> list[str]:
        warnings = ["Verify treatment dosage and intervals before spraying."]
        if payload.diagnosis and payload.diagnosis.confidence is not None:
            if payload.diagnosis.confidence < 0.40:
                warnings.append(
                    "Diagnosis confidence is below 40%. Use a clearer, close-up photo of the affected leaf and rescan."
                )
        elif payload.image_data_url:
            warnings.append("Image-only analysis should be confirmed against field symptoms.")
        return warnings[:2]

    def _fallback_response(
        self,
        payload: ChatRequest,
        knowledge_records: list[dict[str, str]],
    ) -> ChatResponse:
        disease = payload.diagnosis.disease_name if payload.diagnosis else None
        label_key = payload.diagnosis.label_key if payload.diagnosis else None
        crop = payload.diagnosis.crop_type if payload.diagnosis else None
        disease_label = _TRAINED_LABEL_NAMES.get(label_key or "", disease or "")
        summary = knowledge_records[0]["summary"] if knowledge_records else ""

        answer_parts: list[str] = []
        if disease_label:
            answer_parts.append(
                f"The scan identified: {disease_label}."
            )
        if summary:
            answer_parts.append(summary)
        else:
            answer_parts.append(
                "Please ensure the Supabase knowledge base is populated with treatment data for your trained model classes "
                "so the assistant can provide specific guidance."
            )

        if payload.image_data_url:
            answer_parts.append(
                "The uploaded image should still be verified against field symptoms before starting any treatment."
            )
        answer_parts.append(f"Your question: {payload.user_message}")

        return ChatResponse(
            answer=" ".join(answer_parts),
            recommended_actions=self._recommended_actions(payload, knowledge_records),
            warnings=self._warnings(payload),
            sources=[record.get("source", "knowledge-base") for record in knowledge_records]
            or ["knowledge-base"],
            model="knowledge-fallback",
        )

    def __init__(self, settings: Settings):
        self._settings = settings

    async def generate_response(
        self,
        payload: ChatRequest,
        current_user: AuthenticatedUser,
        knowledge_records: list[dict[str, str]],
    ) -> ChatResponse:
        if not self._settings.openai_api_key:
            return self._fallback_response(payload, knowledge_records)

        from openai import OpenAI

        client = OpenAI(api_key=self._settings.openai_api_key)

        knowledge_text = "\n".join(
            f"- {record.get('title', 'Untitled')}: {record.get('summary', '')}"
            for record in knowledge_records
        )
        user_context = (
            f"User ID: {current_user.id}\n"
            f"Question: {payload.user_message}\n"
            f"Knowledge:\n{knowledge_text or '- none'}"
        )

        if payload.diagnosis:
            user_context += (
                "\nDiagnosis context:\n"
                f"- crop_type: {payload.diagnosis.crop_type or 'unknown'}\n"
                f"- label_key: {payload.diagnosis.label_key or 'unknown'}\n"
                f"- disease_name: {payload.diagnosis.disease_name or 'unknown'}\n"
                f"- confidence: {payload.diagnosis.confidence or 'unknown'}\n"
                f"- severity: {payload.diagnosis.severity or 'unknown'}"
            )

        user_content: list[dict[str, str]] = [
            {"type": "input_text", "text": user_context}
        ]
        if payload.image_data_url:
            user_content.append(
                {"type": "input_image", "image_url": payload.image_data_url}
            )

        try:
            response = client.responses.create(
                model=self._settings.openai_model,
                input=[
                    {
                        "role": "system",
                        "content": [
                            {
                                "type": "input_text",
                                "text": (
                                    "You are CropCare AI. Provide concise, practical crop "
                                    "guidance grounded in the supplied knowledge. If an image is "
                                    "provided, analyze the visible crop condition directly from the "
                                    "photo and clearly state uncertainty when needed. Return plain text."
                                ),
                            }
                        ],
                    },
                    {
                        "role": "user",
                        "content": user_content,
                    },
                ],
            )

            answer = getattr(response, "output_text", None) or (
                "I could not generate an answer from the configured model."
            )

            return ChatResponse(
                answer=answer,
                recommended_actions=self._recommended_actions(payload, knowledge_records),
                warnings=self._warnings(payload),
                sources=[record.get("source", "knowledge-base") for record in knowledge_records]
                or ["openai-vision" if payload.image_data_url else "openai"],
                model=self._settings.openai_model,
            )
        except Exception:
            return self._fallback_response(payload, knowledge_records)

    def _recommended_actions(
        self,
        payload: ChatRequest,
        knowledge_records: list[dict[str, str]],
    ) -> list[str]:
        actions: list[str] = []
        if payload.image_data_url:
            actions.append("Compare the AI read with the actual leaf symptoms in the photo.")
        if knowledge_records:
            actions.extend(
                record.get("title", "").strip()
                for record in knowledge_records
                if record.get("title", "").strip()
            )

        actions.extend(
            [
                "Inspect the affected crop again within 24 hours.",
                "Confirm any spray or treatment plan before field application.",
            ]
        )

        deduped: list[str] = []
        for action in actions:
            if action not in deduped:
                deduped.append(action)
        return deduped[:3]

    def _warnings(self, payload: ChatRequest) -> list[str]:
        warnings = ["Verify treatment dosage and intervals before spraying."]
        if payload.diagnosis and payload.diagnosis.confidence is not None:
            if payload.diagnosis.confidence < 0.6:
                warnings.append("Diagnosis confidence is low; use a clearer follow-up image if possible.")
        elif payload.image_data_url:
            warnings.append("Image-only analysis should be confirmed against field symptoms.")
        return warnings[:2]

    def _fallback_response(
        self,
        payload: ChatRequest,
        knowledge_records: list[dict[str, str]],
    ) -> ChatResponse:
        disease = payload.diagnosis.disease_name if payload.diagnosis else None
        crop = payload.diagnosis.crop_type if payload.diagnosis else None
        summary = knowledge_records[0]["summary"] if knowledge_records else ""

        answer_parts = [
            summary or "Here is the best guidance available from the current crop knowledge base.",
        ]
        if crop or disease:
            answer_parts.append(
                f"Field context: crop={crop or 'unknown'}, disease={disease or 'unknown'}."
            )
        if payload.image_data_url:
            answer_parts.append(
                "The uploaded image should still be verified against field symptoms before treatment."
            )
        answer_parts.append(f"Question: {payload.user_message}")

        return ChatResponse(
            answer=" ".join(answer_parts),
            recommended_actions=self._recommended_actions(payload, knowledge_records),
            warnings=self._warnings(payload),
            sources=[record.get("source", "knowledge-base") for record in knowledge_records]
            or ["knowledge-base"],
            model="knowledge-fallback",
        )