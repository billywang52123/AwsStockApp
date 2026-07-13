"""Gateway tool:讀後端個人化大盤比較。"""
from backend_client import call_backend_tool


def handler(event, context):
    return call_backend_tool("/api/market/compare", event)
