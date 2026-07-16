import math

from sqlalchemy.orm import Session
from datetime import date, datetime
from app.repositories.repositories import (
    StockRepository, PortfolioRepository, CardRepository, ReminderRepository, MarketIndexRepository
)
from app.models.portfolio import PortfolioItem
from app.models.card_result import CardResultModel
from app.models.stock import Stock
from app.models.stock_daily_price import StockDailyPrice
from app.models.market_index import MarketIndexDaily
from app.services.cmoney_service import (
    effective_trade_date, fetch_sim_price, fetch_sim_market, fetch_sim_profile,
)
from app.calculators.anxiety_score_calculator import AnxietyScoreCalculator, AnxietyScoreInput, AnxietyScoreOutput
from app.calculators.card_draw_engine import CardDrawEngine
from typing import List, Optional
from sqlalchemy import select, and_

def is_finite_number(value) -> bool:
    """NaN/Infinity 會被 pydantic 序列化成 null,導致 iOS 解碼失敗;
    凡是要進回應的數值都先過這關。"""
    try:
        return math.isfinite(float(value))
    except (TypeError, ValueError):
        return False


def finite_or_zero(value) -> float:
    return float(value) if is_finite_number(value) else 0.0


def run_async(coro):
    import asyncio
    import contextvars
    from concurrent.futures import ThreadPoolExecutor
    try:
        loop = asyncio.get_event_loop()
    except RuntimeError:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

    if loop.is_running():
        # copy_context:讓 X-AI-Provider 等 contextvar 帶進新 thread,
        # 否則 AI 引擎切換在這條路徑會失效(永遠回到預設 Claude)。
        ctx = contextvars.copy_context()
        with ThreadPoolExecutor(1) as executor:
            return executor.submit(ctx.run, lambda: asyncio.run(coro)).result()
    else:
        return loop.run_until_complete(coro)

def get_live_market_change(db: Session) -> float:
    """今日(14:30 換日)的 TAIEX 漲跌:DB 有快取直接用;
    沒有就以 CMoney 模擬日的大盤 proxy(市值比重加權漲幅)補上並存檔。"""
    today = effective_trade_date()
    stmt = select(MarketIndexDaily).where(
        and_(MarketIndexDaily.index_code == "TAIEX", MarketIndexDaily.trade_date == today)
    )
    existing = db.scalars(stmt).first()
    if existing and is_finite_number(existing.change_percent):
        return float(existing.change_percent)

    # Cache miss (or poisoned NaN cache — refetch to self-heal)
    live_data = fetch_sim_market(db)
    if live_data:
        if existing:
            existing.close_price = live_data["close_price"]
            existing.change_percent = live_data["change_percent"]
        else:
            db.add(MarketIndexDaily(
                index_code="TAIEX",
                trade_date=today,
                close_price=live_data["close_price"],
                change_percent=live_data["change_percent"]
            ))
        db.commit()
        return float(live_data["change_percent"])

    # Fallback to latest in DB
    from sqlalchemy import desc
    fallback_stmt = select(MarketIndexDaily).where(MarketIndexDaily.index_code == "TAIEX").order_by(desc(MarketIndexDaily.trade_date))
    fallback = db.scalars(fallback_stmt).first()
    if fallback and is_finite_number(fallback.change_percent):
        return float(fallback.change_percent)

    return -0.9

