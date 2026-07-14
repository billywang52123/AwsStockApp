"""測試共用設定。

模擬時鐘 `_override` 是模組層全域,且 app 匯入時會從『真實 DB』載入持久化的
覆寫值(見 main.py 啟動載入)。為避免真實 DB 若殘留覆寫值污染測試,
每個測試前後都把記憶體覆寫清成 None,確保測試以「無覆寫」的真實時序執行。
需要測覆寫行為的測試自行 set_override。
"""
import pytest

from app.services import sim_clock


@pytest.fixture(autouse=True)
def _reset_sim_clock():
    sim_clock._override = None
    yield
    sim_clock._override = None
