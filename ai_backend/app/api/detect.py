from fastapi import APIRouter, Depends, File, Form, UploadFile

from app.core.dependencies import get_current_user, get_yolo_service
from app.schemas.detect import DetectResponse
from app.schemas.user import AuthenticatedUser
from app.services.yolo_service import YoloService

router = APIRouter()


@router.post("/detect", response_model=DetectResponse)
async def detect(
    image: UploadFile = File(...),
    crop_type: str | None = Form(default=None),
    current_user: AuthenticatedUser = Depends(get_current_user),
    yolo_service: YoloService = Depends(get_yolo_service),
) -> DetectResponse:
    image_bytes = await image.read()
    return await yolo_service.detect_image(
        image_bytes=image_bytes,
        filename=image.filename or "upload.jpg",
        crop_type=crop_type,
        requested_by=current_user,
    )