# AI 找股離線 fallback:常見主題關鍵字 → (代號, 客觀描述)。
# 描述只陳述標的特性,依 no-advice 規則不得出現「建議」與買賣操作字眼。
FALLBACK_SCREEN_THEMES = [
    (("高股息", "股息", "殖利率", "配息", "存股", "高息", "領息"), [
        ("0056", "元大高股息,追蹤台灣高股息指數,配息紀錄長"),
        ("00878", "國泰永續高股息,季配息,規模居台股 ETF 前列"),
        ("00919", "群益台灣精選高息,近年現金殖利率屬市場偏高水準"),
        ("00929", "復華台灣科技優息,月配息的科技高息 ETF"),
        ("2412", "中華電信,電信龍頭,獲利與股利長年穩定"),
        ("2882", "國泰金控,大型金控,長期有配發股利紀錄"),
    ]),
    (("半導體", "晶片", "晶圓", "ic 設計"), [
        ("2330", "台積電,全球晶圓代工龍頭"),
        ("2454", "聯發科,手機晶片設計大廠"),
        ("2303", "聯電,成熟製程晶圓代工"),
        ("3711", "日月光投控,封裝測試龍頭"),
        ("00891", "中信關鍵半導體,半導體主題 ETF"),
    ]),
    (("市值型", "市值", "大盤", "0050", "台灣50", "指數型"), [
        ("0050", "元大台灣50,追蹤台灣市值前 50 大公司"),
        ("006208", "富邦台50,同樣追蹤台灣50指數,經理費率較低"),
        ("00922", "國泰台灣領袖50,市值型並加入低碳篩選"),
    ]),
    (("金融", "金控", "銀行"), [
        ("2882", "國泰金控,壽險為主的大型金控"),
        ("2881", "富邦金控,獲利規模居金控前列"),
        ("2886", "兆豐金控,官股色彩的銀行型金控"),
        ("2891", "中信金控,銀行型金控,股東人數眾多"),
    ]),
    (("ai", "人工智慧", "伺服器", "機器人"), [
        ("2330", "台積電,AI 晶片主要代工者"),
        ("2317", "鴻海,AI 伺服器組裝要角"),
        ("2382", "廣達,AI 伺服器主力供應商"),
        ("3231", "緯創,AI 伺服器代工"),
    ]),
]


