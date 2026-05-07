from fastapi import APIRouter, Depends, File, Form, UploadFile

from app.core.dependencies import get_current_user, get_detect_service
from app.schemas.detect import DetectResponse
from app.schemas.user import AuthenticatedUser
from app.services.detect_service import DetectService

router = APIRouter()


@router.post("/detect", response_model=DetectResponse)
async def detect(
    image: UploadFile = File(...),
    crop_type: str | None = Form(default=None),
    current_user: AuthenticatedUser = Depends(get_current_user),
    detect_service: DetectService = Depends(get_detect_service),
) -> DetectResponse:
    image_bytes = await image.read()
    return await detect_service.detect_image(
        image_bytes=image_bytes,
        filename=image.filename or "upload.jpg",
        crop_type=crop_type,
        requested_by=current_user,
    )