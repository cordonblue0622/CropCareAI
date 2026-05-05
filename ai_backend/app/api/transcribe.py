from fastapi import APIRouter, Depends, File, UploadFile

from app.core.dependencies import get_current_user, get_whisper_service
from app.schemas.transcribe import TranscribeResponse
from app.schemas.user import AuthenticatedUser
from app.services.whisper_service import WhisperService

router = APIRouter()


@router.post("/transcribe", response_model=TranscribeResponse)
async def transcribe(
    audio: UploadFile = File(...),
    current_user: AuthenticatedUser = Depends(get_current_user),
    whisper_service: WhisperService = Depends(get_whisper_service),
) -> TranscribeResponse:
    audio_bytes = await audio.read()
    return await whisper_service.transcribe(
        audio_bytes=audio_bytes,
        filename=audio.filename or "audio.wav",
        requested_by=current_user,
    )