class StockService:
    def __init__(self, db: Session):
        self.repo = StockRepository(db)
        
    def search_stocks(self, keyword: str):
        results = self.repo.search_stocks(keyword)
        if results:
            return results

        # 本地資料庫沒有 + 長得像台股代號 → 用 CMoney 模擬資料驗證後自動入庫
        symbol = keyword.strip()
        if symbol.isdigit() and 4 <= len(symbol) <= 6:
            imported = self._import_unknown_symbol(symbol)
            if imported:
                return [imported]
        return results

    def _import_unknown_symbol(self, symbol: str) -> Optional[Stock]:
        """驗證代號存在(CMoney 模擬日有價格)後寫進 stocks 表,之後可加持股/觀察清單。
        不在 CMoney 300 檔內的代號視為不存在(模擬情境沒有它的任何數據)。

        名稱優先 CMoney 目錄(raw_07),再退證交所/櫃買目錄,最後用代號。"""
        db = self.repo.db
        live = fetch_sim_price(db, symbol)
        if not live:
            return None

        from app.services.stock_directory_service import lookup_tw_stock
        cm_profile = fetch_sim_profile(db, symbol) or {}
        tw_profile = lookup_tw_stock(symbol) or {}
        name = cm_profile.get("name") or tw_profile.get("name") or symbol
        # 目錄查不到但名稱帶 ETF 的視為 ETF(產業曝險歸類用)
        industry = cm_profile.get("industry") or tw_profile.get("industry") \
            or ("ETF" if "etf" in name.lower() else None)

        stock = Stock(symbol=symbol, name=name, market="TW", industry=industry)
        db.add(stock)

        # 順手寫入今日價格快取,搜尋結果馬上有現價可看
        today = effective_trade_date()
        stmt = select(StockDailyPrice).where(
            and_(StockDailyPrice.symbol == symbol, StockDailyPrice.trade_date == today)
        )
        if not db.scalars(stmt).first():
            db.add(StockDailyPrice(
                symbol=symbol, trade_date=today,
                close_price=live["close_price"],
                change_percent=live["change_percent"],
                volume=live["volume"],
            ))
        db.commit()
        db.refresh(stock)
        return stock
        
    def ai_screen(self, query: str) -> dict:
        """AI 找股(觀察清單「加入觀察股」用):自然語言條件 → 已驗證的台股名單。

        GPT 給的名單逐檔用本地 stocks 表 / CMoney 模擬資料驗證,查無此代號的直接丟掉,
        確保回傳的每一檔都能直接加入觀察清單;GPT 離線時退回主題式名單。"""
        query = (query or "").strip()
        if not query:
            return {"items": [], "note": "輸入想找的條件,例如:高股息、殖利率 5% 以上"}

        from app.services.openai_service import OpenAIService
        raw_items = run_async(OpenAIService.fetch_stock_screen(query))

        note = None
        if raw_items is None:
            raw_items, note = self._fallback_screen(query)

        items = []
        seen = set()
        for cand in raw_items:
            if not isinstance(cand, dict):
                continue
            symbol = str(cand.get("symbol", "")).strip().upper()
            reason = str(cand.get("reason", "")).strip()
            if not symbol or symbol in seen:
                continue
            seen.add(symbol)

            stock = self.repo.get_stock(symbol)
            if not stock and symbol.isdigit() and 4 <= len(symbol) <= 6:
                stock = self._import_unknown_symbol(symbol)
            if not stock:
                continue

            price = self.repo.get_daily_price(symbol)
            close = float(price.close_price) if price and is_finite_number(price.close_price) else None
            change = float(price.change_percent) if price and is_finite_number(price.change_percent) else None
            items.append({
                "symbol": stock.symbol,
                "name": stock.name,
                "industry": stock.industry,
                "close_price": close,
                "change_percent": change,
                "reason": reason or "符合你輸入的條件",
            })
            if len(items) >= 8:
                break

        if not items and note is None:
            note = "AI 沒找到可驗證的標的,換個說法試試,例如:高股息、半導體"
        return {"items": items, "note": note}

    def _fallback_screen(self, query: str):
        """GPT 離線時的主題式名單:關鍵字比對常見主題,回 (候選清單, 備註)。"""
        lowered = query.lower()
        for keywords, candidates in FALLBACK_SCREEN_THEMES:
            if any(kw in lowered for kw in keywords):
                raw = [{"symbol": s, "reason": r} for s, r in candidates]
                return raw, "AI 暫時連不上,先列出這個主題的常見標的"
        return [], "AI 暫時連不上,離線模式支援的主題:高股息、半導體、市值型、金融、AI"

    def get_daily_price(self, symbol: str):
        # 1. Check local DB cache first
        cached = self.repo.get_daily_price(symbol)
        
        # 2. Check if we have a cached price for today (14:30 換日)
        #    (帶 NaN 的當日快取視同 miss,重抓一次自癒)
        today = effective_trade_date()
        if (
            cached
            and cached.trade_date == today
            and is_finite_number(cached.close_price)
            and is_finite_number(cached.change_percent)
        ):
            return cached

        # 3. Cache miss: 補 CMoney 模擬日收盤
        live_data = fetch_sim_price(self.repo.db, symbol)
        if live_data:
            db = self.repo.db
            stmt = select(StockDailyPrice).where(
                and_(StockDailyPrice.symbol == symbol, StockDailyPrice.trade_date == today)
            )
            existing = db.scalars(stmt).first()
            if not existing:
                new_price = StockDailyPrice(
                    symbol=symbol,
                    trade_date=today,
                    close_price=live_data["close_price"],
                    change_percent=live_data["change_percent"],
                    volume=live_data["volume"]
                )
                db.add(new_price)
            else:
                existing.close_price = live_data["close_price"]
                existing.change_percent = live_data["change_percent"]
                existing.volume = live_data["volume"]
            db.commit()
            
            # Retrieve fresh record
            cached = self.repo.get_daily_price(symbol)
            return cached
            
        return cached
        
    def get_recommendations(self, symbol: str):
        recommendation_rules = {
            "2330": ["2454", "2317", "2382", "3231"],
            "2454": ["2330", "2317", "2382"],
            "2317": ["2330", "2382", "2308"],
            "2882": ["2891", "0050"],
            "2891": ["2882", "0050"],
            "0050": ["00878", "2330"],
            "00878": ["0050", "2882"]
        }
        related_symbols = recommendation_rules.get(symbol, ["2330", "2317", "2454", "0050", "00878"])
        # filter out self
        related_symbols = [s for s in related_symbols if s != symbol]
        
        results = []
        for sym in related_symbols:
            stock = self.repo.get_stock(sym)
            if stock:
                results.append(stock)
        return results

