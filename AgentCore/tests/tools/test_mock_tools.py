import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))


def test_news_returns_one_item_per_symbol():
    from get_latest_news import handler
    result = handler({"symbols": ["2330", "2317"]}, None)
    assert result["is_mock"] is True
    assert [n["symbol"] for n in result["news"]] == ["2330", "2317"]
    assert all(n["headline"] for n in result["news"])


def test_news_empty_symbols():
    from get_latest_news import handler
    assert handler({"symbols": []}, None)["news"] == []


def test_chip_data_shape():
    from get_chip_data import handler
    result = handler({"symbols": ["2330"]}, None)
    assert result["is_mock"] is True
    item = result["chips"][0]
    assert item["symbol"] == "2330"
    assert set(item) >= {"symbol", "foreign_net_buy_lots", "trust_net_buy_lots", "note"}
