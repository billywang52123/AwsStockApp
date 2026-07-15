"""Gateway tool: 取得指定股票的法人動向(外資/投信/自營商買賣超、持股比率)。"""
from backend_client import get_json

UNAVAILABLE_MSG = "法人動向資料暫時取不到。"


def handler(event, context):
    symbols = (event or {}).get("symbols", [])
    if not symbols:
        return {"error": "缺少 symbols 參數。"}
    user_id = (event or {}).get("user_id", "demo-user")
    symbols_str = ",".join(symbols)
    try:
        body = get_json(f"/api/internal/institutional-flow?symbols={symbols_str}", user_id)
    except Exception:
        return {"error": UNAVAILABLE_MSG}
    if not body.get("success"):
        return {"error": UNAVAILABLE_MSG}
    return body.get("data", [])