class PortfolioService:
    def __init__(self, db: Session):
        self.repo = PortfolioRepository(db)
        self.stock_repo = StockRepository(db)
        
    def get_items(self, user_id: str = "demo-user") -> List[dict]:
        items = self.repo.get_items(user_id)
        results = []
        for item in items:
            stock = self.stock_repo.get_stock(item.symbol)
            results.append({
                "id": item.id,
                "symbol": item.symbol,
                "name": stock.name if stock else item.symbol,
                "cost_price": float(item.cost_price) if item.cost_price is not None else None,
                "shares": item.shares,
                "broker": item.broker,
                "created_at": item.created_at
            })
        return results
        
    def add_item(self, symbol: str, cost_price: Optional[float] = None, shares: Optional[int] = None,
                 broker: Optional[str] = None, user_id: str = "demo-user"):
        # Make sure stock exists or create default
        stock = self.stock_repo.get_stock(symbol)
        name = stock.name if stock else symbol

        item = PortfolioItem(
            user_id=user_id,
            symbol=symbol,
            cost_price=cost_price,
            shares=shares,
            broker=broker,
        )
        saved = self.repo.add_item(item)
        from app.services.investment_profile_service import InvestmentProfileService
        InvestmentProfileService(self.repo.db).capture_habit_snapshot(user_id, "holding_added")
        return {
            "id": saved.id,
            "symbol": saved.symbol,
            "name": name,
            "cost_price": float(saved.cost_price) if saved.cost_price is not None else None,
            "shares": saved.shares,
            "broker": saved.broker,
            "created_at": saved.created_at
        }
        
    def update_item(self, item_id: str, user_id: str = "demo-user", *,
                    broker: Optional[str] = None, cost_price: Optional[float] = None,
                    shares: Optional[int] = None):
        """編輯單一券商分帳(含改券商名):直接依 id 更新該筆,不走合併邏輯."""
        item = self.repo.get_item(item_id, user_id)
        if item is None:
            return None
        item.broker = broker
        item.cost_price = cost_price
        item.shares = shares
        self.repo.db.flush()
        from app.services.investment_profile_service import InvestmentProfileService
        InvestmentProfileService(self.repo.db).capture_habit_snapshot(user_id, "holding_updated")
        stock = self.stock_repo.get_stock(item.symbol)
        name = stock.name if stock else item.symbol
        return {
            "id": item.id,
            "symbol": item.symbol,
            "name": name,
            "cost_price": float(item.cost_price) if item.cost_price is not None else None,
            "shares": item.shares,
            "broker": item.broker,
            "created_at": item.created_at,
        }

    def delete_item(self, item_id: str, user_id: str = "demo-user") -> bool:
        deleted = self.repo.delete_item(item_id, user_id)
        if deleted:
            from app.services.investment_profile_service import InvestmentProfileService
            InvestmentProfileService(self.repo.db).capture_habit_snapshot(user_id, "holding_deleted")
        return deleted

