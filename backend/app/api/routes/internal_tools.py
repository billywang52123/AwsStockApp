"""Internal endpoints for AgentCore tool Lambdas.

These endpoints query RDS directly and return structured data for the
AgentCore agent to reason over. They do NOT trigger AgentCore themselves,
preventing circular calls.

All endpoints require X-User-Id header (same auth as other APIs).
"""

from typing import List, Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.auth import get_current_user_id
from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.services.portfolio_analysis_service import PortfolioAnalysisService

router = APIRouter(prefix="/internal", tags=["Internal Tools"])


@router.get("/portfolio-raw")
def get_portfolio_raw(db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    """使用者庫存分析(規則式,不觸發 AgentCore)。"""
    service = PortfolioAnalysisService(db)
    return ApiResponse(success=True, data=service.get_analysis_raw(user_id))


@router.get("/stock-valuation")
def get_stock_valuation(
    symbols: str = Query(..., description="逗號分隔的股票代號,例如 2330,0050"),
    date: Optional[str] = Query(None, description="日期 YYYYMMDD,預設最新"),
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """行情估值:收盤、漲跌、本益比、淨值比、成交量、市值。"""
    symbol_list = [s.strip() for s in symbols.split(",") if s.strip()]
    placeholders = ",".join(f":s{i}" for i in range(len(symbol_list)))
    params = {f"s{i}": s for i, s in enumerate(symbol_list)}

    date_clause = ""
    if date:
        date_clause = 'AND TRIM("日期") = :dt'
        params["dt"] = date
    else:
        date_clause = 'AND TRIM("日期") = (SELECT MAX(TRIM("日期")) FROM raw.raw_01_price_valuation_2025)'

    sql = text(f"""
        SELECT TRIM("日期") AS date, TRIM("股票代號") AS symbol, TRIM("股票名稱") AS name,
               "收盤價" AS close_price, "漲幅(%)" AS change_pct, "成交量" AS volume,
               "總市值(億)" AS market_cap, "本益比(近四季)" AS pe_ratio,
               "股價淨值比" AS pb_ratio, "週轉率(%)" AS turnover_pct
        FROM raw.raw_01_price_valuation_2025
        WHERE TRIM("股票代號") IN ({placeholders}) {date_clause}
        ORDER BY "日期" DESC, "股票代號"
    """)
    rows = db.execute(sql, params).mappings().all()
    return ApiResponse(success=True, data=[dict(r) for r in rows])


@router.get("/institutional-flow")
def get_institutional_flow(
    symbols: str = Query(..., description="逗號分隔的股票代號"),
    date: Optional[str] = Query(None, description="日期 YYYYMMDD,預設最新"),
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """法人動向:外資/投信/自營商買賣超、持股比率。"""
    symbol_list = [s.strip() for s in symbols.split(",") if s.strip()]
    placeholders = ",".join(f":s{i}" for i in range(len(symbol_list)))
    params = {f"s{i}": s for i, s in enumerate(symbol_list)}

    date_clause = ""
    if date:
        date_clause = 'AND TRIM("日期") = :dt'
        params["dt"] = date
    else:
        date_clause = 'AND TRIM("日期") = (SELECT MAX(TRIM("日期")) FROM raw.raw_02_institutional_trading_2025)'

    sql = text(f"""
        SELECT TRIM("日期") AS date, TRIM("股票代號") AS symbol, TRIM("股票名稱") AS name,
               "外資買賣超" AS foreign_net, "投信買賣超" AS trust_net,
               "自營商買賣超" AS dealer_net, "買賣超合計" AS total_net,
               "外資持股比率(%)" AS foreign_hold_pct, "法人持股比率(%)" AS inst_hold_pct
        FROM raw.raw_02_institutional_trading_2025
        WHERE TRIM("股票代號") IN ({placeholders}) {date_clause}
        ORDER BY "日期" DESC, "股票代號"
    """)
    rows = db.execute(sql, params).mappings().all()
    return ApiResponse(success=True, data=[dict(r) for r in rows])


@router.get("/stock-momentum")
def get_stock_momentum(
    symbols: str = Query(..., description="逗號分隔的股票代號"),
    date: Optional[str] = Query(None, description="日期 YYYYMMDD,預設最新"),
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """動能指標:創新高、連漲、乖離年線、近20日漲跌幅。"""
    symbol_list = [s.strip() for s in symbols.split(",") if s.strip()]
    placeholders = ",".join(f":s{i}" for i in range(len(symbol_list)))
    params = {f"s{i}": s for i, s in enumerate(symbol_list)}

    date_clause = ""
    if date:
        date_clause = 'AND TRIM("日期") = :dt'
        params["dt"] = date
    else:
        date_clause = 'AND TRIM("日期") = (SELECT MAX(TRIM("日期")) FROM raw.raw_04_distance_from_high_low_momentum_2025)'

    sql = text(f"""
        SELECT TRIM("日期") AS date, TRIM("股票代號") AS symbol, TRIM("股票名稱") AS name,
               "股價創歷史新高" AS historical_high, "股價創N日新高" AS n_day_high,
               "股價連N日漲" AS consecutive_up, "近5日漲跌幅%" AS change_5d,
               "近20日漲跌幅%" AS change_20d, "近60日漲跌幅%" AS change_60d,
               "股價乖離月線(%)" AS dev_monthly, "股價乖離季線(%)" AS dev_quarterly,
               "股價乖離年線(%)" AS dev_yearly, "今年以來漲跌幅%" AS ytd_change
        FROM raw.raw_04_distance_from_high_low_momentum_2025
        WHERE TRIM("股票代號") IN ({placeholders}) {date_clause}
        ORDER BY "日期" DESC, "股票代號"
    """)
    rows = db.execute(sql, params).mappings().all()
    return ApiResponse(success=True, data=[dict(r) for r in rows])


@router.get("/forum-sentiment")
def get_forum_sentiment(
    symbols: str = Query(..., description="逗號分隔的股票代號"),
    date: Optional[str] = Query(None, description="日期 YYYYMMDD,預設最新"),
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """社群討論(股票同學會):發文數、看多/看空/中性。"""
    symbol_list = [s.strip() for s in symbols.split(",") if s.strip()]
    placeholders = ",".join(f":s{i}" for i in range(len(symbol_list)))
    params = {f"s{i}": s for i, s in enumerate(symbol_list)}

    date_clause = ""
    if date:
        date_clause = 'AND TRIM("日期") = :dt'
        params["dt"] = date
    else:
        date_clause = 'AND TRIM("日期") = (SELECT MAX(TRIM("日期")) FROM raw.raw_10_forum_posts_replies_daily_stats_2025)'

    sql = text(f"""
        SELECT TRIM("日期") AS date, TRIM("股票代號") AS symbol, TRIM("股票名稱") AS name,
               "發文則數" AS posts, "發文人數" AS posters,
               "看多發文" AS bullish, "看空發文" AS bearish, "中性發文" AS neutral,
               "回文則數" AS replies, "回文人數" AS repliers
        FROM raw.raw_10_forum_posts_replies_daily_stats_2025
        WHERE TRIM("股票代號") IN ({placeholders}) {date_clause}
        ORDER BY "日期" DESC, "股票代號"
    """)
    rows = db.execute(sql, params).mappings().all()
    return ApiResponse(success=True, data=[dict(r) for r in rows])


@router.get("/stock-returns")
def get_stock_returns(
    symbols: str = Query(..., description="逗號分隔的股票代號"),
    date: Optional[str] = Query(None, description="日期 YYYYMMDD,預設最新"),
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """報酬率:日/週/月/季/年報酬、殖利率。"""
    symbol_list = [s.strip() for s in symbols.split(",") if s.strip()]
    placeholders = ",".join(f":s{i}" for i in range(len(symbol_list)))
    params = {f"s{i}": s for i, s in enumerate(symbol_list)}

    date_clause = ""
    if date:
        date_clause = 'AND TRIM("日期") = :dt'
        params["dt"] = date
    else:
        date_clause = 'AND TRIM("日期") = (SELECT MAX(TRIM("日期")) FROM raw.raw_03_return_rate_2025)'

    sql = text(f"""
        SELECT TRIM("日期") AS date, TRIM("股票代號") AS symbol, TRIM("股票名稱") AS name,
               "日報酬率(%)" AS return_daily, "週報酬率(%)" AS return_weekly,
               "月報酬率(%)" AS return_monthly, "季報酬率(%)" AS return_quarterly,
               "年報酬率(%)" AS return_yearly, "殖利率(%)" AS dividend_yield
        FROM raw.raw_03_return_rate_2025
        WHERE TRIM("股票代號") IN ({placeholders}) {date_clause}
        ORDER BY "日期" DESC, "股票代號"
    """)
    rows = db.execute(sql, params).mappings().all()
    return ApiResponse(success=True, data=[dict(r) for r in rows])
