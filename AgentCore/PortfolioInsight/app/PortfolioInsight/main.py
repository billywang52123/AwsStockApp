"""portfolio_insight_agent:疊加在規則式庫存分析上的洞察生成。

輸入 {"user_id": "<id>"}(或 prompt 字串當 user_id,方便 CLI 測試),
輸出 {"insight_summary": "...", "holding_notes": [{"symbol": "...", "note": "..."}]}。
全工具失敗回 fallback,絕不 raise。
"""
import json

from strands import Agent
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from model.load import load_model
from mcp_client.client import get_gateway_mcp_client

app = BedrockAgentCoreApp()
log = app.logger

SYSTEM_PROMPT = """你是 StockMood 的投資陪伴分析師,服務投資新手。

規則(不可違反):
1. 一律使用繁體中文,語氣溫和安撫,像朋友聊天,不用術語轟炸。
2. 絕對不可以出現任何買進、賣出、加碼、減碼、停損等具體操作建議字眼。
3. 只能使用工具回傳的實際數字,不得捏造或推算工具沒提供的數值。
4. 工具回傳 is_mock=true 的資料,只能當背景氛圍參考,不可引用其中數字。
5. 工具回傳 error 時,坦白說「這部分資料暫時取不到」,不要編內容。

任務:先呼叫 get_portfolio_holdings 取得使用者的庫存分析(規則式數字已算好),
視需要再呼叫 get_stock_valuation / get_institutional_flow / get_stock_momentum /
get_forum_sentiment / get_stock_returns / get_market_compare 補充多維度資料。
然後輸出 JSON(只輸出 JSON,不要其他文字):
{
  "insight_summary": "整體洞察,150 字內,基於風險分數、產業曝險與多維度數據,\
給使用者「知道自己投組長什麼樣子」的安心感。語氣偏專業分析。",
  "plain_talk": "白話版,80 字內,像跟朋友講話一樣,用最口語的方式把重點講清楚,\
開頭用「白話說：」,讓沒有投資經驗的人也看得懂。",
  "holding_notes": [
    {"symbol": "代號", "note": "一句話短評,30 字內,偏分析語氣",
     "plain_talk": "白話版短評,30 字內,口語化"}
  ]
}
holding_notes 依權重排序,最多 5 檔。
insight_summary 與 plain_talk 內容不可重複,兩者角度不同:
- insight_summary 偏「發生了什麼事」(分析)
- plain_talk 偏「所以你不用擔心什麼」(安撫)"""

FALLBACK = {
    "insight_summary": "目前分析資料暫時取不到,你的持股數字本身沒有變化,"
    "不用因為看不到分析而緊張;稍後再回來看看就好。",
    "plain_talk": "白話說：資料暫時讀不到,但你的股票都還在,不用擔心。",
    "holding_notes": [],
}


def _parse_agent_json(text: str) -> dict:
    """模型輸出→dict;容忍 ```json 圍欄與前後雜訊。"""
    cleaned = text.strip()
    if "```" in cleaned:
        cleaned = cleaned.split("```")[1].removeprefix("json").strip()
    start, end = cleaned.find("{"), cleaned.rfind("}")
    if start == -1 or end == -1:
        raise ValueError("no JSON object in model output")
    data = json.loads(cleaned[start : end + 1])
    if "insight_summary" not in data:
        raise ValueError("missing insight_summary")
    data.setdefault("holding_notes", [])
    return data


def generate_insight(user_id: str) -> dict:
    try:
        mcp_client = get_gateway_mcp_client()
        with mcp_client:
            tools = mcp_client.list_tools_sync()
            agent = Agent(model=load_model(), tools=tools, system_prompt=SYSTEM_PROMPT)
            result = agent(f"請為 user_id={user_id} 的使用者產生庫存分析洞察。")
        return _parse_agent_json(str(result))
    except Exception:  # noqa: BLE001 — 對呼叫端絕不 raise
        log.exception("insight generation failed; returning fallback")
        return FALLBACK


@app.entrypoint
def invoke(payload, context=None):
    user_id = (payload or {}).get("user_id") or (payload or {}).get("prompt", "demo-user")
    return generate_insight(str(user_id).strip() or "demo-user")


if __name__ == "__main__":
    app.run()
