import httpx
import logging
from typing import Dict, Any, Optional
from app.core.config import settings

logger = logging.getLogger(__name__)

class OpenAIService:
    @staticmethod
    def _generate_fallback_analysis(symbol: str, name: str, close_price: float, change_percent: float) -> str:
        """Generates high-quality fallback stock analysis if GPT is offline."""
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
        """Generates high-quality fallback tarot card content if GPT is offline."""
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
                "message": f"今天雖然持股略有修正，但仍在合理呼吸範圍內。請相信好公司需要時間開花結果，我們一起沉著應對。",
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

    @classmethod
    async def fetch_stock_analysis(cls, symbol: str, name: str, close_price: float, change_percent: float) -> str:
        """Queries OpenAI completion to generate stock analysis, falling back to rule-based template if failing."""
        if not settings.OPENAI_API_KEY:
            logger.info("OPENAI_API_KEY is not set. Using rule-based fallback stock analysis.")
            return cls._generate_fallback_analysis(symbol, name, close_price, change_percent)
            
        prompt = (
            f"你是一位專業的股票心理輔導與分析專家。請針對 {symbol} (名稱: {name})，"
            f"今日收盤價為 {close_price:.2f}，漲跌幅為 {change_percent:+.2f}% 的表現，為股票新手生成一段溫暖、口語化且排版清晰的分析。\n"
            "分析必須包含以下三個段落（使用繁體中文）：\n"
            "1. 【發生什麼】：說明今天個股的大致走勢與可能的市場因素。\n"
            "2. 【跟你有關】：以對帳單與心理角度分析，持有這檔股票的人今天的心情與損益變動該如何看待。\n"
            "3. 【可以留意】：提供接下來新手可以關注的指標（如支撐點、長期營收等），強調不需要急著做任何交易決定。\n"
            "硬性限制：全程繁體中文；全文不得出現「建議」二字，也不得出現「買進、賣出、加碼、減碼、停損、停利、攤平、進場、出場、獲利了結」等任何引導用戶操作的字眼；"
            "可以描述市場現象（例如：賣壓較重、買盤動能強、量能萎縮），也可以談論焦慮分數與情緒安撫，但絕不告訴用戶該做什麼交易動作。"
        )
        
        try:
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    "https://api.openai.com/v1/chat/completions",
                    headers={
                        "Authorization": f"Bearer {settings.OPENAI_API_KEY}",
                        "Content-Type": "application/json"
                    },
                    json={
                        "model": "gpt-4o-mini",
                        "messages": [
                            {"role": "system", "content": "你是一個說繁體中文、溫暖體貼的個人股票投資情緒輔導分析助理。"},
                            {"role": "user", "content": prompt}
                        ],
                        "temperature": 0.7
                    },
                    timeout=5.0
                )
                
                if response.status_code == 200:
                    data = response.json()
                    analysis = data["choices"][0]["message"]["content"]
                    logger.info(f"Successfully generated stock analysis via GPT-4o-mini for {symbol}")
                    return analysis
                else:
                    logger.warning(f"OpenAI returned error code {response.status_code}: {response.text}")
        except Exception as e:
            logger.error(f"Failed to fetch stock analysis from OpenAI: {str(e)}")
            
        return cls._generate_fallback_analysis(symbol, name, close_price, change_percent)

    @classmethod
    async def fetch_stock_screen(cls, query: str) -> Optional[list]:
        """AI 找股(觀察清單加入股票用):自然語言條件 → 台股候選名單。

        回傳 [{"symbol", "name", "reason"}, ...];未設 key 或失敗回 None,
        由 StockService 退回主題式 fallback。GPT 給的代號一律要再經
        StockService 驗證(CMoney 模擬日有價格)才會回給前端,幻覺代號會被丟掉。"""
        if not settings.OPENAI_API_KEY:
            logger.info("OPENAI_API_KEY is not set. Using rule-based fallback stock screen.")
            return None

        prompt = (
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
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    "https://api.openai.com/v1/chat/completions",
                    headers={
                        "Authorization": f"Bearer {settings.OPENAI_API_KEY}",
                        "Content-Type": "application/json"
                    },
                    json={
                        "model": "gpt-4o-mini",
                        "messages": [
                            {"role": "system", "content": "你是一個專門輸出 JSON 格式、嚴謹的台股資料整理助手,只列真實存在的代號。"},
                            {"role": "user", "content": prompt}
                        ],
                        "response_format": {"type": "json_object"},
                        "temperature": 0.3
                    },
                    timeout=12.0
                )

                if response.status_code == 200:
                    data = response.json()
                    import json
                    result = json.loads(data["choices"][0]["message"]["content"])
                    items = result.get("items")
                    if isinstance(items, list):
                        logger.info(f"Successfully generated stock screen via GPT-4o-mini for query: {query}")
                        return items
                else:
                    logger.warning(f"OpenAI returned error code {response.status_code}: {response.text}")
        except Exception as e:
            logger.error(f"Failed to fetch stock screen from OpenAI: {str(e)}")

        return None

    @classmethod
    async def fetch_card_draw_message(
        cls,
        avg_change: float,
        worst_name: Optional[str],
        worst_change: float,
        market_change: float,
        holdings: Optional[list] = None,
    ) -> Dict[str, Any]:
        """Queries OpenAI to generate personalized card draw message and motto."""
        fallback_card = cls._generate_fallback_card(avg_change, worst_name, worst_change, market_change)

        if not settings.OPENAI_API_KEY:
            logger.info("OPENAI_API_KEY is not set. Using rule-based fallback card.")
            return fallback_card

        holdings_lines = []
        for h in holdings or []:
            line = f"- {h['name']} ({h['symbol']})：今日 {h['change_percent']:+.2f}%"
            if h.get("shares"):
                line += f"，持有 {h['shares']} 股"
            holdings_lines.append(line)
        holdings_desc = "\n".join(holdings_lines) if holdings_lines else "（目前沒有持股資料）"

        prompt = (
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
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    "https://api.openai.com/v1/chat/completions",
                    headers={
                        "Authorization": f"Bearer {settings.OPENAI_API_KEY}",
                        "Content-Type": "application/json"
                    },
                    json={
                        "model": "gpt-4o-mini",
                        "messages": [
                            {"role": "system", "content": "你是一個專門輸出 JSON 格式、幽默風趣又暖心的投資情緒塔羅牌助手。"},
                            {"role": "user", "content": prompt}
                        ],
                        "response_format": {"type": "json_object"},
                        "temperature": 0.9
                    },
                    timeout=5.0
                )
                
                if response.status_code == 200:
                    data = response.json()
                    import json
                    result = json.loads(data["choices"][0]["message"]["content"])
                    logger.info("Successfully generated personalized card message via GPT-4o-mini")
                    return {
                        "card_type": result.get("card_type", fallback_card["card_type"]),
                        "title": result.get("title", fallback_card["title"]),
                        "message": result.get("message", fallback_card["message"]),
                        "action_text": result.get("action_text", fallback_card["action_text"]),
                        "motto": result.get("motto", fallback_card["motto"])
                    }
                else:
                    logger.warning(f"OpenAI returned error code {response.status_code}: {response.text}")
        except Exception as e:
            logger.error(f"Failed to fetch card message from OpenAI: {str(e)}")

        return fallback_card

    @classmethod
    async def fetch_fortune_text(
        cls,
        overall_level: str,
        avg_change: float,
        market_change: float,
        holdings: Optional[list] = None,
    ) -> Dict[str, Any]:
        """御神籤「說明 / 注意事項」文字(12c)。籤等由後端規則決定,
        GPT 只補文字;離線或失敗時回空 dict,由 FortuneService 用規則式 fallback。"""
        if not settings.OPENAI_API_KEY:
            logger.info("OPENAI_API_KEY is not set. Using rule-based fortune text.")
            return {}

        holdings_lines = [
            f"- {h['name']} ({h['symbol']})：今日 {h['change_percent']:+.2f}%，產業 {h.get('industry', '其他')}"
            for h in holdings or []
        ]
        holdings_desc = "\n".join(holdings_lines) if holdings_lines else "（目前沒有持股資料）"

        prompt = (
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
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    "https://api.openai.com/v1/chat/completions",
                    headers={
                        "Authorization": f"Bearer {settings.OPENAI_API_KEY}",
                        "Content-Type": "application/json"
                    },
                    json={
                        "model": "gpt-4o-mini",
                        "messages": [
                            {"role": "system", "content": "你是一個專門輸出 JSON 格式、溫暖安撫的日式御神籤解籤助手。"},
                            {"role": "user", "content": prompt}
                        ],
                        "response_format": {"type": "json_object"},
                        "temperature": 0.8
                    },
                    timeout=5.0
                )

                if response.status_code == 200:
                    data = response.json()
                    import json
                    result = json.loads(data["choices"][0]["message"]["content"])
                    logger.info("Successfully generated fortune text via GPT-4o-mini")
                    notices = result.get("notices")
                    return {
                        "summary": result.get("summary"),
                        "notices": notices if isinstance(notices, list) else None,
                    }
                else:
                    logger.warning(f"OpenAI returned error code {response.status_code}: {response.text}")
        except Exception as e:
            logger.error(f"Failed to fetch fortune text from OpenAI: {str(e)}")

        return {}

    @classmethod
    async def fetch_companion_text(
        cls,
        avg_change: float,
        market_change: float,
        holdings_count: int,
    ) -> Optional[str]:
        """陪伴卡(15h)文字:3–4 句安撫,零買賣暗示。
        離線或失敗回 None,由 DailyPackService 用規則式 fallback。"""
        if not settings.OPENAI_API_KEY:
            logger.info("OPENAI_API_KEY is not set. Using rule-based companion text.")
            return None

        prompt = (
            "你是一位溫柔、不催促的 AI 陪伴者,為投資新手寫今天的陪伴訊息。\n"
            f"用戶今天的狀況:持股 {holdings_count} 檔,庫存加權 {avg_change:+.2f}%,大盤 {market_change:+.2f}%。\n\n"
            '請生成 JSON:{"text": "3-4 句繁體中文陪伴訊息(80-120 字),手寫信的語氣,安撫情緒"}\n'
            "硬性限制:不得提及任何個股名稱;不得預測漲跌;不得出現「建議」二字,"
            "也不得出現「買進、賣出、加碼、減碼、停損、停利、攤平、進場、出場、獲利了結」"
            "等任何引導操作的字眼;只安撫情緒,永遠不給操作方向。"
        )

        try:
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    "https://api.openai.com/v1/chat/completions",
                    headers={
                        "Authorization": f"Bearer {settings.OPENAI_API_KEY}",
                        "Content-Type": "application/json"
                    },
                    json={
                        "model": "gpt-4o-mini",
                        "messages": [
                            {"role": "system", "content": "你是一個專門輸出 JSON、語氣溫暖的陪伴訊息助手。"},
                            {"role": "user", "content": prompt}
                        ],
                        "response_format": {"type": "json_object"},
                        "temperature": 0.9
                    },
                    timeout=5.0
                )
                if response.status_code == 200:
                    data = response.json()
                    import json
                    result = json.loads(data["choices"][0]["message"]["content"])
                    text = result.get("text")
                    if isinstance(text, str) and text.strip():
                        logger.info("Successfully generated companion text via GPT-4o-mini")
                        return text.strip()
                else:
                    logger.warning(f"OpenAI returned error code {response.status_code}: {response.text}")
        except Exception as e:
            logger.error(f"Failed to fetch companion text from OpenAI: {str(e)}")

        return None

    @classmethod
    async def fetch_pack_ai_text(cls, metrics: Dict[str, Any]) -> Dict[str, Any]:
        """每日卡包(spec 06):後端把 CMoney 模擬日數據分析完,交給 AI 措辭。
        AI 只生成「推論卡結論句」與「陪伴卡訊息」,數字一律沿用輸入,不可自創。
        離線或失敗回空 dict,由 DailyPackService 用規則式 fallback。"""
        if not settings.OPENAI_API_KEY:
            logger.info("OPENAI_API_KEY is not set. Using rule-based pack text.")
            return {}

        holdings_lines = [
            f"- {h['name']} ({h['symbol']})：漲跌 {h['change_percent']:+.2f}%,"
            f"庫存占比 {h['weight_percent']:.1f}%,產業 {h.get('industry', '其他')}"
            for h in metrics.get("holdings") or []
        ]
        holdings_desc = "\n".join(holdings_lines) if holdings_lines else "（目前沒有持股）"
        community_line = metrics.get("community_heat_text") or "（無社群數據）"
        flash_line = metrics.get("flashcard_event") or "（今日無閃卡事件）"

        prompt = (
            "你是投資新手 App 的 AI 分析員。後端已用 CMoney 收盤資料算好以下數字,"
            "你只負責把它們寫成兩段文字,不可自創任何數字或事件：\n"
            f"{holdings_desc}\n"
            f"庫存加權漲跌 {metrics.get('weighted_change', 0):+.2f}%；"
            f"大盤 {metrics.get('market_change', 0):+.2f}%。\n"
            f"社群(股票同學會)：{community_line}\n"
            f"閃卡事件：{flash_line}\n\n"
            "請生成 JSON：\n"
            "{\n"
            '  "conclusion": "推論卡結論句（40-70 字繁體中文）：對整體庫存的一句判斷,'
            "必須引用上面提供的實際數字,語氣冷靜、標明這是依數字推論\",\n"
            '  "companion": "陪伴卡訊息（80-120 字繁體中文,3-4 句）：手寫信語氣,只安撫情緒,'
            "不提個股名稱、不預測漲跌\"\n"
            "}\n"
            "硬性限制：全程繁體中文；不得出現「建議」二字,也不得出現「買進、賣出、加碼、減碼、"
            "停損、停利、攤平、進場、出場、獲利了結、目標價」等任何引導操作的字眼；"
            "不預測明天漲跌;可描述現況,但不告訴用戶該做什麼交易動作。"
        )

        try:
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    "https://api.openai.com/v1/chat/completions",
                    headers={
                        "Authorization": f"Bearer {settings.OPENAI_API_KEY}",
                        "Content-Type": "application/json"
                    },
                    json={
                        "model": "gpt-4o-mini",
                        "messages": [
                            {"role": "system", "content": "你是一個專門輸出 JSON、依提供數據措辭、語氣冷靜安撫的投資解讀助手。"},
                            {"role": "user", "content": prompt}
                        ],
                        "response_format": {"type": "json_object"},
                        "temperature": 0.7
                    },
                    timeout=6.0
                )
                if response.status_code == 200:
                    data = response.json()
                    import json
                    result = json.loads(data["choices"][0]["message"]["content"])
                    logger.info("Successfully generated pack AI text via GPT-4o-mini")
                    return {
                        "conclusion": result.get("conclusion"),
                        "companion": result.get("companion"),
                    }
                logger.warning(f"OpenAI returned error code {response.status_code}: {response.text}")
        except Exception as e:
            logger.error(f"Failed to fetch pack AI text from OpenAI: {str(e)}")

        return {}
