from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

_BACKEND_ENV_FILE = Path(__file__).resolve().parents[2] / ".env"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=_BACKEND_ENV_FILE,
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_env: str = Field(default="development", alias="APP_ENV")
    api_host: str = Field(default="0.0.0.0", alias="API_HOST")
    api_port: int = Field(default=8000, alias="API_PORT")
    api_version: str = Field(default="0.1.0", alias="API_VERSION")
    log_level: str = Field(default="INFO", alias="LOG_LEVEL")

    enable_mock_services: bool = Field(default=True, alias="ENABLE_MOCK_SERVICES")
    require_auth: bool = Field(default=False, alias="REQUIRE_AUTH")
    cors_origins: str = Field(default="*", alias="CORS_ORIGINS")

    supabase_url: str = Field(
        default="",
        alias="SUPABASE_URL",
    )
    supabase_anon_key: str = Field(
        default="",
        alias="SUPABASE_ANON_KEY",
    )
    supabase_service_role_key: str = Field(
        default="",
        alias="SUPABASE_SERVICE_ROLE_KEY",
    )
    password_reset_redirect_url: str = Field(
        default="cropcareai://auth/reset-password",
        alias="PASSWORD_RESET_REDIRECT_URL",
    )
    admin_invite_redirect_url: str = Field(
        default="http://127.0.0.1:8765/admin",
        alias="ADMIN_INVITE_REDIRECT_URL",
    )

    openai_api_key: str = Field(default="", alias="OPENAI_API_KEY")
    openai_model: str = Field(default="gpt-5.4-mini", alias="OPENAI_MODEL")

    flutter_command: str = Field(default="flutter", alias="FLUTTER_COMMAND")
    tflite_model_path: str = Field(
        default="../assets/models/plant_disease_efficientnetv2s.tflite",
        alias="TFLITE_MODEL_PATH",
    )
    tflite_labels_path: str = Field(
        default="../assets/models/plant_disease_efficientnetv2s_labels.txt",
        alias="TFLITE_LABELS_PATH",
    )

    whisper_model_size: str = Field(default="small", alias="WHISPER_MODEL_SIZE")
    whisper_model_device: str = Field(default="cpu", alias="WHISPER_MODEL_DEVICE")

    @property
    def parsed_cors_origins(self) -> list[str]:
        if self.cors_origins.strip() == "*":
            return ["*"]
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @property
    def cors_origin_regex(self) -> str | None:
        if self.app_env.lower() not in {"development", "test"}:
            return None
        return (
            r"https?://(?:localhost|127\.0\.0\.1|"
            r"192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|"
            r"172\.(?:1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3})(?::\d+)?"
        )

    @property
    def project_root(self) -> Path:
        return Path(__file__).resolve().parents[2]

    @property
    def workspace_root(self) -> Path:
        return self.project_root.parent

    @property
    def whisper_models_dir(self) -> Path:
        return self.project_root / "models" / "whisper"

    @property
    def resolved_tflite_model_path(self) -> Path:
        path = Path(self.tflite_model_path)
        if path.is_absolute():
            return path
        return (self.project_root / path).resolve()

    @property
    def resolved_tflite_labels_path(self) -> Path:
        path = Path(self.tflite_labels_path)
        if path.is_absolute():
            return path
        return (self.project_root / path).resolve()

    @property
    def tflite_helper_test_path(self) -> Path:
        return self.workspace_root / "test" / "backend_tflite_detect_test.dart"


@lru_cache
def get_settings() -> Settings:
    return Settings()
