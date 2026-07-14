"""CMoney Hackathon 2025 模擬資料存取層。

專案為模擬情境:CMoney 提供 2025 全年資料(RDS `raw` schema,本機以
scripts/load_cmoney_raw.py 灌入)。後端以「今天 − 1 年」作為模擬交易日,
取當天資料做分析,再交給 AI 產生文字。

- 價格/估值:raw_01(日期 YYYYMMDD)
- 法人買賣超/外資持股:raw_02
- 動能(創歷史新高/創N日新高/連N日漲):raw_04 —— 閃卡的寫死數據事件直接用官方旗標
- 除息日:raw_05(除息日 YYYYMMDD,可能落在 2026)
- 產業分類:raw_07
- 股票同學會每日發文統計:raw_10(日期 YYYY-MM-DD)—— 社群溫度計
- 大盤:資料包沒有指數,以「市值比重加權漲幅」做大盤 proxy

raw 表不存在(如單元測試的 SQLite)時 `available` 為 False,
呼叫端 fallback 回原本 public 表的路徑。
"""
import logging
import math
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from typing import Dict, List, Optional, Tuple
from zoneinfo import ZoneInfo

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.models.market_index import MarketIndexDaily
from app.models.stock import Stock
from app.models.stock_daily_price import StockDailyPrice

logger = logging.getLogger(__name__)

DATA_SOURCE = "CMoney 股市資料(2025 模擬年)"
FORUM_SOURCE = "CMoney 股票同學會每日統計(2025 模擬年)"

TAIPEI = ZoneInfo("Asia/Taipei")
CLOSE_UPDATE = time(14, 30)


def effective_trade_date(now: Optional[datetime] = None) -> date:
    """全 App 統一的「今日交易日」:14:30 收盤資料更新前算前一日。
    每日卡包、個股價格快取、大盤快取都以這個日期為準,確保吃同一份模擬數據。

    展示用途:sim_clock 若設了模擬今天覆寫(且呼叫端沒帶明確 now),
    直接回覆寫值,整個 App 的「今天」一起移動 → 模擬交易日(今天 − 1 年)隨之改變。
    帶明確 now(如單元測試)時忽略覆寫,照 14:30 規則計算。"""
    if now is None:
        from app.services import sim_clock
        override = sim_clock.get_override()
        if override is not None:
            return override
        now = datetime.now(TAIPEI)
    d = now.date()
    return d - timedelta(days=1) if now.time() < CLOSE_UPDATE else d


def simulated_target(real_date: date) -> date:
    """模擬交易日 = 真實日期 − 1 年(2/29 對映 2/28)。"""
    try:
        return real_date.replace(year=real_date.year - 1)
    except ValueError:
        return real_date.replace(year=real_date.year - 1, day=28)


def _f(value) -> Optional[float]:
    """raw 表全 text;空字串/None/非有限值(NaN、Infinity)→ None。"""
    if value is None or value == "":
        return None
    try:
        f = float(value)
    except (TypeError, ValueError):
        return None
    return f if math.isfinite(f) else None


@dataclass
class CMoneyPrice:
    close: Optional[float]
    change_percent: Optional[float]
    volume: Optional[float]
    cap_weight: Optional[float]


@dataclass
class CMoneyInstitutional:
    net_buy_total: Optional[float]        # 買賣超合計(張)
    foreign_ratio: Optional[float]        # 外資持股比率(%)
    consecutive_buy_days: int             # 法人連續買超天數(含當日)


@dataclass
class CMoneyMomentum:
    all_time_high: bool                   # 股價創歷史新高
    n_day_high: int                       # 股價創N日新高(負值=非新高)
    up_streak: int                        # 股價連N日漲


@dataclass
class CMoneyForum:
    posts: int                            # 今日發文則數
    bullish: int
    bearish: int
    neutral: int
    replies: int
    baseline_posts_avg: Optional[float]   # 近 N 日發文均值(不含當日)
    baseline_bullish_ratio: Optional[float]   # 近 N 日看多占比均值(%)


