from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.core.auth import get_current_user_id
from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.schemas.portfolio_schema import PortfolioItemRead, PortfolioItemCreate, PortfolioItemUpdate
from app.services.services import PortfolioService

router = APIRouter(prefix="/portfolio", tags=["Portfolio"])

@router.get("/items", response_model=ApiResponse[list[PortfolioItemRead]])
def get_portfolio_items(db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    service = PortfolioService(db)
    items = service.get_items(user_id)
    return ApiResponse(success=True, data=items)

@router.post("/items", response_model=ApiResponse[PortfolioItemRead], status_code=status.HTTP_201_CREATED)
def add_portfolio_item(item: PortfolioItemCreate, db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    service = PortfolioService(db)
    saved = service.add_item(item.symbol, item.cost_price, item.shares, broker=item.broker, user_id=user_id)
    db.commit()

    from app.services.services import AchievementService
    AchievementService(db).trigger_unlock("IMPORT_MANUAL", user_id)

    return ApiResponse(success=True, data=saved)

@router.patch("/items/{item_id}", response_model=ApiResponse[PortfolioItemRead])
def update_portfolio_item(item_id: str, item: PortfolioItemUpdate, db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    service = PortfolioService(db)
    updated = service.update_item(
        item_id, user_id,
        broker=item.broker, cost_price=item.cost_price, shares=item.shares,
    )
    if updated is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Portfolio item not found"
        )
    db.commit()
    return ApiResponse(success=True, data=updated)

@router.delete("/items/{item_id}", response_model=ApiResponse[bool])
def delete_portfolio_item(item_id: str, db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    service = PortfolioService(db)
    success = service.delete_item(item_id, user_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Portfolio item not found"
        )
    db.commit()
    return ApiResponse(success=True, data=True)
