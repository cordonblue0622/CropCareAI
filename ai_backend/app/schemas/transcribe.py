from pydantic import BaseModel, Field


class TranscribeResponse(BaseModel):
    status: str
    transcript: str
    language: str
    source: str
    notes: list[str] = Field(default_factory=list)