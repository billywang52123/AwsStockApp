import pytest
from app.services.yahoo_finance_service import YahooFinanceService

def test_fetch_live_price_listed_stock():
    # TSMC (2330) is a listed TWSE stock
    data = YahooFinanceService.fetch_live_price("2330")
    assert data is not None
    assert "close_price" in data
    assert "change_percent" in data
    assert "volume" in data
    assert data["close_price"] > 0
    assert isinstance(data["change_percent"], (int, float))
    assert data["volume"] >= 0

def test_fetch_live_price_market_index():
    # TAIEX market index (^TWII)
    data = YahooFinanceService.fetch_live_price("TAIEX")
    assert data is not None
    assert "close_price" in data
    assert "change_percent" in data
    assert data["close_price"] > 0
    assert isinstance(data["change_percent"], (int, float))
