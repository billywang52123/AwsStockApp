"""Gateway tool(mock):固定法人買賣超樣板。真資料(主辦方籌碼資料)到位後只換本檔。"""


def handler(event, context):
    symbols = (event or {}).get("symbols") or []
    chips = [
        {
            "symbol": s,
            "foreign_net_buy_lots": 0,
            "trust_net_buy_lots": 0,
            "note": "示意資料:近五日法人進出接近中性,無明顯方向。",
        }
        for s in symbols
    ]
    return {"is_mock": True, "chips": chips}
