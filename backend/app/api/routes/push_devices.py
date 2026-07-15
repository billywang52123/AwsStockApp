from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.auth import get_current_user_id
from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.schemas.push_device_schema import PushDeviceRead, PushDeviceRegister
from app.services.push_device_service import PushDeviceService

router = APIRouter(prefix="/push-devices", tags=["Push Devices"])


@router.post("", response_model=ApiResponse[PushDeviceRead])
def register_push_device(
    body: PushDeviceRegister,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    result = PushDeviceService(db).register(
        user_id=user_id,
        device_token=body.device_token,
        platform=body.platform,
        environment=body.environment,
    )
    db.commit()
    return ApiResponse(success=True, data=result)


@router.post("/test", response_model=ApiResponse[dict])
def send_test_push(
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """對自己的所有已註冊裝置發一則測試推播(設定頁診斷用)。"""
    sent = PushDeviceService(db).send_to_user(
        user_id,
        title="測試推播",
        body="推播鏈路正常，之後風格轉變等提醒會從這裡送達。",
        data={"type": "diagnostic"},
    )
    db.commit()
    return ApiResponse(success=True, data={"sent": sent})


@router.get("", response_model=ApiResponse[list[PushDeviceRead]])
def list_push_devices(
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    return ApiResponse(success=True, data=PushDeviceService(db).list_for_user(user_id))


@router.delete("/{device_id}", response_model=ApiResponse[bool])
def delete_push_device(
    device_id: str,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    if not PushDeviceService(db).delete(user_id=user_id, device_id=device_id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Push device not found"
        )
    db.commit()
    return ApiResponse(success=True, data=True)