class AnxietyScoreService:
    def __init__(self, db: Session):
        self.portfolio_repo = PortfolioRepository(db)
        self.stock_repo = StockRepository(db)
        self.market_repo = MarketIndexRepository(db)
        self.calculator = AnxietyScoreCalculator()
        
    def calculate_anxiety(self, user_id: str = "demo-user") -> dict:
        items = self.portfolio_repo.get_items(user_id)
        if not items:
            return {
                "score": 30,
                "level": "穩定",
                "message": "您目前沒有持股，市場波動對您沒有影響。",
                "main_reason": "無持股狀態",
                "risk_label": "穩定"
            }
            
        total_change = 0.0
        max_drop = 0.0
        
        for item in items:
            price_info = self.stock_repo.get_daily_price(item.symbol)
            change = finite_or_zero(price_info.change_percent) if price_info else 0.0
            total_change += change
            if change < max_drop:
                max_drop = change
                
        avg_change = total_change / len(items)
        
        market_change = get_live_market_change(self.portfolio_repo.db)
        
        input_data = AnxietyScoreInput(
            portfolio_change_percent=avg_change,
            market_change_percent=market_change,
            max_drop_percent=max_drop
        )
        
        output = self.calculator.calculate(input_data)
        
        # Message template selection
        score = output.score
        if score <= 30:
            message = "今天你的持股情緒相對平靜，波動在健康範圍內。不需要感到擔心。"
        elif score <= 50:
            message = "今天你的持股有些輕微波動，主要是受個別版塊拉回影響，大勢基本穩定。"
        elif score <= 70:
            message = "今日持股波動較明顯，科技板塊的壓力較大，引發整體持股表現稍弱於大盤。"
        elif score <= 85:
            message = "今天你的持股下跌偏多，部分個股回檔幅度較深，先深呼吸，不需要急著做任何決定。"
        else:
            message = "今天市場大幅修正或您的重倉股大跌。請先深呼吸，這是市場的系統性修正，並不代表公司的長期價值改變。"
            
        return {
            "score": score,
            "level": output.level,
            "message": message,
            "main_reason": "主要受到今日科技股與大盤偏弱拉回影響" if avg_change < 0 else "今日持股表現強勁，情緒穩定",
            "risk_label": output.risk_label
        }

class DailySummaryService:
    def __init__(self, db: Session):
        self.portfolio_repo = PortfolioRepository(db)
        self.stock_repo = StockRepository(db)
        self.market_repo = MarketIndexRepository(db)
        
    def get_summary(self, user_id: str = "demo-user") -> dict:
        items = self.portfolio_repo.get_items(user_id)
        
        market_change = get_live_market_change(self.portfolio_repo.db)
        
        impact_items = []
        for item in items:
            stock = self.stock_repo.get_stock(item.symbol)
            price_info = self.stock_repo.get_daily_price(item.symbol)
            change = finite_or_zero(price_info.change_percent) if price_info else 0.0
            
            if change < -2.0:
                impact = "HIGH"
                reason = "受整體科技板塊震盪影響，今日賣壓較重。"
            elif change < 0:
                impact = "MEDIUM"
                reason = "小幅拉回，與市場均值波動相近。"
            else:
                impact = "LOW"
                reason = "今日走勢穩健，提供帳戶情緒支撐力。"
                
            impact_items.append({
                "symbol": item.symbol,
                "name": stock.name if stock else item.symbol,
                "change_percent": change,
                "impact_level": impact,
                "reason": reason
            })
            
        # Check and trigger achievements
        achievement_service = AchievementService(self.portfolio_repo.db)
        achievement_service.trigger_unlock("CALM_BEGINNER", user_id)
        
        if market_change < -1.5:
            achievement_service.trigger_unlock("MARKET_RESISTER", user_id)
            
        for item in impact_items:
            if item["change_percent"] < -3.0:
                achievement_service.trigger_unlock("STORM_WITNESS", user_id)
                break
                
        return {
            "title": "今日持股白話分析",
            "summary": "今天你的持股整體呈現拉回走勢。這主要是整體半導體及科技股遭遇獲利回吐，並不一定代表你的持股公司基本面發生了變化。",
            "explanation": "當前市場對於通膨與利率走勢仍有觀望情緒，加上前期漲幅已大，因此出現大盤同步下滑。對於新手而言，看懂今日是『全體科技股一起跌』而不是『你的公司單獨出事』，有助於保持冷靜。先觀察就好，不需要急著做任何交易決定。",
            "portfolio_impact_items": impact_items,
            "disclaimer": "內容僅供資訊參考，不構成投資建議。"
        }

