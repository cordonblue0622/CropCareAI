import asyncio
import json
import sys
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from app.api import progress
from app.api.progress import _assess, _normalize_crop
from app.schemas.progress import ProgressCheckInRequest


def payload(**changes):
    return ProgressCheckInRequest(**dict(dict(
        crop_type='eggplant', disease_name='leaf spot', current_health_score=55,
        image_data_url='data:image/jpeg;base64,abc',
    ), **changes))


def install_client(monkeypatch, *, result=None, error=None, wait=False):
    calls = []
    class Client:
        def __init__(self, **kwargs):
            calls.append(kwargs)
            self.responses = self
        async def __aenter__(self):
            return self
        async def __aexit__(self, *_args):
            calls.append('closed')
        async def create(self, **kwargs):
            calls.append(kwargs)
            if wait:
                await asyncio.sleep(10)
            if error:
                raise error
            return SimpleNamespace(output_text=result if isinstance(result, str) else json.dumps(result))
    monkeypatch.setitem(sys.modules, 'openai', SimpleNamespace(AsyncOpenAI=Client))
    return calls


def result(**changes):
    return dict(dict(accepted=True, observed_crop='eggplant', health_score=65,
                     progress_status='improving', assessment='New healthy growth.',
                     next_steps=['Continue care']), **changes)


def test_unavailable_ai_is_not_accepted():
    with pytest.raises(HTTPException) as exc:
        asyncio.run(_assess(payload(), None, 'unused'))
    assert exc.value.status_code == 503


def test_missing_current_photo_is_not_sent_for_validation():
    with pytest.raises(HTTPException) as exc:
        asyncio.run(_assess(payload(image_data_url=None), 'test', 'unused'))
    assert exc.value.status_code == 422


def test_crop_aliases_normalize_to_the_tracked_crop():
    assert _normalize_crop('Bell Pepper') == 'pepper'
    assert _normalize_crop('bok choy') == 'pechay'


@pytest.mark.parametrize('observed', ['tomato', 'unknown'])
def test_mismatch_or_unclear_preserves_score(monkeypatch, observed):
    install_client(monkeypatch, result=result(observed_crop=observed))
    response = asyncio.run(_assess(payload(current_health_score=0), 'test', 'unused'))
    assert response.accepted is False
    assert response.health_score == 0
    assert response.progress_status == 'stable'
    assert response.next_steps == []
    assert response.rejection_reason


def test_valid_proof_uses_one_request_with_both_images_and_context(monkeypatch):
    calls = install_client(monkeypatch, result=result())
    response = asyncio.run(_assess(payload(previous_image_reference='https://example.test/old.jpg',
                                          completed_tasks=['Water'], previous_assessment='Old spots'), 'test', 'unused'))
    assert response.accepted is True
    assert response.health_score == 65
    assert calls[0]['max_retries'] == 0
    assert calls[0]['timeout'] == 60
    assert len(calls) == 3
    content = calls[1]['input'][1]['content']
    assert len([part for part in content if part['type'] == 'input_image']) == 2
    assert 'Old spots' in content[0]['text']
    assert 'Water' in content[0]['text']
    assert calls[-1] == 'closed'


@pytest.mark.parametrize('raw', ['not json', '{}', result(accepted='false'),
                                     result(health_score=float('nan')), result(progress_status='invalid')])
def test_invalid_ai_response_never_accepted(monkeypatch, raw):
    install_client(monkeypatch, result=raw)
    with pytest.raises(HTTPException) as exc:
        asyncio.run(_assess(payload(), 'test', 'unused'))
    assert exc.value.status_code == 502


def test_api_failure_is_not_acceptance(monkeypatch):
    install_client(monkeypatch, error=RuntimeError('unavailable'))
    with pytest.raises(HTTPException) as exc:
        asyncio.run(_assess(payload(), 'test', 'unused'))
    assert exc.value.status_code == 502


def test_rejected_identifiable_photo_has_clear_feedback_when_reason_is_null(monkeypatch):
    install_client(monkeypatch, result=result(accepted=False, rejection_reason=None))
    response = asyncio.run(_assess(payload(), 'test', 'unused'))
    assert not response.accepted
    assert 'clear photo' in response.rejection_reason
    assert response.next_steps == []
    assert response.health_score == 55


def test_timeout_cancels_request_and_releases_client(monkeypatch):
    calls = install_client(monkeypatch, wait=True)
    monkeypatch.setattr(progress, 'PROGRESS_TIMEOUT_SECONDS', 0.01)
    with pytest.raises(HTTPException) as exc:
        asyncio.run(_assess(payload(), 'test', 'unused'))
    assert exc.value.status_code == 504
    assert calls[-1] == 'closed'
