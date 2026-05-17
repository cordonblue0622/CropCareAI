import json
import logging
import re
from typing import Any

from app.core.config import Settings
from app.schemas.chat import ChatRequest, ChatResponse
from app.schemas.user import AuthenticatedUser

logger = logging.getLogger(__name__)

_CCAI_JSON_PREFIX = "CCAI_JSON:"

# Human-readable names for every label the trained EfficientNet model recognises.
_TRAINED_LABEL_NAMES: dict[str, str] = {
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

_SYSTEM_PROMPT = """You are CropCare AI, an expert crop disease assistant for Filipino smallholder farmers.

App scope (only these vegetables): tomato, bell pepper, squash, eggplant, and bok choy (pechay).
If the photo is not one of these crops (for example rice, corn, ornamentals, pets, food on a plate), do NOT invent a vegetable disease. Briefly say CropCare focuses on those five crops and ask for a leaf photo of one of them.

The on-device TFLite scanner only covers tomato, pepper, and squash diseases (13 conditions below). For eggplant and pechay there is no on-device model: rely on the image and the knowledge excerpts.

Scanner labels (hints only — verify on the image):
PEPPER: Bacterial Spot · Healthy
SQUASH: Powdery Mildew
TOMATO: Bacterial Spot · Early Blight · Late Blight · Leaf Mold · Septoria Leaf Spot · Spider Mites · Target Spot · Yellow Leaf Curl Virus · Mosaic Virus · Healthy

Rules for the farmer-visible answer:
1. Treat scanner output as a hint. If the image contradicts it, say so and correct.
2. If knowledge excerpts match the verified problem, use their treatment wording (including any day-by-day steps given in the excerpt).
3. Structure the first diagnosis reply as plain text sections in this order, with labels exactly like this (no markdown, no bullets):
What it is:
Key symptoms:
Immediate action:
Treatment:
Prevention tip:
4. If the photo is unclear, ask for a closer, well-lit leaf photo.
5. Prefer organic/IPM first; if you mention chemicals, add brief safety cautions in the answer body.
6. Keep under 260 words unless the farmer explicitly asks for more detail.
7. If scanner confidence is below 60%, say the result is uncertain and suggest a clearer photo.

After your answer, output exactly one extra final line and nothing after it. That line must start with CCAI_JSON: followed by compact JSON (no line breaks inside the JSON) with these keys:
in_app_crop_scope (boolean), show_treatment_ui (boolean), verified_crop (string: tomato, pepper, squash, eggplant, pechay, or empty), verified_disease (string or empty), treatment_actions (array of 3-7 short imperative steps, or empty array).

JSON rules:
- in_app_crop_scope false if the subject is outside the five crops or not a plant/crop photo.
- show_treatment_ui true only if in_app_crop_scope AND you identified a specific disease/pests/problem that merits a plan (not for a clearly healthy plant with no action). When true, treatment_actions must be non-empty.
- If in_app_crop_scope is false, show_treatment_ui must be false and treatment_actions must be []."""

_CONVERSATIONAL_PROMPT = """You are CropCare AI helping a smallholder vegetable farmer.

The farmer is continuing an earlier chat (they may have already received a diagnosis). Answer their latest question directly in plain, simple English and keep the reply anchored to the active crop and problem already established in the chat unless the farmer clearly switches crops.

Rules:
- Stay focused on the active crop context. Do not drift to another crop unless the farmer explicitly changes crops.
- If the farmer asks about a product, brand, spray, or active ingredient, explain whether it fits the active crop and likely problem, what it is mainly used for, and when it would not be a good fit.
- If web search results are available, use them to verify what a named product is for or what active ingredient it contains. If reliable web results are not available, use your own crop-protection knowledge and clearly tell the farmer to verify the label, crop registration, dosage, and pre-harvest interval locally.
- Do NOT repeat the full diagnosis template (no required "What it is / Treatment" sections) unless they explicitly ask you to restate the plan.
- Do NOT add generic warning footers or tip lists unless the question is about safety or compliance.
- Stay focused on the question. Under 200 words unless they ask for detail.
- If the question is unrelated to crops, answer briefly and politely.
- Plain text only — no markdown."""

_SUPPORTED_TREATMENT_CARD_CROPS = {
    "tomato",
    "eggplant",
    "pepper",
    "pechay",
    "squash",
}

_CROP_ALIASES: dict[str, tuple[str, ...]] = {
    "tomato": ("tomato",),
    "pepper": ("pepper", "bell pepper", "capsicum"),
    "squash": ("squash", "kalabasa"),
    "eggplant": ("eggplant", "talong"),
    "pechay": ("pechay", "bok choy", "bokchoy"),
}

_PRODUCT_QUERY_HINTS = (
    "product",
    "brand",
    "spray",
    "fungicide",
    "bactericide",
    "pesticide",
    "insecticide",
    "miticide",
    "fertilizer",
    "fertiliser",
    "active ingredient",
    "can i use",
    "should i use",
    "recommend",
    "recommendation",
    "copper",
    "mancozeb",
    "chlorothalonil",
    "metalaxyl",
    "azoxystrobin",
    "difenoconazole",
    "abamectin",
    "spinosad",
    "neem",
    "imidacloprid",
    "thiophanate",
    "potassium bicarbonate",
)


class LlmService:
    def __init__(self, settings: Settings):
        self._settings = settings

    def _split_ccai_json(self, raw_answer: str) -> tuple[str, dict[str, Any]]:
        text = (raw_answer or "").rstrip()
        if _CCAI_JSON_PREFIX not in text:
            return raw_answer, {}

        lines = text.split("\n")
        last_line = lines[-1].strip() if lines else ""
        if not last_line.startswith(_CCAI_JSON_PREFIX):
            return raw_answer, {}

        json_part = last_line[len(_CCAI_JSON_PREFIX) :].strip()
        try:
            meta = json.loads(json_part)
            if not isinstance(meta, dict):
                return raw_answer, {}
        except json.JSONDecodeError:
            logger.warning("Could not parse CCAI_JSON footer; using empty metadata.")
            return raw_answer, {}

        body = "\n".join(lines[:-1]).rstrip()
        return body, meta

    def _normalize_verified_crop(self, value: str) -> str:
        v = (value or "").strip().lower()
        aliases = {
            "bok choy": "pechay",
            "bokchoy": "pechay",
            "bell pepper": "pepper",
            "capsicum": "pepper",
        }
        return aliases.get(v, v)

    async def generate_response(
        self,
        payload: ChatRequest,
        current_user: AuthenticatedUser,
        knowledge_records: list[dict[str, Any]],
    ) -> ChatResponse:
        _ = current_user
        if not self._settings.openai_api_key:
            return self._fallback_response(payload, knowledge_records)

        from openai import OpenAI

        client = OpenAI(api_key=self._settings.openai_api_key)

        active_crop = self._resolve_active_crop(payload, knowledge_records)
        is_follow_up = len(payload.conversation_history) >= 2 or not self._should_use_diagnosis_template(payload)
        is_product_query = self._is_product_query(payload.user_message)
        system_prompt = self._build_system_prompt(
            is_follow_up=is_follow_up,
            active_crop=active_crop,
            is_product_query=is_product_query,
        )

        knowledge_text = self._format_knowledge_records(knowledge_records)

        user_context_lines: list[str] = []

        conversation_text = self._format_conversation_history(payload)
        if conversation_text:
            user_context_lines.append(f"Recent conversation:\n{conversation_text}")

        if active_crop:
            user_context_lines.append(
                f"Active crop focus for this chat: {active_crop}"
            )

        user_context_lines.append(f"Farmer's latest message: {payload.user_message}")

        if is_product_query:
            user_context_lines.append(
                "This is a product-fit question. If a product, spray, or active ingredient is named, evaluate whether it matches the active crop and likely crop problem before recommending it."
            )

        if knowledge_text:
            user_context_lines.append(f"\nRelevant knowledge:\n{knowledge_text}")

        if payload.diagnosis:
            label_key = payload.diagnosis.label_key or ""
            disease_label = _TRAINED_LABEL_NAMES.get(
                label_key, payload.diagnosis.disease_name or label_key
            )
            confidence_pct = (
                f"{payload.diagnosis.confidence * 100:.0f}%"
                if payload.diagnosis.confidence is not None
                else "unknown"
            )
            user_context_lines.append(
                f"\nScanner hint from the TFLite model (verify this against the image before answering):"
                f"\n- Closest condition: {disease_label}"
                f"\n- Model label key: {label_key}"
                f"\n- Confidence: {confidence_pct}"
                f"\n- Crop: {payload.diagnosis.crop_type or 'unknown'}"
                f"\n- Severity: {payload.diagnosis.severity or 'unknown'}"
            )
        elif (payload.hint_crop_type or "").strip():
            user_context_lines.append(
                f"\nFarmer selected crop type hint (no on-device scan): {payload.hint_crop_type.strip()}"
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
            response, used_web_search = self._create_response(
                client,
                system_prompt=system_prompt,
                user_content=user_content,
                allow_web_search=is_product_query,
            )

            raw_answer = getattr(response, "output_text", None) or (
                "I could not generate an answer from the configured model."
            )
            answer_body, meta = self._split_ccai_json(raw_answer)

            recommended_actions = self._build_recommended_actions(
                payload,
                knowledge_records,
                answer_body,
                meta=meta,
                is_follow_up=is_follow_up,
            )

            in_scope, show_ui = self._scope_flags_from_meta(
                meta=meta,
                is_follow_up=is_follow_up,
                recommended_actions=recommended_actions,
            )

            return ChatResponse(
                answer=answer_body,
                recommended_actions=recommended_actions if show_ui else [],
                warnings=self._warnings(payload, is_follow_up=is_follow_up, in_scope=in_scope),
                sources=self._response_sources(
                    payload,
                    knowledge_records,
                    include_openai=True,
                    include_web_search=used_web_search,
                ),
                model=self._settings.openai_model,
                in_app_crop_scope=in_scope,
                show_treatment_ui=show_ui and bool(recommended_actions),
            )
        except Exception:
            logger.exception("OpenAI chat response failed. Falling back to diagnosis-grounded guidance.")
            return self._fallback_response(payload, knowledge_records)

    def _build_system_prompt(
        self,
        *,
        is_follow_up: bool,
        active_crop: str,
        is_product_query: bool,
    ) -> str:
        base = _CONVERSATIONAL_PROMPT if is_follow_up else _SYSTEM_PROMPT

        extra_rules: list[str] = []
        if active_crop:
            extra_rules.append(
                f"Active crop focus for this reply: {active_crop}. Keep the answer specific to {active_crop} unless the farmer clearly switches crops."
            )
        if is_product_query:
            extra_rules.append(
                "The farmer is asking for product guidance. Prefer product-fit reasoning: identify the active ingredient or product type, explain whether it fits the active crop and likely problem, and do not claim label approval unless you can support it."
            )

        if not extra_rules:
            return base
        return f"{base}\n\n" + "\n".join(extra_rules)

    def _create_response(
        self,
        client: Any,
        *,
        system_prompt: str,
        user_content: list[dict[str, str]],
        allow_web_search: bool,
    ) -> tuple[Any, bool]:
        payload = [
            {
                "role": "system",
                "content": [{"type": "input_text", "text": system_prompt}],
            },
            {"role": "user", "content": user_content},
        ]

        if allow_web_search:
            try:
                response = client.responses.create(
                    model=self._settings.openai_model,
                    input=payload,
                    tools=[{"type": "web_search_preview"}],
                )
                return response, self._response_used_web_search(response)
            except Exception:
                logger.exception(
                    "OpenAI web search request failed. Retrying without web search."
                )

        response = client.responses.create(
            model=self._settings.openai_model,
            input=payload,
        )
        return response, False

    def _response_used_web_search(self, response: Any) -> bool:
        for item in getattr(response, "output", []) or []:
            if getattr(item, "type", "") == "web_search_call":
                return True
        return False

    def _resolve_active_crop(
        self,
        payload: ChatRequest,
        knowledge_records: list[dict[str, Any]],
    ) -> str:
        if payload.diagnosis and (payload.diagnosis.crop_type or "").strip():
            return self._normalize_verified_crop(payload.diagnosis.crop_type or "")

        hint_crop = self._normalize_verified_crop(payload.hint_crop_type or "")
        if hint_crop in _SUPPORTED_TREATMENT_CARD_CROPS:
            return hint_crop

        for record in knowledge_records:
            crop_type = self._normalize_verified_crop(str(record.get("crop_type") or ""))
            if crop_type in _SUPPORTED_TREATMENT_CARD_CROPS:
                return crop_type

        recent_text = " ".join(
            [payload.user_message]
            + [turn.content for turn in payload.conversation_history[-6:]]
        )
        return self._infer_crop_from_text(recent_text)

    def _infer_crop_from_text(self, text: str) -> str:
        normalized = (text or "").strip().lower()
        if not normalized:
            return ""

        for crop, aliases in _CROP_ALIASES.items():
            if any(alias in normalized for alias in aliases):
                return crop
        return ""

    def _is_product_query(self, user_message: str) -> bool:
        normalized = (user_message or "").strip().lower()
        if not normalized:
            return False

        if any(token in normalized for token in _PRODUCT_QUERY_HINTS):
            return True

        return bool(
            re.search(
                r"\b(can|should|which|what)\b.{0,40}\b(use|buy|spray|apply|recommend)\b",
                normalized,
            )
        )

    def _should_use_diagnosis_template(self, payload: ChatRequest) -> bool:
        return bool(payload.image_data_url or payload.diagnosis)

    def _is_greeting(self, user_message: str) -> bool:
        normalized = re.sub(r"\s+", " ", (user_message or "").strip().lower())
        if not normalized:
            return False

        greetings = (
            "hi",
            "hello",
            "hey",
            "good morning",
            "good afternoon",
            "good evening",
        )
        return any(
            normalized == greeting or normalized.startswith(f"{greeting} ")
            for greeting in greetings
        )

    def _intro_response(self, user_message: str, active_crop: str) -> str:
        if self._is_greeting(user_message):
            if active_crop:
                return (
                    f"Hello. I can help with your {active_crop} crop. Ask about symptoms, "
                    "treatment timing, or a product you want to check, or upload a close leaf photo when you want a diagnosis."
                )
            return (
                "Hello. I can help with tomato, bell pepper, squash, eggplant, and pechay. "
                "Tell me which crop you want help with, ask a crop question, or upload a close leaf photo when you are ready."
            )

        if active_crop:
            return (
                f"I can help with your {active_crop} crop. Tell me the symptom, treatment step, "
                "or product you want to check, or upload a close leaf photo when you want a diagnosis."
            )

        return (
            "I can help with tomato, bell pepper, squash, eggplant, and pechay. "
            "Tell me which crop you are working on, describe the symptom, or upload a close leaf photo when you want a diagnosis."
        )

    def _scope_flags_from_meta(
        self,
        *,
        meta: dict[str, Any],
        is_follow_up: bool,
        recommended_actions: list[str],
    ) -> tuple[bool, bool]:
        if is_follow_up:
            return True, False

        in_scope = bool(meta.get("in_app_crop_scope", True))
        show_raw = meta.get("show_treatment_ui")
        if show_raw is None:
            show_ui = bool(recommended_actions)
        else:
            show_ui = bool(show_raw)

        if not in_scope:
            show_ui = False
        return in_scope, show_ui

    def _build_recommended_actions(
        self,
        payload: ChatRequest,
        knowledge_records: list[dict[str, Any]],
        answer: str,
        *,
        meta: dict[str, Any],
        is_follow_up: bool,
    ) -> list[str]:
        if is_follow_up:
            return []

        in_scope = bool(meta.get("in_app_crop_scope", True))
        show_ui = meta.get("show_treatment_ui")
        if show_ui is False or not in_scope:
            return []

        from_meta = self._normalize_string_list(meta.get("treatment_actions"))
        deduped_meta: list[str] = []
        for a in from_meta:
            if a and a not in deduped_meta:
                deduped_meta.append(a)
        if deduped_meta:
            return deduped_meta[:7]

        verified = self._normalize_verified_crop(str(meta.get("verified_crop") or ""))
        crop_type = verified
        if crop_type not in _SUPPORTED_TREATMENT_CARD_CROPS:
            if payload.diagnosis and (payload.diagnosis.crop_type or "").strip():
                crop_type = (payload.diagnosis.crop_type or "").strip().lower()
            elif (payload.hint_crop_type or "").strip():
                crop_type = (payload.hint_crop_type or "").strip().lower()
                crop_type = self._normalize_verified_crop(crop_type)

        if crop_type not in _SUPPORTED_TREATMENT_CARD_CROPS:
            return []

        return self._actions_from_knowledge(knowledge_records, answer, crop_type)

    def _actions_from_knowledge(
        self,
        knowledge_records: list[dict[str, Any]],
        answer: str,
        crop_type: str,
    ) -> list[str]:
        if crop_type not in _SUPPORTED_TREATMENT_CARD_CROPS:
            return []
        actions: list[str] = []
        for record in knowledge_records:
            actions.extend(self._normalize_string_list(record.get("treatment_steps")))
            day_lines = self._normalize_string_list(record.get("treatment_day_lines"))
            for line in day_lines:
                if line and line not in actions:
                    actions.append(line)
            if not actions:
                actions.extend(
                    self._extract_treatment_actions(record.get("summary", ""))
                )

        if not actions and answer.strip():
            actions.extend(self._extract_treatment_actions(answer))

        deduped: list[str] = []
        for action in actions:
            if action not in deduped:
                deduped.append(action)
        return deduped[:7]

    def _warnings(self, payload: ChatRequest, *, is_follow_up: bool, in_scope: bool) -> list[str]:
        if is_follow_up or not in_scope:
            return []

        warnings = ["Verify treatment dosage and intervals before spraying."]
        if payload.diagnosis and payload.diagnosis.confidence is not None:
            if payload.diagnosis.confidence < 0.60:
                warnings.append(
                    "Diagnosis confidence is below 60%. Use a clearer, close-up photo of the affected leaf and rescan."
                )
        elif payload.image_data_url:
            warnings.append("Image-only analysis should be confirmed against field symptoms.")
        return warnings[:2]

    def _fallback_response(
        self,
        payload: ChatRequest,
        knowledge_records: list[dict[str, Any]],
    ) -> ChatResponse:
        active_crop = self._resolve_active_crop(payload, knowledge_records)
        if not self._should_use_diagnosis_template(payload):
            return ChatResponse(
                answer=self._intro_response(payload.user_message, active_crop),
                recommended_actions=[],
                warnings=[],
                sources=self._response_sources(
                    payload,
                    knowledge_records,
                    include_openai=False,
                ),
                model="knowledge-fallback",
                in_app_crop_scope=bool(active_crop),
                show_treatment_ui=False,
            )

        disease = payload.diagnosis.disease_name if payload.diagnosis else None
        label_key = payload.diagnosis.label_key if payload.diagnosis else None
        disease_label = _TRAINED_LABEL_NAMES.get(label_key or "", disease or "")
        summary = knowledge_records[0]["summary"] if knowledge_records else ""

        answer_parts: list[str] = []
        if disease_label:
            answer_parts.append(
                f"Based on the scan, the closest detected condition is {disease_label}."
            )
        if summary:
            answer_parts.append(summary)
        elif payload.diagnosis:
            answer_parts.append(
                "I couldn't reach the OpenAI response model right now, so I can only reflect the scan result. "
                "Please send the message again in a moment for a fuller conversational reply."
            )
        else:
            answer_parts.append(
                "I couldn't reach the OpenAI response model right now. Please try again in a moment, "
                "or attach a clearer close-up photo of the affected leaf."
            )

        if payload.diagnosis and payload.diagnosis.confidence is not None:
            if payload.diagnosis.confidence < 0.60:
                answer_parts.append(
                    "The scan confidence is still low, so please confirm it with a clearer leaf photo before treating."
                )

        answer = " ".join(part.strip() for part in answer_parts if part.strip())

        crop_guess = ""
        if payload.diagnosis and (payload.diagnosis.crop_type or "").strip():
            crop_guess = self._normalize_verified_crop(
                payload.diagnosis.crop_type.strip().lower()
            )
        elif (payload.hint_crop_type or "").strip():
            crop_guess = self._normalize_verified_crop(
                payload.hint_crop_type.strip().lower()
            )

        actions = self._actions_from_knowledge(knowledge_records, answer, crop_guess)

        return ChatResponse(
            answer=answer,
            recommended_actions=actions,
            warnings=self._warnings(
                payload,
                is_follow_up=len(payload.conversation_history) >= 2,
                in_scope=True,
            ),
            sources=self._response_sources(
                payload,
                knowledge_records,
                include_openai=False,
            ),
            model="knowledge-fallback",
            in_app_crop_scope=True,
            show_treatment_ui=bool(actions),
        )

    def _format_conversation_history(self, payload: ChatRequest) -> str:
        lines: list[str] = []
        for turn in payload.conversation_history[-6:]:
            content = " ".join(turn.content.split())
            if not content:
                continue
            prefix = "Farmer" if turn.role == "user" else "CropCare AI"
            lines.append(f"{prefix}: {content}")
        return "\n".join(lines)

    def _format_knowledge_records(self, knowledge_records: list[dict[str, Any]]) -> str:
        parts: list[str] = []
        for record in knowledge_records:
            title = record.get("title", "Untitled")
            summary = record.get("summary", "")
            entry = f"- {title}: {summary}".strip()
            steps = self._normalize_string_list(record.get("treatment_steps"))
            if steps:
                entry = f"{entry}\n  Structured treatment steps: {' | '.join(steps)}"
            day_lines = self._normalize_string_list(record.get("treatment_day_lines"))
            if day_lines:
                entry = f"{entry}\n  Day-by-day plan: {' || '.join(day_lines)}"
            prev = self._normalize_string_list(record.get("prevention_steps"))
            if prev:
                entry = f"{entry}\n  Prevention steps: {' | '.join(prev)}"
            parts.append(entry)
        return "\n".join(part for part in parts if part.strip())

    def _normalize_string_list(self, raw: Any) -> list[str]:
        if raw is None:
            return []
        if isinstance(raw, list):
            return [str(item).strip() for item in raw if str(item).strip()]
        if isinstance(raw, str):
            text = raw.strip()
            return [text] if text else []
        return []

    def _extract_treatment_actions(self, text: str) -> list[str]:
        if not text.strip():
            return []

        actions: list[str] = []
        sections = [
            self._extract_section(
                text, "Immediate action", ["Treatment", "Prevention tip", "Prevention"]
            ),
            self._extract_section(
                text, "Treatment", ["Prevention tip", "Prevention", "Warnings"]
            ),
        ]

        for section in sections:
            if not section:
                continue
            actions.extend(self._sentences_to_actions(section))

        if actions:
            return actions[:5]

        treatment_match = re.search(
            r"Treatment\s*:\s*(.+?)(?:Prevention(?: tip)?\s*:|Warnings\s*:|$)",
            text,
            re.IGNORECASE | re.DOTALL,
        )
        if treatment_match:
            return self._sentences_to_actions(treatment_match.group(1))[:5]

        return []

    def _extract_section(self, text: str, label: str, next_labels: list[str]) -> str:
        next_pattern = "|".join(re.escape(item) for item in next_labels)
        pattern = (
            rf"{re.escape(label)}\s*:\s*(.+?)" rf"(?:(?:{next_pattern})\s*:|$)"
        )
        match = re.search(pattern, text, re.IGNORECASE | re.DOTALL)
        if not match:
            return ""
        return match.group(1).strip()

    def _sentences_to_actions(self, text: str) -> list[str]:
        normalized = re.sub(r"\s+", " ", text).strip()
        if not normalized:
            return []
        sentences = re.split(r"(?<=[.!?])\s+", normalized)
        return [sentence.strip() for sentence in sentences if sentence.strip()]

    def _response_sources(
        self,
        payload: ChatRequest,
        knowledge_records: list[dict[str, Any]],
        *,
        include_openai: bool,
        include_web_search: bool = False,
    ) -> list[str]:
        sources: list[str] = []
        if include_openai:
            sources.append("openai-vision" if payload.image_data_url else "openai")
        if include_web_search:
            sources.append("openai-web-search")
        sources.extend(
            str(record.get("source", "knowledge-base")) for record in knowledge_records
        )

        deduped: list[str] = []
        for source in sources:
            normalized = source.strip()
            if normalized and normalized not in deduped:
                deduped.append(normalized)
        if deduped:
            return deduped
        return ["knowledge-base"] if not include_openai else ["openai"]