class CardDrawService:
    def __init__(self, db: Session):
        self.anxiety_service = AnxietyScoreService(db)
        self.card_repo = CardRepository(db)
        self.engine = CardDrawEngine()
        
    def draw_today_card(self, user_id: str = "demo-user") -> dict:
        today = date.today()
        existing = self.card_repo.get_today_card(user_id, today)
        if existing:
            return {
                "card_type": existing.card_type,
                "title": existing.title,
                "message": existing.message,
                "action_text": existing.action_text
            }
            
        # Get score
        anxiety = self.anxiety_service.calculate_anxiety(user_id)
        score = anxiety["score"]
        
        # Build dynamic card metrics + full holdings detail for the GPT prompt
        items = self.anxiety_service.portfolio_repo.get_items(user_id)
        worst_name = None
        worst_change = 0.0
        holdings = []
        total_change = 0.0

        for item in items:
            stock = self.anxiety_service.stock_repo.get_stock(item.symbol)
            price_info = self.anxiety_service.stock_repo.get_daily_price(item.symbol)
            change = finite_or_zero(price_info.change_percent) if price_info else 0.0
            name = stock.name if stock else item.symbol

            holdings.append({
                "symbol": item.symbol,
                "name": name,
                "change_percent": change,
                "shares": item.shares,
            })
            total_change += change

            if worst_name is None or change < worst_change:
                worst_name = name
                worst_change = change

        market_change = get_live_market_change(self.anxiety_service.portfolio_repo.db)
        avg_change = total_change / len(items) if items else 0.0

        # Draw card via OpenAI (with robust fallback)
        from app.services.openai_service import OpenAIService
        card_data = run_async(
            OpenAIService.fetch_card_draw_message(
                avg_change=avg_change,
                worst_name=worst_name,
                worst_change=worst_change,
                market_change=market_change,
                holdings=holdings
            )
        )
        
        msg_with_motto = card_data["message"]
        if card_data.get("motto"):
            msg_with_motto += f"\n\n【今日心法】\n{card_data['motto']}"
            
        card_model = CardResultModel(
            user_id=user_id,
            trade_date=today,
            card_type=card_data["card_type"],
            title=card_data["title"],
            message=msg_with_motto,
            action_text=card_data["action_text"]
        )
        self.card_repo.save_card(card_model)
        
        return {
            "card_type": card_data["card_type"],
            "title": card_data["title"],
            "message": msg_with_motto,
            "action_text": card_data["action_text"]
        }
        
    def get_today_card(self, user_id: str = "demo-user") -> Optional[dict]:
        today = date.today()
        existing = self.card_repo.get_today_card(user_id, today)
        if not existing:
            return None
        return {
            "card_type": existing.card_type,
            "title": existing.title,
            "message": existing.message,
            "action_text": existing.action_text
        }

class MarketCompareService:
    def __init__(self, db: Session):
        self.portfolio_repo = PortfolioRepository(db)
        self.stock_repo = StockRepository(db)
        self.market_repo = MarketIndexRepository(db)
        
    def compare_market(self, user_id: str = "demo-user") -> dict:
        items = self.portfolio_repo.get_items(user_id)
        if not items:
            return {
                "portfolio_change_percent": 0.0,
                "market_change_percent": -0.9,
                "message": "尚未添加持股，無法進行表現對比。"
            }
            
        total_change = 0.0
        for item in items:
            price_info = self.stock_repo.get_daily_price(item.symbol)
            change = finite_or_zero(price_info.change_percent) if price_info else 0.0
            total_change += change
            
        avg_change = total_change / len(items)
        
        market_change = get_live_market_change(self.portfolio_repo.db)
        
        diff = avg_change - market_change
        
        if diff > 0.5:
            message = "今天你的持股表現比大盤稍微抗跌，展現出不錯的韌性。"
        elif diff < -0.5:
            message = "今天你的持股跌幅大於大盤，主要受累於科技板塊的深幅拉回。"
        else:
            message = "今天你的持股走勢基本與大盤同步，屬於正常的市場震盪範圍。"
            
        return {
            "portfolio_change_percent": avg_change,
            "market_change_percent": market_change,
            "message": message
        }

