"""Gateway tool:讀後端規則式庫存分析(市值/風險分數/產業曝險/持股/風險提醒)。"""
from backend_client import call_backend_tool  # Lambda 打包後是平面模組


def handler(event, context):
    return call_backend_tool("/api/portfolio/analysis", event)
