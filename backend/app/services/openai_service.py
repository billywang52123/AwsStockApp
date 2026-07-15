"""AI text generation service — now backed by AWS Bedrock (Claude Sonnet 4.5).

Public interface is unchanged: all 6 class methods retain the same signatures
so callers (stocks.py, fortune_service.py, daily_pack_service.py, cards.py)
continue to work without modification.

Migration notes:
- Replaced httpx calls to OpenAI with synchronous boto3 Bedrock Converse.
- All async methods now use ``run_in_threadpool`` internally to avoid blocking.
- OPENAI_API_KEY is no longer required; the service uses IAM-based auth via
  the ECS task role (or local AWS credentials for dev).
- Fallback behaviour is preserved: any Bedrock error → rule-based template.
"""

import json
import logging
from typing import Any, Dict, Optional

from starlette.concurrency import run_in_threadpool

from app.services.bedrock_llm_service import get_bedrock_llm

logger = logging.getLogger(__name__)


class OpenAIService:
    """AI service using Bedrock Claude Sonnet 4.5 (name kept for import compatibility)."""

    # ──────────────────────────────────────────────────────────────────────
    # Fallbacks (unchanged)
    # ──────────────────────────────────────────────────────────────────────

    @staticmethod
    def _normalize_analysis_format(text: str) -> str:
        """Ensure Bedrock output matches the format iOS expects:
        【發生什麼】\\n內容...\\n\\n【跟你有關】\\n內容...\\n\\n【可以留意】\\n內容...

        iOS splits on \\n\\n then looks for 【】 in each part.
        So each section must be: 【標題】\\n內容 (single newline after title),
        and sections separated by \\n\\n.
        """
        import re
        # Strip markdown artifacts
        text = re.sub(r'#{1,3}\s*', '', text)
        text = text.replace('**', '').replace('---', '').replace('```', '')

        sections = []
        markers = ['【發生什麼】', '【跟你有關】', '【可以留意】']

        for i, marker in enumerate(markers):
            start = text.find(marker)
            if start == -1:
                continue
            content_start = start + len(marker)
            # Find next marker or end
            next_start = len(text)
            for next_marker in markers[i + 1:]:
                pos = text.find(next_marker, content_start)
                if pos != -1:
                    next_start = min(next_start, pos)
                    break

            content = text[content_start:next_start].strip()
            # Remove internal double newlines to keep content as single block
            content = re.sub(r'\n{2,}', '\n', content)
            sections.append(f"{marker}\n{content}")

        if not sections:
            # If parsing failed, return raw text as fallback
            return text

        return "\n\n".join(sections)

    @staticmethod
    def _generate_fallback_analysis(symbol: str, name: str, close_price: float, change_percent: float) -> str:
        if change_percent >= 0:
            return (
                "【發生什麼】\n"
                f"今天 {name} ({symbol}) 走勢穩健，股價收在 ${close_price:.2f}，微幅上漲了 {change_percent:.2f}%。主要是大盤市場情緒偏暖，科技與金控板塊的買盤資金持續挹注，支撐了今天的股價走勢。\n\n"
                "【跟你有關】\n"
                "看著持股上漲，您的情緒今天應該比較安心。不過，新手投資人在上漲時，往往容易心癢癢、想立刻做點什麼。此時先深呼吸，按照當初設定的投資目標執行，不要讓一時的市場情緒替你做決定。\n\n"
                "【可以留意】\n"
                "短期可以留意成交量是否隨上漲同步放大，這是走勢是否具備延續性的重要指標。長期請持續關注公司的營收公佈與基本面獲利。今天可以保持冷靜，給自己倒杯咖啡，靜待股價回歸合理呼吸範圍。"
            )
        else:
            return (
                "【發生什麼】\n"
                f"今天 {name} ({symbol}) 走勢偏弱，股價拉回至 ${close_price:.2f}，下跌了 {abs(change_percent):.2f}%。今天的回檔主要受到整體市場板塊調節與短線獲利回吐影響，並非個股本身發生營運危機。\n\n"
                "【跟你有關】\n"
                "看著庫存損益出現紅字跌幅，心裡感到焦慮或緊張是極為正常的。請對自己說一句：這只是市場的日常波動，並不代表這家公司的長期價值歸零。在恐慌時最忌諱做倉促的決定，先關掉看盤 App，給情緒一點沉澱的時間。\n\n"
                "【可以留意】\n"
                "可以留意下方的重要支撐均線，以及即將發布的季報數據。若公司的長期產業競爭力沒有變，短期的非理性修正往往只是市場情緒的呼吸。今天就別看盤了，好好放鬆一下吧！"
            )

    @staticmethod
    def _generate_fallback_card(avg_change: float, worst_name: Optional[str], worst_change: float, market_change: float) -> Dict[str, Any]:
        if worst_change < -2.0 and worst_name:
            return {
                "card_type": "STOCK_EVENT",
                "title": "個股事件卡",
                "message": f"今天你持有的 {worst_name} 下跌了 {abs(worst_change):.2f}%，這可能對你的心情造成了較大的衝擊。我們一起把這個事件拆開來分析，不用慌張。",
                "action_text": "查看詳細分析",
                "motto": "不要因為一天的下跌，而否定你當初深思熟慮的決定。"
            }
        elif market_change < -1.5:
            return {
                "card_type": "MARKET_IMPACT",
                "title": "大盤影響卡",
                "message": f"今天大盤下跌了 {abs(market_change):.2f}%，整體市場賣壓沉重。請明白這不是你的持股出了問題，而是大環境在調整。",
                "action_text": "查看大盤波動",
                "motto": "大潮退去時，保持呼吸、留在場內，就是對好公司最大的信心。"
            }
        elif avg_change < 0:
            return {
                "card_type": "CONFIDENCE_RESTORE",
                "title": "信心恢復卡",
                "message": "今天雖然持股略有修正，但仍在合理呼吸範圍內。請相信好公司需要時間開花結果，我們一起沉著應對。",
                "action_text": "查看今日原因",
                "motto": "波動是市場的呼吸，用時間的複利去平息眼前的風浪。"
            }
        else:
            return {
                "card_type": "CALM_OBSERVE",
                "title": "冷靜觀察卡",
                "message": "今天你的持股整體表現平穩，市場波動較小。可以先用輕鬆的心情看懂市場變化，好好享受今天的生活。",
                "action_text": "查看今日原因",
                "motto": "最好的投資，往往是學會靜靜觀察並過好當下的生活。"
            }

    # ──────────────────────────────────────────────────────────────────────
    # 1. Stock Analysis
    # ──────────────────────────────────────────────────────────────────────

    @classmethod
    async def fetch_stock_analysis(
        cls, symbol: str, name: str, close_price: float, change_percent: float,
        user_context: str = "",
    ) -> str:
        system = "你是一個說繁體中文、溫暖體貼的個人股票投資情緒輔導分析助理。只輸出純文字分析,不輸出 JSON,不使用 markdown 語法。"
        user = (
            f"你是一位專業的股票心理輔導與分析專家。請針對 {symbol} (名稱: {name})，"
            f"今日收盤價為 {close_price:.2f}，漲跌幅為 {change_percent:+.2f}% 的表現，為股票新手生成一段溫暖、口語化的分析。\n"
            f"以下是後端依該使用者問卷與持股快照產生的個人化脈絡；只可用來調整解釋順序與深度：\n"
            f"{user_context or '尚無完整風格資料，使用中性教學語氣。'}\n\n"
            "輸出格式（嚴格遵守,不可更改格式）:\n"
            "【發生什麼】\n這裡寫第一段內容,說明今天個股走勢與市場因素\n\n"
            "【跟你有關】\n這裡寫第二段內容,心理角度分析持股人的心情與損益\n\n"
            "【可以留意】\n這裡寫第三段內容,新手可關注的指標\n\n"
            "格式規則：\n"
            "- 每個段落標題獨佔一行,用【】包住\n"
            "- 標題後面緊接一個換行符,然後直接接內容文字（標題與內容之間只有一個換行）\n"
            "- 段落與段落之間用兩個換行分隔\n"
            "- 內容文字中不可包含額外的空行\n"
            "- 禁止使用 markdown 語法（#、##、**、*、---、```）\n"
            "- 每段內容 80-150 字\n\n"
            "內容硬性限制：全程繁體中文；全文不得出現「建議」二字，也不得出現「買進、賣出、加碼、減碼、停損、停利、攤平、進場、出場、獲利了結」等任何引導用戶操作的字眼；"
            "可以描述市場現象（例如：賣壓較重、買盤動能強、量能萎縮），也可以談論焦慮分數與情緒安撫，但絕不告訴用戶該做什麼交易動作。"
        )
        try:
            llm = get_bedrock_llm()
            result = await run_in_threadpool(
                llm.converse, system=system, user=user, temperature=0.7, max_tokens=1024
            )
            logger.info("Generated stock analysis via Bedrock for %s", symbol)
            return cls._normalize_analysis_format(result)
        except Exception:
            logger.exception("Bedrock stock analysis failed for %s; using fallback", symbol)

        return cls._generate_fallback_analysis(symbol, name, close_price, change_percent)

    # ──────────────────────────────────────────────────────────────────────
    # 2. AI Stock Screen
    # ──────────────────────────────────────────────────────────────────────

    @classmethod
    async def fetch_stock_screen(cls, query: str) -> Optional[list]:
        system = (
            "你是一個專門輸出 JSON 格式、嚴謹的台股資料整理助手,只列真實存在的代號。"
            "只回傳單一 JSON 物件,不要有任何額外文字。"
        )
        user = (
            "你是台股資料整理助手。用戶想找符合以下條件的台股(上市/上櫃個股或 ETF):\n"
            f"「{query}」\n\n"
            "請列出最多 8 檔最符合條件的標的,生成以下 JSON:\n"
            "{\n"
            '  "items": [\n'
            '    {"symbol": "台股代號(純數字,例如 0056、00878、2412)", "name": "中文名稱", '
            '"reason": "40 字內說明它與條件的關聯(例如殖利率水準、配息頻率、產業屬性),只描述客觀特性"}\n'
            "  ]\n"
            "}\n"
            "硬性限制:全程繁體中文;只列你確定真實存在的台股代號,不確定的寧可不列;"
            "reason 不得出現「建議」二字,也不得出現「買進、賣出、加碼、減碼、停損、停利、攤平、進場、出場、獲利了結」等任何引導用戶操作的字眼;"
            "不得保證報酬或未來配息;若用戶的條件跟找股票無關,items 回傳空陣列。"
        )
        try:
            llm = get_bedrock_llm()
            result = await run_in_threadpool(
                llm.converse_json, system=system, user=user, temperature=0.3, max_tokens=1024
            )
            items = result.get("items")
            if isinstance(items, list):
                logger.info("Generated stock screen via Bedrock for query: %s", query)
                return items
        except Exception:
            logger.exception("Bedrock stock screen failed for query: %s", query)

        return None

    # ──────────────────────────────────────────────────────────────────────
    # 3. Card Draw Message
    # ──────────────────────────────────────────────────────────────────────

    @classmethod
    async def fetch_card_draw_message(
        cls,
        avg_change: float,
        worst_name: Optional[str],
        worst_change: float,
        market_change: float,
        holdings: Optional[list] = None,
    ) -> Dict[str, Any]:
        fallback_card = cls._generate_fallback_card(avg_change, worst_name, worst_change, market_change)

        holdings_lines = []
        for h in holdings or []:
            line = f"- {h['name']} ({h['symbol']})：今日 {h['change_percent']:+.2f}%"
            if h.get("shares"):
                line += f"，持有 {h['shares']} 股"
            holdings_lines.append(line)
        holdings_desc = "\n".join(holdings_lines) if holdings_lines else "（目前沒有持股資料）"

        system = (
            "你是一個專門輸出 JSON 格式、幽默風趣又暖心的投資情緒塔羅牌助手。"
            "只回傳單一 JSON 物件,不要有任何額外文字。"
        )
        user = (
            "你是一位幽默風趣、有梗又暖心的投資情緒陪伴塔羅牌大師。以下是用戶今天的持股實況：\n"
            f"{holdings_desc}\n"
            f"持股平均漲跌幅 {avg_change:+.2f}%；大盤（加權指數）{market_change:+.2f}%。\n\n"
            "請依今天的表現挑一張最適合的情緒陪伴牌（冷靜觀察卡、信心恢復卡、大盤影響卡、小心震盪卡、個股事件卡之一），並生成以下 JSON 格式：\n"
            "{\n"
            '  "card_type": "對應英文卡名 (STOCK_EVENT / MARKET_IMPACT / CONFIDENCE_RESTORE / CALM_OBSERVE / VOLATILITY_ALERT)",\n'
            '  "title": "對應繁體中文卡名",\n'
            '  "message": "牌面訊息（80-140 字繁體中文）：要幽默風趣、有趣有梗，可用生活化比喻或輕鬆吐槽市場，並具體點名他的持股與今日表現；語氣溫暖，絕不嘲笑用戶虧損，也不製造恐慌",\n'
            '  "action_text": "按鈕行為文字 (例如: 查看詳細分析 / 查看大盤波動)",\n'
            '  "motto": "今日心法（一句簡短、幽默又有力量的投資情緒陪伴格言）"\n'
            "}\n"
            "硬性限制：全程繁體中文；全文不得出現「建議」二字，也不得出現「買進、賣出、加碼、減碼、停損、停利、攤平、進場、出場、獲利了結」等任何引導用戶操作的字眼；"
            "可以描述市場現象（例如：賣壓較重、買盤動能強），但絕不告訴用戶該做什麼交易動作。"
        )
        try:
            llm = get_bedrock_llm()
            result = await run_in_threadpool(
                llm.converse_json, system=system, user=user, temperature=0.9, max_tokens=512
            )
            logger.info("Generated card message via Bedrock")
            return {
                "card_type": result.get("card_type", fallback_card["card_type"]),
                "title": result.get("title", fallback_card["title"]),
                "message": result.get("message", fallback_card["message"]),
                "action_text": result.get("action_text", fallback_card["action_text"]),
                "motto": result.get("motto", fallback_card["motto"]),
            }
        except Exception:
            logger.exception("Bedrock card message failed; using fallback")

        return fallback_card

    # ──────────────────────────────────────────────────────────────────────
    # 4. Fortune Text
    # ──────────────────────────────────────────────────────────────────────

    @classmethod
    async def fetch_fortune_text(
        cls,
        overall_level: str,
        avg_change: float,
        market_change: float,
        holdings: Optional[list] = None,
    ) -> Dict[str, Any]:
        holdings_lines = [
            f"- {h['name']} ({h['symbol']})：今日 {h['change_percent']:+.2f}%，產業 {h.get('industry', '其他')}"
            for h in holdings or []
        ]
        holdings_desc = "\n".join(holdings_lines) if holdings_lines else "（目前沒有持股資料）"

        system = (
            "你是一個專門輸出 JSON 格式、溫暖安撫的日式御神籤解籤助手。"
            "只回傳單一 JSON 物件,不要有任何額外文字。"
        )
        user = (
            "你是一位溫暖的日式御神籤解籤人,為投資新手寫今天的籤詩內容。用戶今天的狀況：\n"
            f"{holdings_desc}\n"
            f"持股平均漲跌 {avg_change:+.2f}%；大盤 {market_change:+.2f}%；"
            f"今日綜合籤等（已由系統判定,不可更改）：{overall_level}。\n\n"
            "請生成以下 JSON：\n"
            "{\n"
            '  "summary": "說明欄（60-100 字繁體中文）：描述今天可能發生的事與市場氛圍,語氣安撫、貼合籤等,可具體點名持股",\n'
            '  "notices": ["注意事項 1（30 字內,只能根據上面提供的實際資料描述,不可編造新聞或事件）", "注意事項 2", "注意事項 3"]\n'
            "}\n"
            "硬性限制：全程繁體中文；不得出現「建議」二字,也不得出現「買進、賣出、加碼、減碼、停損、停利、攤平、進場、出場、獲利了結」等任何引導操作的字眼；"
            "凶籤走安撫語氣,不製造恐慌;可描述市場現象,但不告訴用戶該做什麼交易動作。"
        )
        try:
            llm = get_bedrock_llm()
            result = await run_in_threadpool(
                llm.converse_json, system=system, user=user, temperature=0.8, max_tokens=512
            )
            logger.info("Generated fortune text via Bedrock")
            notices = result.get("notices")
            return {
                "summary": result.get("summary"),
                "notices": notices if isinstance(notices, list) else None,
            }
        except Exception:
            logger.exception("Bedrock fortune text failed; using fallback")

        return {}

    # ──────────────────────────────────────────────────────────────────────
    # 5. Companion Text
    # ──────────────────────────────────────────────────────────────────────

    @classmethod
    async def fetch_companion_text(
        cls,
        avg_change: float,
        market_change: float,
        holdings_count: int,
    ) -> Optional[str]:
        system = (
            "你是一個專門輸出 JSON、語氣溫暖的陪伴訊息助手。"
            "只回傳單一 JSON 物件,不要有任何額外文字。"
        )
        user = (
            "你是一位溫柔、不催促的 AI 陪伴者,為投資新手寫今天的陪伴訊息。\n"
            f"用戶今天的狀況:持股 {holdings_count} 檔,庫存加權 {avg_change:+.2f}%,大盤 {market_change:+.2f}%。\n\n"
            '請生成 JSON:{"text": "3-4 句繁體中文陪伴訊息(80-120 字),手寫信的語氣,安撫情緒"}\n'
            "硬性限制:不得提及任何個股名稱;不得預測漲跌;不得出現「建議」二字,"
            "也不得出現「買進、賣出、加碼、減碼、停損、停利、攤平、進場、出場、獲利了結」"
            "等任何引導操作的字眼;只安撫情緒,永遠不給操作方向。"
        )
        try:
            llm = get_bedrock_llm()
            result = await run_in_threadpool(
                llm.converse_json, system=system, user=user, temperature=0.9, max_tokens=256
            )
            text = result.get("text")
            if isinstance(text, str) and text.strip():
                logger.info("Generated companion text via Bedrock")
                return text.strip()
        except Exception:
            logger.exception("Bedrock companion text failed; using fallback")

        return None

    # ──────────────────────────────────────────────────────────────────────
    # 6. Pack AI Text
    # ──────────────────────────────────────────────────────────────────────

    @classmethod
    async def fetch_pack_ai_text(cls, metrics: Dict[str, Any]) -> Dict[str, Any]:
        holdings_lines = [
            f"- {h['name']} ({h['symbol']})：漲跌 {h['change_percent']:+.2f}%,"
            f"庫存占比 {h['weight_percent']:.1f}%,產業 {h.get('industry', '其他')}"
            for h in metrics.get("holdings") or []
        ]
        holdings_desc = "\n".join(holdings_lines) if holdings_lines else "（目前沒有持股）"
        community_line = metrics.get("community_heat_text") or "（無社群數據）"
        flash_line = metrics.get("flashcard_event") or "（今日無閃卡事件）"
        user_context = metrics.get("user_prompt_context") or "（尚無使用者投資風格資料,使用中性分析）"

        system = (
            "你是一個專門輸出 JSON、依提供數據措辭、語氣冷靜安撫的投資解讀助手。"
            "只回傳單一 JSON 物件,不要有任何額外文字。"
        )
        user = (
            "你是投資新手 App 的 AI 分析員。後端已用 CMoney 收盤資料算好以下數字,"
            "你只負責把它們寫成一句結論,不可自創任何數字或事件：\n"
            f"{holdings_desc}\n"
            f"庫存加權漲跌 {metrics.get('weighted_change', 0):+.2f}%；"
            f"大盤 {metrics.get('market_change', 0):+.2f}%。\n"
            f"社群(股票同學會)：{community_line}\n"
            f"閃卡事件：{flash_line}\n\n"
            f"以下是後端依問卷與持股快照產生的使用者脈絡,請只用來調整解釋順序與深度,"
            f"不可據此產生交易指令：\n{user_context}\n\n"
            "請生成 JSON：\n"
            "{\n"
            '  "conclusion": "推論卡結論句（40-70 字繁體中文）：對整體庫存的一句判斷,'
            "必須引用上面提供的實際數字,語氣冷靜、標明這是依數字推論\"\n"
            "}\n"
            "硬性限制：全程繁體中文；不得出現「建議」二字,也不得出現「買進、賣出、加碼、減碼、"
            "停損、停利、攤平、進場、出場、獲利了結、目標價」等任何引導操作的字眼；"
            "不預測明天漲跌;可描述現況,但不告訴用戶該做什麼交易動作。"
        )
        try:
            llm = get_bedrock_llm()
            result = await run_in_threadpool(
                llm.converse_json, system=system, user=user, temperature=0.7, max_tokens=256
            )
            logger.info("Generated pack AI text via Bedrock")
            return {"conclusion": result.get("conclusion")}
        except Exception:
            logger.exception("Bedrock pack AI text failed; using fallback")

        return {}