class ReminderService:
    def __init__(self, db: Session):
        self.repo = ReminderRepository(db)
        
    def get_settings(self, user_id: str = "demo-user") -> dict:
        setting = self.repo.get_settings(user_id)
        return {
            "enabled": setting.enabled,
            "time_slot": setting.time_slot,
            "items": {
                "anxiety_score": setting.anxiety_score,
                "daily_card": setting.daily_card,
                "volatility_alert": setting.volatility_alert
            }
        }
        
    def save_settings(self, data: dict, user_id: str = "demo-user") -> dict:
        saved = self.repo.save_settings(
            user_id=user_id,
            enabled=data["enabled"],
            time_slot=data["time_slot"],
            anxiety_score=data["items"]["anxiety_score"],
            daily_card=data["items"]["daily_card"],
            volatility_alert=data["items"]["volatility_alert"]
        )
        return {
            "enabled": saved.enabled,
            "time_slot": saved.time_slot,
            "items": {
                "anxiety_score": saved.anxiety_score,
                "daily_card": saved.daily_card,
                "volatility_alert": saved.volatility_alert
            }
        }

class AchievementService:
    """Catalog-driven achievements: definitions live in achievements_catalog,
    the DB only stores unlock records per user."""

    def __init__(self, db: Session):
        self.db = db

    def get_achievements(self, user_id: str = "demo-user") -> List[dict]:
        from app.models.achievement import AchievementModel
        from app.services.achievements_catalog import ACHIEVEMENTS, CATEGORY_NAMES
        from sqlalchemy import select

        stmt = select(AchievementModel).where(
            AchievementModel.user_id == user_id,
            AchievementModel.is_unlocked == True  # noqa: E712
        )
        unlocked = {r.achievement_key: r for r in self.db.scalars(stmt).all()}

        result = []
        for definition in ACHIEVEMENTS:
            record = unlocked.get(definition["key"])
            is_unlocked = record is not None
            masked = definition["hidden"] and not is_unlocked
            result.append({
                "achievement_key": definition["key"],
                "title": "？？？" if masked else definition["title"],
                "description": "隱藏成就：達成後揭曉" if masked else definition["description"],
                "icon_name": "questionmark" if masked else definition["icon"],
                "category": definition["category"],
                "category_name": CATEGORY_NAMES[definition["category"]],
                "rarity": definition["rarity"],
                "is_hidden": definition["hidden"],
                "is_unlocked": is_unlocked,
                "unlocked_at": record.unlocked_at.strftime("%Y-%m-%d") if record and record.unlocked_at else None
            })
        return result

    def evaluate(self, user_id: str = "demo-user") -> List[dict]:
        """Runs the evaluation engine and returns newly unlocked achievements."""
        from app.services.achievement_evaluator import AchievementEvaluator
        from app.services.achievements_catalog import CATEGORY_NAMES

        newly = AchievementEvaluator(self.db, user_id).evaluate()
        return [
            {
                "achievement_key": d["key"],
                "title": d["title"],
                "description": d["description"],
                "icon_name": d["icon"],
                "category": d["category"],
                "category_name": CATEGORY_NAMES[d["category"]],
                "rarity": d["rarity"],
                "is_hidden": d["hidden"],
                "is_unlocked": True,
                "unlocked_at": date.today().strftime("%Y-%m-%d")
            }
            for d in newly
        ]

    def trigger_unlock(self, achievement_key: str, user_id: str = "demo-user") -> bool:
        """Unlocks a single catalog achievement (used by event hooks like OCR import)."""
        from app.models.achievement import AchievementModel
        from app.services.achievements_catalog import get_definition
        from sqlalchemy import select, and_
        from datetime import date as date_type

        definition = get_definition(achievement_key)
        if not definition:
            return False

        stmt = select(AchievementModel).where(
            and_(AchievementModel.user_id == user_id, AchievementModel.achievement_key == achievement_key)
        )
        achievement = self.db.scalars(stmt).first()
        if achievement is None:
            self.db.add(AchievementModel(
                user_id=user_id,
                achievement_key=achievement_key,
                title=definition["title"],
                description=definition["description"],
                icon_name=definition["icon"],
                is_unlocked=True,
                unlocked_at=date_type.today()
            ))
            self.db.commit()
            return True
        if not achievement.is_unlocked:
            achievement.is_unlocked = True
            achievement.unlocked_at = date_type.today()
            self.db.commit()
            return True
        return False
