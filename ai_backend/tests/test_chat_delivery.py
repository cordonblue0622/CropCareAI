import asyncio
import threading
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from app.core.config import Settings
from app.schemas.chat import ChatRequest
from app.schemas.user import AuthenticatedUser
from app.services.llm_service import LlmService


@pytest.mark.parametrize('count', [1, 3, 4, 6])
def test_every_image_reaches_model_in_order(monkeypatch, count):
    service = LlmService(Settings(OPENAI_API_KEY='test'))
    images = [f'data:image/jpeg;base64,image{index}' for index in range(count)]
    captured = {}

    def create(client, **kwargs):
        captured.update(kwargs)
        return SimpleNamespace(output_text='Photo observations'), False

    monkeypatch.setattr(service, '_create_response', create)
    asyncio.run(service.generate_response(
        ChatRequest(user_message='Compare these leaves', image_data_urls=images),
        AuthenticatedUser(id='test'), [],
    ))
    blocks = captured['user_content']
    assert [b['image_url'] for b in blocks if b['type'] == 'input_image'] == images
    if count > 1:
        assert any('Distinguish different symptoms' in b.get('text', '') for b in blocks)


def test_online_failure_is_an_http_error_not_offline_guidance(monkeypatch):
    service = LlmService(Settings(OPENAI_API_KEY='test'))

    def fail(*args, **kwargs):
        raise TimeoutError('upstream timeout')

    monkeypatch.setattr(service, '_create_response', fail)
    with pytest.raises(HTTPException) as failure:
        asyncio.run(service.generate_response(
            ChatRequest(user_message='Compare', image_data_urls=['image1', 'image2', 'image3']),
            AuthenticatedUser(id='test'), [],
        ))
    assert failure.value.status_code == 502
    assert 'retry' in failure.value.detail.lower()


def test_missing_key_is_service_unavailable():
    service = LlmService(Settings(OPENAI_API_KEY=''))
    with pytest.raises(HTTPException) as failure:
        asyncio.run(service.generate_response(
            ChatRequest(user_message='Compare', image_data_urls=['image']),
            AuthenticatedUser(id='test'), [],
        ))
    assert failure.value.status_code == 503


def test_model_call_does_not_block_event_loop(monkeypatch):
    service = LlmService(Settings(OPENAI_API_KEY='test'))
    event = threading.Event()

    def create(*args, **kwargs):
        assert event.wait(timeout=2), 'event loop blocked by model call'
        return SimpleNamespace(output_text='Photo observations'), False

    monkeypatch.setattr(service, '_create_response', create)

    async def run():
        task = asyncio.create_task(service.generate_response(
            ChatRequest(user_message='Compare', image_data_urls=['image']),
            AuthenticatedUser(id='test'), [],
        ))
        await asyncio.sleep(0.02)
        event.set()
        await task

    asyncio.run(run())
