"""模擬時鐘:覆寫全 App 的「今天」以便展示不同的模擬交易日。

專案為 CMoney 2025 模擬資料,交易日 = 今天 − 1 年。展示時常需要跳到
別的日期看不同盤況,這裡提供一個可覆寫的「有效今天」:

- 覆寫值存在 app_settings 表(key=effective_today,重啟不掉),
  並在啟動時載入到模組層 `_override`,供 `effective_trade_date()` 無 session 快速讀取。
- 未設定時回 None,`effective_trade_date()` 走真實系統時間 + 14:30 換日規則。

單一 uvicorn process,in-memory 快取即為權威值;set/clear 會同步寫回 DB。
"""
import logging
from datetime import date
from typing import Optional

from sqlalchemy import text
from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)

SETTING_KEY = "effective_today"

_override: Optional[date] = None
_loaded: bool = False


def _parse(value: Optional[str]) -> Optional[date]:
    if not value:
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        logger.warning("sim_clock: 無法解析 override 值 %r,忽略", value)
        return None


def get_override() -> Optional[date]:
    """目前的模擬今天覆寫(None = 用真實時間)。無 session、供熱路徑呼叫。"""
    return _override


def load_from_db(db: Session) -> Optional[date]:
    """啟動時把持久化的覆寫值載入記憶體。DB 無此表/連線失敗都安靜退回 None。"""
    global _override, _loaded
    try:
        row = db.execute(
            text("SELECT value FROM app_settings WHERE key = :k"),
            {"k": SETTING_KEY},
        ).first()
        _override = _parse(row[0]) if row else None
    except Exception:
        db.rollback()
        _override = None
    _loaded = True
    if _override:
        logger.info("sim_clock: 載入模擬今天覆寫 = %s", _override)
    return _override


def set_override(db: Session, value: date) -> date:
    """設定模擬今天並持久化;回傳設定後的值。"""
    global _override
    from app.models.app_setting import AppSetting

    setting = db.get(AppSetting, SETTING_KEY)
    if setting:
        setting.value = value.isoformat()
    else:
        db.add(AppSetting(key=SETTING_KEY, value=value.isoformat()))
    db.commit()
    _override = value
    logger.info("sim_clock: 模擬今天覆寫設為 %s", value)
    return value


def clear_override(db: Session) -> None:
    """清除覆寫,恢復用真實系統時間。"""
    global _override
    from app.models.app_setting import AppSetting

    setting = db.get(AppSetting, SETTING_KEY)
    if setting:
        db.delete(setting)
        db.commit()
    _override = None
    logger.info("sim_clock: 已清除模擬今天覆寫,恢復真實時間")
