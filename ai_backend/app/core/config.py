from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=(".env", ".env.example"),
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

    supabase_url: str = Field(default="", alias="SUPABASE_URL")
    supabase_anon_key: str = Field(default="", alias="SUPABASE_ANON_KEY")
    supabase_service_role_key: str = Field(
        default="",
        alias="SUPABASE_SERVICE_ROLE_KEY",
    )

    openai_api_key: str = Field(default="", alias="OPENAI_API_KEY")
    openai_model: str = Field(default="gpt-5.4-mini", alias="OPENAI_MODEL")

    flutter_command: str = Field(default="flutter", alias="FLUTTER_COMMAND")
    tflite_model_path: str = Field(
        default="../assets/models/cropcare_efficientnet_v2.tflite",
        alias="TFLITE_MODEL_PATH",
    )
    tflite_labels_path: str = Field(
        default="../assets/models/labels_v2.txt",
        alias="TFLITE_LABELS_PATH",
    )

    yolo_model_path: str = Field(default="models/yolo/best.pt", alias="YOLO_MODEL_PATH")
    whisper_model_size: str = Field(default="small", alias="WHISPER_MODEL_SIZE")
    whisper_model_device: str = Field(default="cpu", alias="WHISPER_MODEL_DEVICE")

    @property
    def parsed_cors_origins(self) -> list[str]:
        if self.cors_origins.strip() == "*":
            return ["*"]
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

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
