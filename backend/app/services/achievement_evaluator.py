"""Achievement evaluation engine.

Evaluates every condition that can be derived from the user's current
portfolio snapshot (P/L, weights, industries, anxiety score) and unlocks
the matching achievements. Event-based achievements (OCR import, manual
input …) are unlocked directly by their routes via
AchievementService.trigger_unlock; streak/history achievements are defined
in the catalog but not auto-evaluated yet.
"""
import logging
from datetime import date
from typing import List, Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.achievement import AchievementModel
from app.services.achievements_catalog import ACHIEVEMENTS_BY_KEY

logger = logging.getLogger(__name__)

# ── Theme matchers: (achievement key, industry keywords, symbols, name keywords)
THEME_RULES = [
    ("THEME_AI", ["半導體", "AI"], set(), ["AI", "人工智慧"]),
    ("THEME_COMPUTE", ["半導體"], {"2382", "3231", "NVDA", "AMD"}, ["伺服器"]),
    ("THEME_TSMC", [], {"2330", "TSM"}, ["台積電"]),
    ("THEME_SPACEX", [], set(), ["SpaceX", "太空"]),
    ("THEME_ROCKET", ["航太", "衛星", "太空"], {"RKLB"}, ["航太", "衛星"]),
    ("THEME_EV", ["電動車", "汽車"], {"TSLA", "2308"}, ["電動"]),
    ("THEME_GREEN", ["綠能", "太陽能", "風電", "能源儲存"], set(), ["綠能", "太陽能", "風電"]),
    ("THEME_CRYPTO", ["加密", "區塊鏈"], {"COIN", "MSTR"}, ["比特幣", "區塊鏈"]),
    ("THEME_BANK", ["金融"], set(), ["金控", "銀行"]),
    ("THEME_REIT", ["不動產", "REIT", "營建"], set(), ["REIT"]),
    ("THEME_BIO", ["生技", "醫療", "製藥"], set(), ["生技", "醫療"]),
    ("THEME_OIL", ["能源", "石油"], {"XOM", "CVX"}, ["石油"]),
    ("THEME_DEFENSE", ["國防", "軍工"], {"LMT", "RTX"}, ["軍工"]),
    ("THEME_STAY_HOME", ["遊戲", "電商", "串流"], {"NFLX"}, ["遊戲", "電商", "串流"]),
    ("THEME_CLOUD", ["雲端"], {"AMZN", "MSFT", "GOOG", "GOOGL"}, ["雲端"]),
    ("THEME_APPLE", [], {"AAPL"}, ["蘋果"]),
    ("THEME_GOOGLE", [], {"GOOG", "GOOGL"}, set()),
    ("THEME_META", [], {"META"}, set()),
    ("THEME_AMAZON", [], {"AMZN"}, set()),
    ("THEME_BUFFETT", [], {"BRK.A", "BRK.B", "BRK-B"}, ["波克夏"]),
    ("THEME_INDEX", [], {"0050", "006208", "VOO", "VTI", "SPY", "QQQ"}, ["台灣50", "S&P"]),
    ("THEME_DIVIDEND", [], {"0056", "00878", "00919", "00929"}, ["高股息"]),
]


class Holding:
    def __init__(self, symbol, name, industry, shares, cost, close, change):
        self.symbol = symbol
        self.name = name
        self.industry = industry or ""
        self.shares = shares
        self.cost = cost
        self.close = close
        self.change = change  # today's change_percent

        self.has_pnl = bool(cost and shares and close is not None and cost > 0)
        self.market_value = (close or 0.0) * (shares or 0)
        self.cost_value = (cost or 0.0) * (shares or 0)
        self.pnl_pct = ((close - cost) / cost * 100.0) if self.has_pnl else None
        self.profit_amount = (self.market_value - self.cost_value) if self.has_pnl else 0.0

    @property
    def is_etf(self) -> bool:
        return self.industry == "ETF" or self.symbol.startswith("00")


