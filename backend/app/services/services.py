from sqlalchemy.orm import Session
from datetime import date, datetime
from app.repositories.repositories import (
    StockRepository, PortfolioRepository, CardRepository, ReminderRepository, MarketIndexRepository
)
from app.models.portfolio import PortfolioItem
from app.models.card_result import CardResultModel
from app.models.stock_daily_price import StockDailyPrice
from app.models.market_index import MarketIndexDaily
from app.services.yahoo_finance_service import YahooFinanceService
from app.calculators.anxiety_score_calculator import AnxietyScoreCalculator, AnxietyScoreInput, AnxietyScoreOutput
from app.calculators.card_draw_engine import CardDrawEngine
from typing import List, Optional
from sqlalchemy import select, and_

def run_async(coro):
    import asyncio
    from concurrent.futures import ThreadPoolExecutor
    try:
        loop = asyncio.get_event_loop()
    except RuntimeError:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        
    if loop.is_running():
        with ThreadPoolExecutor(1) as executor:
            return executor.submit(lambda: asyncio.run(coro)).result()
    else:
        return loop.run_until_complete(coro)

def get_live_market_change(db: Session) -> float:
    """
    Checks if TAIEX market index daily price is cached in DB for today.
    If not, queries Yahoo Finance, saves to DB, and returns the change percent.
    """
    today = date.today()
    stmt = select(MarketIndexDaily).where(
        and_(MarketIndexDaily.index_code == "TAIEX", MarketIndexDaily.trade_date == today)
    )
    existing = db.scalars(stmt).first()
    if existing:
        return float(existing.change_percent)
        
    # Cache miss
    live_data = YahooFinanceService.fetch_live_price("TAIEX")
    if live_data:
        new_index = MarketIndexDaily(
            index_code="TAIEX",
            trade_date=today,
            close_price=live_data["close_price"],
            change_percent=live_data["change_percent"]
        )
        db.add(new_index)
        db.commit()
        return float(live_data["change_percent"])
        
    # Fallback to latest in DB
    from sqlalchemy import desc
    fallback_stmt = select(MarketIndexDaily).where(MarketIndexDaily.index_code == "TAIEX").order_by(desc(MarketIndexDaily.trade_date))
    fallback = db.scalars(fallback_stmt).first()
    if fallback:
        return float(fallback.change_percent)
        
    return -0.9

