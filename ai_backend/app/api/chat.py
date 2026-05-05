from fastapi import APIRouter, Depends

from app.core.dependencies import (
    get_current_user,
    get_knowledge_service,
    get_llm_service,
)
from app.schemas.chat import ChatRequest, ChatResponse
from app.schemas.user import AuthenticatedUser
from app.services.knowledge_service import KnowledgeService
from app.services.llm_service import LlmService

router = APIRouter()


@router.post("/chat", response_model=ChatResponse)
async def chat(
    payload: ChatRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
    knowledge_service: KnowledgeService = Depends(get_knowledge_service),
    llm_service: LlmService = Depends(get_llm_service),
) -> ChatResponse:
    knowledge_records = await knowledge_service.fetch_relevant_records(payload)
    return await llm_service.generate_response(
        payload=payload,
        current_user=current_user,
        knowledge_records=knowledge_records,
    )