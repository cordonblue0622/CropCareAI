from functools import lru_cache

from fastapi import APIRouter, Depends, Response, status

from app.core.config import get_settings
from app.core.dependencies import require_authenticated_user
from app.schemas.user import AuthenticatedUser
from app.services.account_service import AccountService

router = APIRouter(prefix="/account")


@lru_cache
def get_account_service() -> AccountService:
    return AccountService(get_settings())


@router.delete("", status_code=status.HTTP_204_NO_CONTENT)
async def delete_account(
    user: AuthenticatedUser = Depends(require_authenticated_user),
    service: AccountService = Depends(get_account_service),
) -> Response:
    await service.delete_account(user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)