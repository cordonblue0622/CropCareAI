from functools import lru_cache
from typing import Any

from fastapi import APIRouter, Depends, Query, Response, status

from app.core.config import get_settings
from app.core.dependencies import require_admin_user, require_superadmin_user
from app.schemas.user import AuthenticatedUser
from app.services.admin_service import AdminService, RESOURCES

router = APIRouter(prefix="/admin")


@lru_cache
def get_admin_service() -> AdminService:
    return AdminService(get_settings())


@router.get("/me")
async def admin_identity(
    admin: AuthenticatedUser = Depends(require_admin_user),
) -> dict[str, Any]:
    return {"id": admin.id, "email": admin.email, "role": admin.role}


@router.get("/summary")
async def admin_summary(
    _: AuthenticatedUser = Depends(require_admin_user),
    service: AdminService = Depends(get_admin_service),
) -> dict[str, Any]:
    return await service.summary()


@router.get("/analytics")
async def admin_analytics(
    _: AuthenticatedUser = Depends(require_admin_user),
    service: AdminService = Depends(get_admin_service),
) -> dict[str, Any]:
    return await service.analytics()


@router.get("/crops/{crop_id}/activity")
async def crop_activity(
    crop_id: str,
    _: AuthenticatedUser = Depends(require_admin_user),
    service: AdminService = Depends(get_admin_service),
) -> dict[str, Any]:
    return await service.crop_activity(crop_id)


@router.get("/announcements")
async def list_announcements(
    admin: AuthenticatedUser = Depends(require_admin_user),
    service: AdminService = Depends(get_admin_service),
) -> dict[str, Any]:
    return {"items": await service.list_announcements(admin)}


@router.post("/announcements", status_code=status.HTTP_201_CREATED)
async def create_announcement(
    payload: dict[str, Any],
    admin: AuthenticatedUser = Depends(require_admin_user),
    service: AdminService = Depends(get_admin_service),
) -> dict[str, Any]:
    return await service.create_announcement(payload, admin)


@router.put("/announcements/{announcement_id}/like")
async def set_announcement_like(
    announcement_id: str,
    payload: dict[str, Any],
    admin: AuthenticatedUser = Depends(require_admin_user),
    service: AdminService = Depends(get_admin_service),
) -> dict[str, Any]:
    return await service.set_announcement_like(announcement_id, payload, admin)


@router.post("/announcements/{announcement_id}/replies", status_code=status.HTTP_201_CREATED)
async def create_announcement_reply(
    announcement_id: str,
    payload: dict[str, Any],
    admin: AuthenticatedUser = Depends(require_admin_user),
    service: AdminService = Depends(get_admin_service),
) -> dict[str, Any]:
    return await service.create_announcement_reply(announcement_id, payload, admin)


@router.get("/resources")
async def resource_catalog(
    _: AuthenticatedUser = Depends(require_admin_user),
) -> dict[str, Any]:
    return {
        name: {
            "fields": resource.fields,
            "editable": resource.editable,
            "required": resource.required,
            "can_create": resource.can_create,
        }
        for name, resource in RESOURCES.items()
    }


@router.get("/resources/{resource_name}")
async def list_resource(
    resource_name: str,
    query: str = Query(default="", max_length=80),
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    _: AuthenticatedUser = Depends(require_admin_user),
    service: AdminService = Depends(get_admin_service),
) -> dict[str, Any]:
    rows = await service.list_resource(
        resource_name,
        query=query,
        limit=limit,
        offset=offset,
    )
    return {"items": rows, "limit": limit, "offset": offset}


@router.post("/resources/{resource_name}", status_code=status.HTTP_201_CREATED)
async def create_resource(
    resource_name: str,
    payload: dict[str, Any],
    admin: AuthenticatedUser = Depends(require_admin_user),
    service: AdminService = Depends(get_admin_service),
) -> dict[str, Any]:
    return await service.create_resource(resource_name, payload, admin)


