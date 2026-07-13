"""Gateway tool(mock):固定中性新聞樣板。真資料源到位後只換本檔內部實作。"""


def handler(event, context):
    symbols = (event or {}).get("symbols") or []
    news = [
        {
            "symbol": s,
            "headline": f"{s} 近期無重大個別消息,市場關注整體產業景氣與資金流向。",
            "sentiment": "neutral",
        }
        for s in symbols
    ]
    return {"is_mock": True, "news": news}
