"""Deterministic candidate selection for the first personalized-push demo."""

from __future__ import annotations

import math
import re
from dataclasses import asdict, dataclass
from typing import Any

_MISSING_VALUES = {"", "-", "--", "—", "N/A", "NA", "NULL", "NONE"}


def normalize_symbol(value: Any) -> str:
    symbol = str(value or "").strip().upper()
    for suffix in (".TW", ".TWO"):
        if symbol.endswith(suffix):
            return symbol[: -len(suffix)]
    return symbol


def parse_number(value: Any) -> float | None:
    if value is None:
        return None
    text = str(value).strip().upper().replace("−", "-")
    if text in _MISSING_VALUES:
        return None
    negative_parentheses = text.startswith("(") and text.endswith(")")
    text = text.replace(",", "").replace("%", "")
    text = re.sub(r"[^0-9+\-.]", "", text)
    if text in _MISSING_VALUES or text in {"+", "-", "."}:
        return None
    try:
        number = float(text)
    except ValueError:
        return None
    if negative_parentheses:
        number = -abs(number)
    return number if math.isfinite(number) else None


@dataclass(frozen=True)
class PushCandidate:
    user_id: str
    demo_date: str
    symbol: str
    stock_name: str
    close_price: float
    change_percent: float
    signal_type: str = "large_price_move"

    def facts(self) -> dict[str, Any]:
        return {
            "demo_date": self.demo_date,
            "symbol": self.symbol,
            "stock_name": self.stock_name,
            "close_price": round(self.close_price, 2),
            "change_percent": round(self.change_percent, 2),
            "signal_type": self.signal_type,
        }

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)


def select_candidate(
    *,
    user_id: str,
    demo_date: str,
    holdings: list[dict[str, Any]],
    market_rows: list[dict[str, Any]],
    threshold_percent: float,
) -> PushCandidate | None:
    market_by_symbol: dict[str, dict[str, Any]] = {}
    for row in market_rows:
        symbol = normalize_symbol(row.get("symbol"))
        if symbol:
            market_by_symbol[symbol] = row

    candidates: list[PushCandidate] = []
    for holding in holdings:
        symbol = normalize_symbol(holding.get("symbol"))
        row = market_by_symbol.get(symbol)
        if not row:
            continue
        close_price = parse_number(row.get("close_price"))
        change_percent = parse_number(row.get("change_percent"))
        if close_price is None or change_percent is None:
            continue
        if abs(change_percent) < threshold_percent:
            continue
        candidates.append(
            PushCandidate(
                user_id=user_id,
                demo_date=demo_date,
                symbol=symbol,
                stock_name=str(row.get("stock_name") or symbol).strip(),
                close_price=close_price,
                change_percent=change_percent,
            )
        )

    if not candidates:
        return None
    return max(candidates, key=lambda candidate: abs(candidate.change_percent))
