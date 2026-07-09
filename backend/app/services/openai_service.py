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