class CMoneyDataService:
    def __init__(self, db: Session):
        self.db = db

    # ── 可用性與日期 ─────────────────────────────────────────

    @property
    def available(self) -> bool:
        try:
            # 非 Postgres(單元測試的 SQLite)直接走 fallback,不能發查詢:
            # 查詢失敗的 rollback 會把呼叫端同 session 未 commit 的資料一起洗掉
            if self.db.get_bind().dialect.name != "postgresql":
                return False
            return bool(self.db.execute(
                text("SELECT to_regclass('raw.raw_01_price_valuation_2025')")
            ).scalar())
        except Exception:
            self.db.rollback()
            return False

    def resolve_trade_date(self, target: date) -> Optional[str]:
        """目標日(含)以前最近的資料交易日,回 'YYYYMMDD';假日自動回退。"""
        return self.db.execute(text(
            'SELECT max("日期") FROM raw.raw_01_price_valuation_2025 WHERE "日期" <= :d'
        ), {"d": target.strftime("%Y%m%d")}).scalar()

    @staticmethod
    def to_date(yyyymmdd: str) -> date:
        return date(int(yyyymmdd[:4]), int(yyyymmdd[4:6]), int(yyyymmdd[6:8]))

    # ── 價格與大盤 ───────────────────────────────────────────

    def get_price(self, symbol: str, yyyymmdd: str) -> Optional[CMoneyPrice]:
        row = self.db.execute(text(
            'SELECT "收盤價", "漲幅(%)", "成交量", "市值比重(%)" '
            'FROM raw.raw_01_price_valuation_2025 '
            'WHERE "股票代號" = :s AND "日期" = :d'
        ), {"s": symbol, "d": yyyymmdd}).first()
        if not row:
            return None
        return CMoneyPrice(close=_f(row[0]), change_percent=_f(row[1]),
                           volume=_f(row[2]), cap_weight=_f(row[3]))

    def market_change(self, yyyymmdd: str) -> Optional[float]:
        """大盤 proxy:全資料集市值比重加權平均漲幅(資料包沒有加權指數)。"""
        row = self.db.execute(text(
            'SELECT sum(cast("市值比重(%)" as float) * cast("漲幅(%)" as float)) '
            '     / nullif(sum(cast("市值比重(%)" as float)), 0) '
            'FROM raw.raw_01_price_valuation_2025 '
            'WHERE "日期" = :d AND "市值比重(%)" IS NOT NULL AND "漲幅(%)" IS NOT NULL'
        ), {"d": yyyymmdd}).scalar()
        return round(float(row), 2) if row is not None else None

    # ── 法人 / 動能 / 除息(閃卡的寫死數據事件來源) ─────────────

    def get_institutional(self, symbol: str, yyyymmdd: str) -> Optional[CMoneyInstitutional]:
        rows = self.db.execute(text(
            'SELECT "買賣超合計", "外資持股比率(%)" '
            'FROM raw.raw_02_institutional_trading_2025 '
            'WHERE "股票代號" = :s AND "日期" <= :d ORDER BY "日期" DESC LIMIT 30'
        ), {"s": symbol, "d": yyyymmdd}).fetchall()
        if not rows:
            return None
        streak = 0
        for r in rows:
            net = _f(r[0])
            if net is not None and net > 0:
                streak += 1
            else:
                break
        return CMoneyInstitutional(
            net_buy_total=_f(rows[0][0]),
            foreign_ratio=_f(rows[0][1]),
            consecutive_buy_days=streak,
        )

    def get_momentum(self, symbol: str, yyyymmdd: str) -> Optional[CMoneyMomentum]:
        row = self.db.execute(text(
            'SELECT "股價創歷史新高", "股價創N日新高", "股價連N日漲" '
            'FROM raw.raw_04_distance_from_high_low_momentum_2025 '
            'WHERE "股票代號" = :s AND "日期" = :d'
        ), {"s": symbol, "d": yyyymmdd}).first()
        if not row:
            return None
        return CMoneyMomentum(
            all_time_high=(_f(row[0]) or 0) >= 1,
            n_day_high=int(_f(row[1]) or 0),
            up_streak=int(_f(row[2]) or 0),
        )

    def days_to_ex_dividend(self, symbol: str, sim_date: date) -> Optional[int]:
        """距除息日天數(除息日在模擬日之後才有意義)。"""
        row = self.db.execute(text(
            'SELECT "除息日" FROM raw.raw_05_dividend_ex_dividend_2025 '
            'WHERE "股票代號" = :s AND "除息日" IS NOT NULL '
            'ORDER BY "除息日" LIMIT 1'
        ), {"s": symbol}).first()
        if not row or not row[0]:
            return None
        try:
            ex_date = self.to_date(row[0])
        except (ValueError, IndexError):
            return None
        delta = (ex_date - sim_date).days
        return delta if delta >= 0 else None

    # ── 股票同學會(raw_10)→ 社群溫度計 ─────────────────────

    def get_forum(self, symbol: str, sim_date: date,
                  baseline_days: int = 20) -> Optional[CMoneyForum]:
        day_str = sim_date.strftime("%Y-%m-%d")
        today = self.db.execute(text(
            'SELECT "發文則數", "看多發文", "看空發文", "中性發文", "回文則數" '
            'FROM raw.raw_10_forum_posts_replies_daily_stats_2025 '
            'WHERE "股票代號" = :s AND "日期" = :d'
        ), {"s": symbol, "d": day_str}).first()
        if not today:
            return None

        # 基準:模擬日前 N 日(不含當日),只顯示相對自身歷史的變化
        baseline = self.db.execute(text(
            'SELECT avg(cast("發文則數" as float)), '
            '       avg(cast("看多發文" as float) / nullif(cast("發文則數" as float), 0) * 100) '
            'FROM raw.raw_10_forum_posts_replies_daily_stats_2025 '
            'WHERE "股票代號" = :s AND "日期" < :d AND "日期" >= :start'
        ), {
            "s": symbol, "d": day_str,
            "start": (sim_date - timedelta(days=baseline_days + 10)).strftime("%Y-%m-%d"),
        }).first()

        return CMoneyForum(
            posts=int(_f(today[0]) or 0),
            bullish=int(_f(today[1]) or 0),
            bearish=int(_f(today[2]) or 0),
            neutral=int(_f(today[3]) or 0),
            replies=int(_f(today[4]) or 0),
            baseline_posts_avg=_f(baseline[0]) if baseline else None,
            baseline_bullish_ratio=_f(baseline[1]) if baseline else None,
        )

    # ── 同步 public 表:讓全 App(焦慮分數/庫存分析)吃同一份模擬數據 ──

    def sync_public_tables(self, real_today: date, yyyymmdd: str) -> None:
        """把模擬日的 CMoney 收盤資料 upsert 進 public 表(trade_date = 真實今天),
        讓全 App(焦慮分數/庫存分析/個股頁)吃同一份模擬數據:

        - stocks:300 檔目錄(raw_07,主產業)
        - stock_daily_prices:全檔收盤/漲跌/量(覆寫式,先前寫入的今日列一律蓋掉)
        - market_index_daily:TAIEX = 市值比重加權 proxy
        冪等:今日列數已足且 TAIEX proxy 與目前模擬日一致 → 跳過;
        14:30 後模擬日前進一天,proxy 改變會觸發整批重新覆寫。
        """
        market = self.market_change(yyyymmdd)
        expected = round(market, 2) if market is not None else 0.0

        synced_count = self.db.query(StockDailyPrice).filter(
            StockDailyPrice.trade_date == real_today
        ).count()
        index_row = self.db.query(MarketIndexDaily).filter(
            MarketIndexDaily.index_code == "TAIEX",
            MarketIndexDaily.trade_date == real_today,
        ).first()
        if synced_count >= 100 and index_row is not None \
                and round(index_row.change_percent, 2) == expected:
            return

        # stocks 目錄
        directory = self.db.execute(text(
            'SELECT "股票代號", "股票名稱", "主產業" '
            'FROM raw.raw_07_industry_classification_mapping'
        )).fetchall()
        known = {s.symbol for s in self.db.query(Stock.symbol).all()}
        for symbol, name, industry in directory:
            if symbol and symbol not in known:
                self.db.add(Stock(symbol=symbol, name=name or symbol,
                                  market="TW", industry=industry or "其他"))

        # 當日全檔價格(覆寫式 upsert:模擬情境以 CMoney 為準)
        prices = self.db.execute(text(
            'SELECT "股票代號", "收盤價", "漲幅(%)", "成交量" '
            'FROM raw.raw_01_price_valuation_2025 WHERE "日期" = :d'
        ), {"d": yyyymmdd}).fetchall()
        existing_rows = {
            p.symbol: p for p in self.db.query(StockDailyPrice).filter(
                StockDailyPrice.trade_date == real_today
            ).all()
        }
        avg_close_num = 0.0
        avg_close_den = 0.0
        for symbol, close, change, volume in prices:
            close_f, change_f = _f(close), _f(change)
            if close_f is None:
                continue
            row = existing_rows.get(symbol)
            if row:
                row.close_price = close_f
                row.change_percent = change_f or 0.0
                row.volume = _f(volume)
            else:
                self.db.add(StockDailyPrice(
                    symbol=symbol, trade_date=real_today,
                    close_price=close_f, change_percent=change_f or 0.0,
                    volume=_f(volume),
                ))
            avg_close_num += close_f
            avg_close_den += 1

        proxy_close = round(avg_close_num / avg_close_den, 2) if avg_close_den else 0.0
        if index_row:
            index_row.close_price = proxy_close
            index_row.change_percent = expected
        else:
            self.db.add(MarketIndexDaily(
                index_code="TAIEX", trade_date=real_today,
                close_price=proxy_close,
                change_percent=expected,
            ))
        self.db.flush()
        logger.info("CMoney sync: %s 檔價格 → %s(模擬日 %s,大盤 proxy %s%%)",
                    len(prices), real_today, yyyymmdd, expected)