class AchievementEvaluator:
    def __init__(self, db: Session, user_id: str):
        self.db = db
        self.user_id = user_id

    # ── Unlock plumbing ───────────────────────────────────────────

    def _unlocked_keys(self) -> set:
        stmt = select(AchievementModel.achievement_key).where(
            AchievementModel.user_id == self.user_id,
            AchievementModel.is_unlocked == True,  # noqa: E712
        )
        return set(self.db.scalars(stmt).all())

    def _unlock(self, key: str, already: set, newly: List[str]):
        if key in already or key in newly:
            return
        definition = ACHIEVEMENTS_BY_KEY.get(key)
        if not definition:
            return
        self.db.add(AchievementModel(
            user_id=self.user_id,
            achievement_key=key,
            title=definition["title"],
            description=definition["description"],
            icon_name=definition["icon"],
            is_unlocked=True,
            unlocked_at=date.today(),
        ))
        newly.append(key)

    # ── Snapshot ─────────────────────────────────────────────────

    def _load_holdings(self) -> List[Holding]:
        from app.repositories.repositories import PortfolioRepository, StockRepository
        portfolio_repo = PortfolioRepository(self.db)
        stock_repo = StockRepository(self.db)

        holdings = []
        for item in portfolio_repo.get_items(self.user_id):
            stock = stock_repo.get_stock(item.symbol)
            price = stock_repo.get_daily_price(item.symbol)
            holdings.append(Holding(
                symbol=item.symbol,
                name=stock.name if stock else item.symbol,
                industry=stock.industry if stock else "",
                shares=item.shares,
                cost=float(item.cost_price) if item.cost_price is not None else None,
                close=float(price.close_price) if price else None,
                change=float(price.change_percent) if price else 0.0,
            ))
        return holdings

    def _anxiety_score(self) -> Optional[int]:
        try:
            from app.services.services import AnxietyScoreService
            return AnxietyScoreService(self.db).calculate_anxiety(self.user_id)["score"]
        except Exception as e:  # anxiety needs price data; never block achievements
            logger.warning(f"Anxiety score unavailable for achievements: {e}")
            return None

    # ── Main evaluation ──────────────────────────────────────────

    def evaluate(self) -> List[dict]:
        """Evaluates all derivable conditions; returns newly unlocked definitions."""
        already = self._unlocked_keys()
        newly: List[str] = []

        holdings = self._load_holdings()
        if holdings:
            self._eval_today(holdings, already, newly)
            self._eval_total_pnl(holdings, already, newly)
            self._eval_single(holdings, already, newly)
            self._eval_combo(holdings, already, newly)
            self._eval_theme(holdings, already, newly)
            self._eval_import_followups(holdings, already, newly)

        score = self._anxiety_score() if holdings else None
        if score is not None:
            self._eval_anxiety(score, already, newly)

        if newly:
            self.db.commit()
        return [ACHIEVEMENTS_BY_KEY[k] for k in newly]

    # 今日總損益（依市值加權；沒有市值資料時用平均漲跌幅）
    def _today_change(self, holdings) -> float:
        weighted = [(h.change, h.market_value) for h in holdings if h.market_value > 0]
        if weighted:
            total_mv = sum(mv for _, mv in weighted)
            return sum(c * mv for c, mv in weighted) / total_mv
        return sum(h.change for h in holdings) / len(holdings)

    def _total_pnl_pct(self, holdings) -> Optional[float]:
        cost_total = sum(h.cost_value for h in holdings if h.has_pnl)
        market_total = sum(h.market_value for h in holdings if h.has_pnl)
        if cost_total <= 0:
            return None
        return (market_total - cost_total) / cost_total * 100.0

    def _eval_today(self, holdings, already, newly):
        today = self._today_change(holdings)
        for threshold, key in [(-3, "ANXIETY_DROP_3"), (-5, "ANXIETY_DROP_5"), (-8, "ANXIETY_DROP_8"),
                               (-10, "ANXIETY_DROP_10"), (-15, "ANXIETY_DROP_15")]:
            if today <= threshold:
                self._unlock(key, already, newly)
        if today < 0:
            self._unlock("ANXIETY_STILL_ALIVE", already, newly)

    def _eval_anxiety(self, score, already, newly):
        if score > 60:
            self._unlock("ANXIETY_RADAR_ON", already, newly)
        if score > 90:
            self._unlock("ANXIETY_MAXED", already, newly)
        if score < 10:
            self._unlock("ANXIETY_ZEN", already, newly)
        # 匯入即崩潰：曾使用 OCR 且焦慮指數超過 80
        if score > 80 and "IMPORT_FIRST_OCR" in already:
            self._unlock("IMPORT_INSTANT_PANIC", already, newly)

    def _eval_total_pnl(self, holdings, already, newly):
        total = self._total_pnl_pct(holdings)
        if total is None:
            return
        for threshold, key in [(5, "PNL_UP_5"), (10, "PNL_UP_10"), (50, "PNL_UP_50"),
                               (100, "PNL_UP_100"), (200, "PNL_UP_200"), (500, "PNL_UP_500")]:
            if total >= threshold:
                self._unlock(key, already, newly)
        for threshold, key in [(-10, "PNL_DOWN_10"), (-30, "PNL_DOWN_30"), (-50, "PNL_DOWN_50"),
                               (-99.9, "PNL_DOWN_100")]:
            if total <= threshold:
                self._unlock(key, already, newly)
        if total <= -50:
            self._unlock("PNL_NOT_SOLD_NOT_LOST", already, newly)
        if total >= 100:
            self._unlock("PNL_PAPER_RICH", already, newly)

    def _eval_single(self, holdings, already, newly):
        total_mv = sum(h.market_value for h in holdings)
        pnl_holdings = [h for h in holdings if h.has_pnl]

        total_profit = sum(h.profit_amount for h in pnl_holdings if h.profit_amount > 0)
        total_loss = sum(h.profit_amount for h in pnl_holdings if h.profit_amount < 0)

        for h in holdings:
            weight = (h.market_value / total_mv * 100.0) if total_mv > 0 else 0.0
            if weight > 50:
                self._unlock("SINGLE_CORE_50", already, newly)
            if weight > 80:
                self._unlock("SINGLE_ALL_IN_80", already, newly)

            if h.pnl_pct is None:
                continue
            if h.pnl_pct >= 100:
                self._unlock("SINGLE_UP_100", already, newly)
            if h.pnl_pct >= 1000:
                self._unlock("SINGLE_UP_1000", already, newly)
            if h.profit_amount >= 1_000_000:
                self._unlock("SINGLE_LIFE_CHANGER", already, newly)
            if h.pnl_pct <= -30:
                self._unlock("SINGLE_DOWN_30", already, newly)
            if h.pnl_pct <= -50:
                self._unlock("SINGLE_DOWN_50", already, newly)
                self._unlock("SINGLE_IRON_LEEK", already, newly)
            if h.pnl_pct <= -70:
                self._unlock("SINGLE_DOWN_70", already, newly)
            if h.pnl_pct >= 50:
                self._unlock("SINGLE_DIAMOND_HAND", already, newly)
            if h.pnl_pct <= -30 and weight > 30:
                self._unlock("SINGLE_FAITH", already, newly)
            if total_profit > 0 and h.profit_amount >= total_profit * 0.8 and h.profit_amount > 0:
                self._unlock("SINGLE_CARRY_FAMILY", already, newly)
            if total_loss < 0 and h.profit_amount <= total_loss * 0.8 and h.profit_amount < 0:
                self._unlock("SINGLE_BAD_APPLE", already, newly)

    def _eval_combo(self, holdings, already, newly):
        n = len(holdings)
        if all(h.change > 0 for h in holdings):
            self._unlock("COMBO_ALL_RED", already, newly)
        if all(h.change < 0 for h in holdings):
            self._unlock("COMBO_ALL_GREEN", already, newly)

        pnl_holdings = [h for h in holdings if h.pnl_pct is not None]
        if len(pnl_holdings) >= 3:
            has_big_win = any(h.pnl_pct >= 20 for h in pnl_holdings)
            has_big_loss = any(h.pnl_pct <= -20 for h in pnl_holdings)
            has_flat = any(abs(h.pnl_pct) < 3 for h in pnl_holdings)
            if has_big_win and has_big_loss and has_flat:
                self._unlock("COMBO_TRAFFIC_LIGHT", already, newly)
        if pnl_holdings:
            if all(h.pnl_pct < 0 for h in pnl_holdings):
                self._unlock("COMBO_ALL_TRAPPED", already, newly)
            if all(h.pnl_pct > 0 for h in pnl_holdings):
                self._unlock("COMBO_ALL_PROFIT", already, newly)
        if sum(1 for h in pnl_holdings if h.pnl_pct <= -20) >= 5:
            self._unlock("COMBO_LEEK_FARM", already, newly)
        if sum(1 for h in pnl_holdings if h.pnl_pct >= 20) >= 5:
            self._unlock("COMBO_GODLY", already, newly)

        by_value = sorted(holdings, key=lambda h: h.market_value, reverse=True)
        total_mv = sum(h.market_value for h in holdings)
        top3 = by_value[:3]
        if len(top3) == 3 and all(h.pnl_pct is not None and h.pnl_pct < 0 for h in top3):
            self._unlock("COMBO_STRESS_TEST", already, newly)
        if n >= 20:
            self._unlock("COMBO_DIVERSIFIED", already, newly)
        # 需要 4 檔以上，前 3 大佔比 >70% 才有意義
        if n >= 4 and total_mv > 0 and sum(h.market_value for h in top3) / total_mv > 0.7:
            self._unlock("COMBO_CONCENTRATED", already, newly)
        total_pnl = self._total_pnl_pct(holdings)
        if total_mv > 0 and n >= 2 and max(h.market_value for h in holdings) / total_mv < 0.2 \
                and total_pnl is not None and total_pnl > 0:
            self._unlock("COMBO_BALANCED", already, newly)

        industries = {}
        for h in holdings:
            if h.industry:
                industries.setdefault(h.industry, []).append(h)
        for industry, group in industries.items():
            group_mv = sum(h.market_value for h in group)
            if total_mv > 0 and group_mv / total_mv > 0.7:
                self._unlock("COMBO_ONE_INDUSTRY", already, newly)
            if len(group) >= 2 and all(h.change < 0 for h in group):
                self._unlock("COMBO_INDUSTRY_CRASH", already, newly)

        etf = [h for h in holdings if h.is_etf and h.pnl_pct is not None]
        stock = [h for h in holdings if not h.is_etf and h.pnl_pct is not None]
        if etf and stock:
            etf_profit = sum(h.profit_amount for h in etf)
            stock_profit = sum(h.profit_amount for h in stock)
            if etf_profit > 0 and stock_profit < 0:
                self._unlock("COMBO_ETF_SAVIOR", already, newly)
            if stock_profit > 0 and etf_profit < 0:
                self._unlock("COMBO_STOCK_SAVIOR", already, newly)

    def _eval_theme(self, holdings, already, newly):
        for key, industry_kws, symbols, name_kws in THEME_RULES:
            for h in holdings:
                symbol_hit = h.symbol.upper() in symbols
                industry_hit = any(kw in h.industry for kw in industry_kws)
                name_hit = any(kw in h.name for kw in name_kws)
                if symbol_hit or industry_hit or name_hit:
                    self._unlock(key, already, newly)
                    break

    def _eval_import_followups(self, holdings, already, newly):
        """Achievements that combine import events with the current portfolio state."""
        total_mv = sum(h.market_value for h in holdings)
        total_pnl = self._total_pnl_pct(holdings)
        ocr_used = "IMPORT_FIRST_OCR" in already or "IMPORT_FIRST_OCR" in newly
        manual_used = "IMPORT_MANUAL" in already or "IMPORT_MANUAL" in newly

        if total_mv >= 10_000_000:
            self._unlock("IMPORT_RICH_DAY", already, newly)
        if manual_used and len(holdings) >= 10:
            self._unlock("IMPORT_MANUAL_10", already, newly)
        if ocr_used and manual_used:
            self._unlock("IMPORT_SEMI_AUTO", already, newly)
        if ocr_used:
            self._unlock("IMPORT_AI_REALITY", already, newly)
            if total_pnl is not None and total_pnl <= -30:
                self._unlock("IMPORT_OCR_SAD", already, newly)
            if total_pnl is not None and any(h.pnl_pct is not None and h.pnl_pct < 0 for h in holdings):
                self._unlock("IMPORT_BRAVE", already, newly)
