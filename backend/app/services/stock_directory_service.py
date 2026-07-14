"""台股代號 → 中文簡稱 / 產業 目錄。

搜尋遇到本地資料庫沒有的代號時,先用這份目錄補中文名稱與產業:
- 上市:證交所 OpenAPI(t187ap03_L)
- 上櫃:櫃買中心 OpenAPI(mopsfin_t187ap03_O)
兩份合計約 2,000 檔,記憶體快取 24 小時;來源掛掉時回 None,
由呼叫端退回 CMoney 目錄名稱,搜尋不會因此失敗。
"""
import logging
import time
from typing import Optional

import requests

logger = logging.getLogger(__name__)

_TTL_SECONDS = 86400
_cache: dict = {"loaded_at": 0.0, "by_symbol": {}}

# 證交所/櫃買 產業別代碼 → 中文(常用代碼;查不到的一律「其他」)
INDUSTRY_NAMES = {
    "01": "水泥", "02": "食品", "03": "塑膠", "04": "紡織纖維",
    "05": "電機機械", "06": "電器電纜", "08": "玻璃陶瓷", "09": "造紙",
    "10": "鋼鐵", "11": "橡膠", "12": "汽車", "14": "建材營造",
    "15": "航運", "16": "觀光餐旅", "17": "金融保險", "18": "貿易百貨",
    "19": "綜合", "20": "其他", "21": "化學", "22": "生技醫療",
    "23": "油電燃氣", "24": "半導體", "25": "電腦及週邊", "26": "光電",
    "27": "通信網路", "28": "電子零組件", "29": "電子通路", "30": "資訊服務",
    "31": "其他電子", "32": "文化創意", "33": "農業科技", "34": "電子商務",
    "35": "綠能環保", "36": "數位雲端", "37": "運動休閒", "38": "居家生活",
}

# (URL, 代號欄, 簡稱欄, 產業欄) — 上市用中文欄名、上櫃用英文欄名
_SOURCES = [
    ("https://openapi.twse.com.tw/v1/opendata/t187ap03_L",
     "公司代號", "公司簡稱", "產業別"),
    ("https://www.tpex.org.tw/openapi/v1/mopsfin_t187ap03_O",
     "SecuritiesCompanyCode", "CompanyAbbreviation", "SecuritiesIndustryCode"),
]


def _load_directory() -> dict:
    by_symbol: dict = {}
    for url, code_key, name_key, industry_key in _SOURCES:
        try:
            resp = requests.get(url, timeout=10, headers={"accept": "application/json"})
            resp.raise_for_status()
            for row in resp.json():
                code = (row.get(code_key) or "").strip()
                name = (row.get(name_key) or "").strip()
                industry_code = (row.get(industry_key) or "").strip()
                if code and name:
                    by_symbol[code] = {
                        "name": name,
                        "industry": INDUSTRY_NAMES.get(industry_code, "其他"),
                    }
        except Exception as e:
            logger.warning(f"Load TW stock directory failed ({url}): {e}")
    logger.info(f"TW stock directory loaded: {len(by_symbol)} symbols")
    return by_symbol


def lookup_tw_stock(symbol: str) -> Optional[dict]:
    """代號 → {"name": 中文簡稱, "industry": 中文產業};查不到回 None。"""
    now = time.time()
    if not _cache["by_symbol"] or now - _cache["loaded_at"] > _TTL_SECONDS:
        loaded = _load_directory()
        if loaded:
            _cache["by_symbol"] = loaded
            _cache["loaded_at"] = now
    return _cache["by_symbol"].get(symbol)
