from fastapi import APIRouter, Depends, UploadFile, File, HTTPException, status
from sqlalchemy.orm import Session
from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.services.csv_import_service import CSVImportService
from app.core.auth import verify_admin_key

MAX_UPLOAD_SIZE = 10 * 1024 * 1024  # 10 MB

router = APIRouter(
    prefix="/admin/import",
    tags=["Admin Import"],
    dependencies=[Depends(verify_admin_key)]
)

async def _read_file_with_limit(file: UploadFile) -> bytes:
    if file.content_type and file.content_type not in ("text/csv", "application/octet-stream"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid file type: {file.content_type}. Expected text/csv."
        )
    content = await file.read()
    if len(content) > MAX_UPLOAD_SIZE:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"File too large. Maximum size is {MAX_UPLOAD_SIZE // (1024*1024)} MB."
        )
    return content

@router.post("/stocks", response_model=ApiResponse[int], status_code=status.HTTP_201_CREATED)
async def import_stocks(file: UploadFile = File(...), db: Session = Depends(get_db)):
    try:
        content = await _read_file_with_limit(file)
        count = CSVImportService.import_stocks(content, db)
        return ApiResponse(success=True, data=count)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Import failed: {str(e)}"
        )

@router.post("/stock-daily-prices", response_model=ApiResponse[int], status_code=status.HTTP_201_CREATED)
async def import_stock_daily_prices(file: UploadFile = File(...), db: Session = Depends(get_db)):
    try:
        content = await _read_file_with_limit(file)
        count = CSVImportService.import_daily_prices(content, db)
        return ApiResponse(success=True, data=count)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Import failed: {str(e)}"
        )

@router.post("/market", response_model=ApiResponse[int], status_code=status.HTTP_201_CREATED)
async def import_market(file: UploadFile = File(...), db: Session = Depends(get_db)):
    try:
        content = await _read_file_with_limit(file)
        count = CSVImportService.import_market_index(content, db)
        return ApiResponse(success=True, data=count)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Import failed: {str(e)}"
        )
