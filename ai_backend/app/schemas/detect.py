from pydantic import BaseModel, Field


class BoundingBox(BaseModel):
    x: float = Field(ge=0, le=1)
    y: float = Field(ge=0, le=1)
    width: float = Field(ge=0, le=1)
    height: float = Field(ge=0, le=1)


class DetectionItem(BaseModel):
    label: str
    label_key: str | None = None
    confidence: float = Field(ge=0, le=1)
    bbox: BoundingBox


class ModelInfo(BaseModel):
    name: str
    version: str


class DetectResponse(BaseModel):
    status: str
    source: str
    crop_type: str | None = None
    detections: list[DetectionItem]
    model: ModelInfo
    notes: list[str] = Field(default_factory=list)