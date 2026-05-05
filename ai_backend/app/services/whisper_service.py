import tempfile
from pathlib import Path

from app.core.config import Settings
from app.schemas.transcribe import TranscribeResponse
from app.schemas.user import AuthenticatedUser


class WhisperService:
    def __init__(self, settings: Settings):
        self._settings = settings
        self._model = None

    async def transcribe(
        self,
        audio_bytes: bytes,
        filename: str,
        requested_by: AuthenticatedUser,
    ) -> TranscribeResponse:
        suffix = Path(filename).suffix or ".wav"

        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp_audio:
            temp_audio.write(audio_bytes)
            temp_audio_path = Path(temp_audio.name)

        try:
            if self._settings.openai_api_key:
                transcript, language = self._transcribe_with_openai(temp_audio_path)
                return TranscribeResponse(
                    status="ok",
                    transcript=transcript,
                    language=language,
                    source="openai-whisper",
                    notes=[f"Requested by {requested_by.id}."],
                )

            if self._settings.enable_mock_services:
                return TranscribeResponse(
                    status="ok",
                    transcript=(
                        f"Mock transcript for {filename}. Requested by {requested_by.id}."
                    ),
                    language="en",
                    source="mock-whisper",
                    notes=["Disable mock services after Whisper is configured."],
                )

            model = self._load_model()
            segments, info = model.transcribe(str(temp_audio_path))
            transcript = " ".join(segment.text.strip() for segment in segments).strip()

            return TranscribeResponse(
                status="ok",
                transcript=transcript,
                language=info.language,
                source="whisper",
            )
        finally:
            temp_audio_path.unlink(missing_ok=True)

    def _transcribe_with_openai(self, temp_audio_path: Path) -> tuple[str, str]:
        from openai import OpenAI

        client = OpenAI(api_key=self._settings.openai_api_key)
        with temp_audio_path.open("rb") as audio_file:
            response = client.audio.transcriptions.create(
                model="whisper-1",
                file=audio_file,
            )

        transcript = (getattr(response, "text", "") or "").strip()
        if not transcript:
            raise RuntimeError("OpenAI transcription returned an empty transcript.")

        language = getattr(response, "language", None) or "unknown"
        return transcript, language

    def _load_model(self):
        if self._model is None:
            from faster_whisper import WhisperModel

            self._settings.whisper_models_dir.mkdir(parents=True, exist_ok=True)
            self._model = WhisperModel(
                self._settings.whisper_model_size,
                device=self._settings.whisper_model_device,
                download_root=str(self._settings.whisper_models_dir),
            )
        return self._model