@router.patch("/resources/{resource_name}/{record_id}")
async def update_resource(
    resource_name: str,
    record_id: str,
    payload: dict[str, Any],
    admin: AuthenticatedUser = Depends(require_admin_user),
    service: AdminService = Depends(get_admin_service),
) -> dict[str, Any]:
    return await service.update_resource(resource_name, record_id, payload, admin)


@router.delete(
    "/resources/{resource_name}/{record_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def archive_resource(
    resource_name: str,
    record_id: str,
    admin: AuthenticatedUser = Depends(require_admin_user),
    service: AdminService = Depends(get_admin_service),
) -> Response:
    await service.archive_resource(resource_name, record_id, admin)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/users")
async def list_users(
    page: int = Query(default=1, ge=1),
    per_page: int = Query(default=50, ge=1, le=100),
    _: AuthenticatedUser = Depends(require_admin_user),
    service: AdminService = Depends(get_admin_service),
) -> dict[str, Any]:
    return {"items": await service.list_users(page=page, per_page=per_page)}


@router.post("/users/invite", status_code=status.HTTP_201_CREATED)
async def invite_user(
    payload: dict[str, Any],
    admin: AuthenticatedUser = Depends(require_admin_user),
    service: AdminService = Depends(get_admin_service),
) -> dict[str, Any]:
    return await service.invite_user(payload, admin)


@router.patch("/users/{user_id}/suspension", status_code=status.HTTP_204_NO_CONTENT)
async def set_user_suspension(
    user_id: str,
    payload: dict[str, Any],
    admin: AuthenticatedUser = Depends(require_admin_user),
    service: AdminService = Depends(get_admin_service),
) -> Response:
    await service.set_user_suspension(
        user_id,
        suspended=payload.get("suspended") is True,
        actor=admin,
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.patch("/users/{user_id}/admin-role", status_code=status.HTTP_204_NO_CONTENT)
async def set_user_admin_role(
    user_id: str,
    payload: dict[str, Any],
    superadmin: AuthenticatedUser = Depends(require_superadmin_user),
    service: AdminService = Depends(get_admin_service),
) -> Response:
    await service.set_user_admin_role(
        user_id,
        approved=payload.get("approved") is True,
        actor=superadmin,
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.patch("/users/{user_id}/profile")
async def update_user_profile(
    user_id: str,
    payload: dict[str, Any],
    admin: AuthenticatedUser = Depends(require_admin_user),
    service: AdminService = Depends(get_admin_service),
) -> dict[str, Any]:
    return await service.update_user_profile(user_id, payload, admin)


@router.post("/users/{user_id}/password-reset", status_code=status.HTTP_204_NO_CONTENT)
async def send_user_password_reset(
    user_id: str,
    admin: AuthenticatedUser = Depends(require_admin_user),
    service: AdminService = Depends(get_admin_service),
) -> Response:
    await service.send_password_reset(user_id, admin)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/treatment-protocols")
async def list_treatment_protocols(
    _: AuthenticatedUser = Depends(require_admin_user),
    service: AdminService = Depends(get_admin_service),
) -> dict[str, Any]:
    return {"items": await service.list_treatment_protocols()}


@router.put("/treatment-protocols/{disease_id}")
async def save_treatment_protocol(
    disease_id: str,
    payload: dict[str, Any],
    admin: AuthenticatedUser = Depends(require_admin_user),
    service: AdminService = Depends(get_admin_service),
) -> dict[str, Any]:
    return await service.save_treatment_protocol(disease_id, payload, admin)


@router.get("/audit")
async def audit_events(
    limit: int = Query(default=50, ge=1, le=100),
    _: AuthenticatedUser = Depends(require_admin_user),
    service: AdminService = Depends(get_admin_service),
) -> dict[str, Any]:
    return {"items": await service.list_audit_events(limit=limit)}