class StockService:
    def __init__(self, db: Session):
        self.repo = StockRepository(db)
        
    def search_stocks(self, keyword: str):
        return self.repo.search_stocks(keyword)
        
    def get_daily_price(self, symbol: str):
        # 1. Check local DB cache first
        cached = self.repo.get_daily_price(symbol)
        
        # 2. Check if we have a cached price for today
        today = date.today()
        if cached and cached.trade_date == today:
            return cached
            
        # 3. Cache miss: Fetch from Yahoo Finance
        live_data = YahooFinanceService.fetch_live_price(symbol)
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
                "created_at": item.created_at
            })
        return results
        
    def add_item(self, symbol: str, cost_price: Optional[float] = None, shares: Optional[int] = None, user_id: str = "demo-user"):
        # Make sure stock exists or create default
        stock = self.stock_repo.get_stock(symbol)
        name = stock.name if stock else symbol
        
        item = PortfolioItem(
            user_id=user_id,
            symbol=symbol,
            cost_price=cost_price,
            shares=shares
        )
        saved = self.repo.add_item(item)
        return {
            "id": saved.id,
            "symbol": saved.symbol,
            "name": name,
            "cost_price": float(saved.cost_price) if saved.cost_price is not None else None,
            "shares": saved.shares,
            "created_at": saved.created_at
        }
        
    def delete_item(self, item_id: str, user_id: str = "demo-user") -> bool:
        return self.repo.delete_item(item_id, user_id)

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
            change = float(price_info.change_percent) if price_info else 0.0
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
            message = "今天你的持股下跌偏多，部分個股回檔幅度較深，建議不要急著做交易決定。"
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
            change = float(price_info.change_percent) if price_info else 0.0
            
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
            "explanation": "當前市場對於通膨與利率走勢仍有觀望情緒，加上前期漲幅已大，因此出現大盤同步下滑。對於新手而言，看懂今日是『全體科技股一起跌』而不是『你的公司單獨出事』，有助於保持冷靜。建議先觀察，不需要急著買進或賣出。",
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
        
        # Build dynamic card metrics
        items = self.anxiety_service.portfolio_repo.get_items(user_id)
        worst_name = None
        worst_change = 0.0
        best_name = None
        best_change = 0.0
        
        if items:
            for item in items:
                stock = self.anxiety_service.stock_repo.get_stock(item.symbol)
                price_info = self.anxiety_service.stock_repo.get_daily_price(item.symbol)
                change = float(price_info.change_percent) if price_info else 0.0
                
                if worst_name is None or change < worst_change:
                    worst_name = stock.name if stock else item.symbol
                    worst_change = change
                if best_name is None or change > best_change:
                    best_name = stock.name if stock else item.symbol
                    best_change = change
                    
        market_change = get_live_market_change(self.anxiety_service.portfolio_repo.db)
        avg_change = (worst_change + best_change) / 2.0 if items else 0.0
        
        # Draw card via OpenAI (with robust fallback)
        from app.services.openai_service import OpenAIService
        card_data = run_async(
            OpenAIService.fetch_card_draw_message(
                avg_change=avg_change,
                worst_name=worst_name,
                worst_change=worst_change,
                market_change=market_change
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
            change = float(price_info.change_percent) if price_info else 0.0
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
    def __init__(self, db: Session):
        self.db = db
        
    def get_achievements(self, user_id: str = "demo-user") -> List[dict]:
        from app.models.achievement import AchievementModel
        from sqlalchemy import select
        stmt = select(AchievementModel).where(AchievementModel.user_id == user_id)
        results = self.db.scalars(stmt).all()
        
        if not results:
            # Seed default achievements
            defaults = [
                ("CALM_BEGINNER", "冷靜初學者", "完成第一天的持股情緒白話分析閱讀", "leaf.fill"),
                ("HABIT_BUILDER", "冷靜記錄者", "連續 3 天打開 App 閱讀持股分析與心法", "calendar.badge.clock"),
                ("STORM_WITNESS", "風浪見證者", "在庫存個股大跌超過 3% 的日子，冷靜讀完分析不慌張", "wind"),
                ("MARKET_RESISTER", "大盤對抗者", "在大盤指數大跌超過 1.5% 的日子，依然上線閱讀陪伴內容", "shield.fill")
            ]
            results = []
            for key, title, desc, icon in defaults:
                model = AchievementModel(
                    user_id=user_id,
                    achievement_key=key,
                    title=title,
                    description=desc,
                    icon_name=icon,
                    is_unlocked=False,
                    unlocked_at=None
                )
                self.db.add(model)
                results.append(model)
            self.db.commit()
            
        return [
            {
                "achievement_key": r.achievement_key,
                "title": r.title,
                "description": r.description,
                "icon_name": r.icon_name,
                "is_unlocked": r.is_unlocked,
                "unlocked_at": r.unlocked_at.strftime("%Y-%m-%d") if r.unlocked_at else None
            }
            for r in results
        ]
        
    def trigger_unlock(self, achievement_key: str, user_id: str = "demo-user") -> bool:
        from app.models.achievement import AchievementModel
        from sqlalchemy import select, and_
        from datetime import date
        stmt = select(AchievementModel).where(
            and_(AchievementModel.user_id == user_id, AchievementModel.achievement_key == achievement_key)
        )
        achievement = self.db.scalars(stmt).first()
        if achievement and not achievement.is_unlocked:
            achievement.is_unlocked = True
            achievement.unlocked_at = date.today()
            self.db.commit()
            return True
        return False
