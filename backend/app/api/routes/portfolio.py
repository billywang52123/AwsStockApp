from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.schemas.portfolio_schema import PortfolioItemRead, PortfolioItemCreate
from app.services.services import PortfolioService

router = APIRouter(prefix="/portfolio", tags=["Portfolio"])

@router.get("/items", response_model=ApiResponse[list[PortfolioItemRead]])
def get_portfolio_items(db: Session = Depends(get_db)):
    service = PortfolioService(db)
    items = service.get_items()
    return ApiResponse(success=True, data=items)

@router.post("/items", response_model=ApiResponse[PortfolioItemRead], status_code=status.HTTP_201_CREATED)
def add_portfolio_item(item: PortfolioItemCreate, db: Session = Depends(get_db)):
    service = PortfolioService(db)
    saved = service.add_item(item.symbol, item.cost_price, item.shares)
    db.commit()
    return ApiResponse(success=True, data=saved)

@router.delete("/items/{item_id}", response_model=ApiResponse[bool])
def delete_portfolio_item(item_id: str, db: Session = Depends(get_db)):
    service = PortfolioService(db)
    success = service.delete_item(item_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Portfolio item not found"
        )
    db.commit()
    return ApiResponse(success=True, data=True)
