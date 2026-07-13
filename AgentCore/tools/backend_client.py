"""呼叫 StockMood 後端的共用 helper。stdlib-only,Lambda 免打包依賴。"""
import json
import os
import urllib.request

TIMEOUT_SECONDS = 5


def get_json(path: str, user_id: str) -> dict:
    base_url = os.environ["BACKEND_BASE_URL"].rstrip("/")
    req = urllib.request.Request(
        f"{base_url}{path}",
        headers={"X-User-Id": user_id, "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=TIMEOUT_SECONDS) as resp:
        return json.loads(resp.read().decode())


UNAVAILABLE_MSG = "資料暫時取不到,請先以既有的基本數字說明,不要編造數值。"


def call_backend_tool(path: str, event: dict) -> dict:
    user_id = (event or {}).get("user_id", "").strip()
    if not user_id:
        return {"error": "缺少 user_id 參數。"}
    try:
        body = get_json(path, user_id)
    except Exception:  # noqa: BLE001 — 對 agent 一律回結構化錯誤,不讓 Lambda 炸掉
        return {"error": UNAVAILABLE_MSG}
    if not body.get("success"):
        return {"error": UNAVAILABLE_MSG}
    return body.get("data", {})