# ── 取代 Yahoo 的即時查價介面(全 App 唯一資料源是 CMoney) ────────

def _resolve_sim_day(db: Session) -> Optional[Tuple["CMoneyDataService", str]]:
    cm = CMoneyDataService(db)
    if not cm.available:
        return None
    yyyymmdd = cm.resolve_trade_date(simulated_target(effective_trade_date()))
    return (cm, yyyymmdd) if yyyymmdd else None


def fetch_sim_price(db: Session, symbol: str) -> Optional[Dict]:
    """單檔模擬日收盤價,回傳 shape 與舊 Yahoo fetch_live_price 相同;
    查無(不在 CMoney 300 檔內)回 None,呼叫端視為代號不存在。"""
    resolved = _resolve_sim_day(db)
    if not resolved:
        return None
    cm, yyyymmdd = resolved
    price = cm.get_price(symbol, yyyymmdd)
    if not price or price.close is None:
        return None
    return {
        "close_price": price.close,
        "change_percent": price.change_percent if price.change_percent is not None else 0.0,
        "volume": price.volume if price.volume is not None else 0,
    }


def fetch_sim_market(db: Session) -> Optional[Dict]:
    """模擬日大盤:市值比重加權漲幅 proxy + 全檔均價當 close。"""
    resolved = _resolve_sim_day(db)
    if not resolved:
        return None
    cm, yyyymmdd = resolved
    change = cm.market_change(yyyymmdd)
    if change is None:
        return None
    close = db.execute(text(
        'SELECT avg(cast("收盤價" as float)) FROM raw.raw_01_price_valuation_2025 '
        "WHERE \"日期\" = :d AND \"收盤價\" <> ''"
    ), {"d": yyyymmdd}).scalar()
    return {
        "close_price": round(float(close), 2) if close is not None else 0.0,
        "change_percent": change,
    }


def fetch_sim_profile(db: Session, symbol: str) -> Optional[Dict]:
    """CMoney 目錄(raw_07)的名稱/主產業;查無回 None。"""
    cm = CMoneyDataService(db)
    if not cm.available:
        return None
    row = db.execute(text(
        'SELECT "股票名稱", "主產業" FROM raw.raw_07_industry_classification_mapping '
        'WHERE "股票代號" = :s'
    ), {"s": symbol}).first()
    if not row:
        return None
    return {"name": row[0] or None, "industry": row[1] or None}
