import csv
import io
import logging
import math
from datetime import datetime
from sqlalchemy.orm import Session
from sqlalchemy import select, and_
from app.models.stock import Stock
from app.models.stock_daily_price import StockDailyPrice
from app.models.market_index import MarketIndexDaily

logger = logging.getLogger(__name__)


def _finite_float(value: str, field: str) -> float:
    """float() 會接受 'nan'/'inf' 字串;匯入資料一律要求有限數值。"""
    result = float(value)
    if not math.isfinite(result):
        raise ValueError(f"{field} must be a finite number, got {value!r}")
    return result


class CSVImportService:
    @staticmethod
    def import_stocks(file_content: bytes, db: Session) -> int:
        try:
            text = file_content.decode("utf-8")
        except UnicodeDecodeError as e:
            raise ValueError(f"File is not valid UTF-8: {e}")
        
        reader = csv.DictReader(io.StringIO(text))
        count = 0
        for row_num, row in enumerate(reader, start=2):
            symbol = row.get("symbol", "").strip()
            name = row.get("name", "").strip()
            market = row.get("market", "TW").strip()
            industry = row.get("industry", "").strip()
            
            if not symbol or not name:
                logger.warning(f"Skipping row {row_num}: missing symbol or name")
                continue
                
            stmt = select(Stock).where(Stock.symbol == symbol)
            stock = db.scalars(stmt).first()
            if not stock:
                stock = Stock(symbol=symbol, name=name, market=market, industry=industry)
                db.add(stock)
            else:
                stock.name = name
                stock.market = market
                stock.industry = industry
            count += 1
        db.commit()
        return count

    @staticmethod
    def import_daily_prices(file_content: bytes, db: Session) -> int:
        try:
            text = file_content.decode("utf-8")
        except UnicodeDecodeError as e:
            raise ValueError(f"File is not valid UTF-8: {e}")
        
        reader = csv.DictReader(io.StringIO(text))
        count = 0
        errors = []
        for row_num, row in enumerate(reader, start=2):
            symbol = row.get("symbol", "").strip()
            trade_date_str = row.get("tradeDate", "").strip()
            close_price_val = row.get("closePrice", "").strip()
            change_percent_val = row.get("changePercent", "").strip()
            volume_val = row.get("volume", "").strip()
            
            if not symbol or not trade_date_str or not close_price_val:
                continue
            
            try:
                trade_date = datetime.strptime(trade_date_str, "%Y-%m-%d").date()
                close_price = _finite_float(close_price_val, "closePrice")
                change_percent = _finite_float(change_percent_val, "changePercent") if change_percent_val else 0.0
                volume = _finite_float(volume_val, "volume") if volume_val else None
            except (ValueError, TypeError) as e:
                errors.append(f"Row {row_num}: {e}")
                continue
                
            stmt = select(StockDailyPrice).where(
                and_(StockDailyPrice.symbol == symbol, StockDailyPrice.trade_date == trade_date)
            )
            price = db.scalars(stmt).first()
            if not price:
                price = StockDailyPrice(
                    symbol=symbol,
                    trade_date=trade_date,
                    close_price=close_price,
                    change_percent=change_percent,
                    volume=volume
                )
                db.add(price)
            else:
                price.close_price = close_price
                price.change_percent = change_percent
                price.volume = volume
            count += 1
        
        if errors:
            logger.warning(f"CSV import had {len(errors)} parse errors: {errors[:5]}")
        
        db.commit()
        return count

    @staticmethod
    def import_market_index(file_content: bytes, db: Session) -> int:
        try:
            text = file_content.decode("utf-8")
        except UnicodeDecodeError as e:
            raise ValueError(f"File is not valid UTF-8: {e}")
        
        reader = csv.DictReader(io.StringIO(text))
        count = 0
        errors = []
        for row_num, row in enumerate(reader, start=2):
            index_code = row.get("indexCode", "TAIEX").strip()
            trade_date_str = row.get("tradeDate", "").strip()
            close_price_val = row.get("closePrice", "").strip()
            change_percent_val = row.get("changePercent", "").strip()
            
            if not trade_date_str or not close_price_val:
                continue
            
            try:
                trade_date = datetime.strptime(trade_date_str, "%Y-%m-%d").date()
                close_price = _finite_float(close_price_val, "closePrice")
                change_percent = _finite_float(change_percent_val, "changePercent") if change_percent_val else 0.0
            except (ValueError, TypeError) as e:
                errors.append(f"Row {row_num}: {e}")
                continue
                
            stmt = select(MarketIndexDaily).where(
                and_(MarketIndexDaily.index_code == index_code, MarketIndexDaily.trade_date == trade_date)
            )
            idx = db.scalars(stmt).first()
            if not idx:
                idx = MarketIndexDaily(
                    index_code=index_code,
                    trade_date=trade_date,
                    close_price=close_price,
                    change_percent=change_percent
                )
                db.add(idx)
            else:
                idx.close_price = close_price
                idx.change_percent = change_percent
            count += 1
        
        if errors:
            logger.warning(f"CSV import had {len(errors)} parse errors: {errors[:5]}")
        
        db.commit()
        return count
