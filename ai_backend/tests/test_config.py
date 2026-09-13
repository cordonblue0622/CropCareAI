from app.core.config import Settings


def test_normalizes_gpt_5_6_luna_display_name() -> None:
    settings = Settings(OPENAI_MODEL="gpt-5.6 Luna")

    assert settings.openai_model == "gpt-5.6-luna"