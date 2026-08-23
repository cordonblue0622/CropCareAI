from typing import Literal

from pydantic import BaseModel, Field


class DiagnosisContext(BaseModel):
    crop_type: str | None = None
    label_key: str | None = None
    disease_name: str | None = None
    confidence: float | None = Field(default=None, ge=0, le=1)
    severity: str | None = None


class WeatherContext(BaseModel):
    location: str | None = None
    temperature_c: float | None = None
    humidity: float | None = None
    condition: str | None = None


class ConversationTurn(BaseModel):
    role: Literal["user", "assistant"]
    content: str


class ChatRequest(BaseModel):
    user_message: str
    crop_id: str | None = None
    diagnosis: DiagnosisContext | None = None
    image_data_url: str | None = None
    image_data_urls: list[str] = Field(default_factory=list)
    weather: WeatherContext | None = None
    conversation_history: list[ConversationTurn] = Field(default_factory=list)
    locale: str | None = "en"
    # When TFLite did not attach a diagnosis (e.g. eggplant/pechay), guides KB fetch + vision.
    hint_crop_type: str | None = None


class ChatResponse(BaseModel):
    answer: str
    recommended_actions: list[str]
    warnings: list[str]
    sources: list[str]
    model: str
    in_app_crop_scope: bool = True
    show_treatment_ui: bool = False