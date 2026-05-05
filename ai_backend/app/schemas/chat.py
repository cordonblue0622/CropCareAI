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


class ChatRequest(BaseModel):
    user_message: str
    crop_id: str | None = None
    diagnosis: DiagnosisContext | None = None
    image_data_url: str | None = None
    weather: WeatherContext | None = None
    locale: str | None = "en"


class ChatResponse(BaseModel):
    answer: str
    recommended_actions: list[str]
    warnings: list[str]
    sources: list[str]
    model: str