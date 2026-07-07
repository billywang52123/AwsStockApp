import pytest
from app.services.openai_service import OpenAIService
from app.services.services import run_async

def test_fallback_stock_analysis():
    # Test fallback formatting
    text = OpenAIService._generate_fallback_analysis("2330", "台積電", 920.0, -3.5)
    assert "【發生什麼】" in text
    assert "【跟你有關】" in text
    assert "【可以留意】" in text
    assert "台積電" in text

def test_fallback_card_draw():
    # Test fallback card mapping
    card = OpenAIService._generate_fallback_card(-1.0, "台積電", -4.0, -0.5)
    assert card["card_type"] == "STOCK_EVENT"
    assert card["title"] == "個股事件卡"
    assert "台積電" in card["message"]
    
    card_calm = OpenAIService._generate_fallback_card(0.2, "台積電", 0.5, 0.1)
    assert card_calm["card_type"] == "CALM_OBSERVE"
    assert card_calm["title"] == "冷靜觀察卡"

def test_run_async_wrapper():
    async def hello():
        return "world"
    res = run_async(hello())
    assert res == "world"
