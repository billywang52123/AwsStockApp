"""投資風格問卷、持股習慣辨識、歷史快照與 AI prompt context。"""

import json
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

from sqlalchemy import and_, select
from sqlalchemy.orm import Session

from app.models.holding_activity import HoldingActivityModel
from app.models.investment_profile import (
    InvestmentHabitSnapshotModel,
    InvestmentProfileModel,
)
from app.models.portfolio import PortfolioItem
from app.repositories.repositories import StockRepository


QUESTIONNAIRE_VERSION = 1
PROMPT_VERSION = "investment-context-v1"
TECH_KEYWORDS = ("半導體", "IC", "電子", "光電", "通信", "電腦", "科技")


QUESTIONNAIRE = [
    {
        "id": "investment_horizon",
        "title": "你通常用多長的時間看一筆投資？",
        "subtitle": "用來調整分析中短線波動與長期脈絡的比重。",
        "options": [
            {"code": "short", "label": "數天到三個月", "description": "較關注近期價格與事件"},
            {"code": "medium", "label": "三個月至兩年", "description": "兼顧趨勢與基本面"},
            {"code": "long", "label": "兩年以上", "description": "較重視長期結構與產業"},
        ],
    },
    {
        "id": "risk_tolerance",
        "title": "遇到明顯波動時，你通常能接受到什麼程度？",
        "subtitle": "不是測膽量，而是讓風險說明符合你的承受度。",
        "options": [
            {"code": "conservative", "label": "希望波動小一點", "description": "先看下行風險與穩定性"},
            {"code": "balanced", "label": "可以接受適度波動", "description": "同時衡量風險與成長"},
            {"code": "aggressive", "label": "可以接受較大波動", "description": "願意承受波動換取成長空間"},
        ],
    },
    {
        "id": "decision_style",
        "title": "你做判斷時最常依靠什麼？",
        "subtitle": "決定分析要多呈現公式、事件背景或白話脈絡。",
        "options": [
            {"code": "data_driven", "label": "數據與可驗證資料", "description": "偏好公式、比較與來源"},
            {"code": "news_driven", "label": "新聞與產業事件", "description": "偏好事件脈絡與影響路徑"},
            {"code": "intuitive", "label": "整體感受與經驗", "description": "偏好先看白話結論再展開"},
        ],
    },
    {
        "id": "trading_frequency",
        "title": "你大約多久會調整一次持股？",
        "subtitle": "與實際異動紀錄分開保存，後續可以比較偏好與行為。",
        "options": [
            {"code": "low", "label": "很少調整", "description": "一年數次或更少"},
            {"code": "medium", "label": "偶爾調整", "description": "每月到每季"},
            {"code": "high", "label": "經常調整", "description": "每週或更頻繁"},
        ],
    },
    {
        "id": "drawdown_response",
        "title": "持股明顯下跌時，你第一個反應比較接近哪一種？",
        "subtitle": "用來安排安撫、查證與風險揭露的順序。",
        "options": [
            {"code": "hold", "label": "先維持原計畫", "description": "不因單日波動立刻改變"},
            {"code": "review", "label": "先重新查資料", "description": "確認原因與原本假設"},
            {"code": "reduce", "label": "先降低曝險感", "description": "對下跌較敏感，需要先看風險"},
        ],
    },
    {
        "id": "primary_goal",
        "title": "你目前最主要的投資目標是什麼？",
        "subtitle": "只用來調整分析視角，不會產生交易指令。",
        "options": [
            {"code": "preservation", "label": "資產穩定", "description": "優先理解風險與回撤"},
            {"code": "income", "label": "現金流與收益", "description": "較關注穩定性與持續性"},
            {"code": "growth", "label": "長期成長", "description": "較關注產業與成長結構"},
            {"code": "learning", "label": "學習與建立方法", "description": "較需要名詞、公式與來源"},
        ],
    },
]


PREFERENCE_STYLES = {
    "unclassified": ("尚未完成問卷", "目前先用中性方式呈現資料；完成問卷後會調整分析層次。"),
    "conservative_guardian": ("穩健守護型", "重視下行風險、資產穩定與可承受波動。"),
    "steady_balancer": ("穩健平衡型", "會同時比較風險與成長，不只看單一訊號。"),
    "growth_explorer": ("長期成長型", "願意承受適度波動，較重視產業與長期結構。"),
    "active_opportunist": ("主動觀察型", "關注近期變化與相對強弱，但分析仍以資料為邊界。"),
}

OBSERVED_STYLES = {
    **PREFERENCE_STYLES,
    "unclassified": ("尚待觀察", "持股或問卷資料不足，暫不替你貼上風格標籤。"),
    "focused_growth": ("集中成長型", "目前部位集中度較高，單一標的或產業對整體影響較明顯。"),
    "diversified_balancer": ("分散平衡型", "目前持股分散度較高，單一標的對整體影響相對有限。"),
    "active_opportunist": ("主動調整型", "近期持股異動較頻繁，風格呈現較高的主動調整特徵。"),
}

HABITS = {
    "insufficient_data": ("資料累積中", "目前持股或異動資料不足，後續更新會逐步形成習慣輪廓。"),
    "focused_holder": ("集中持有", "目前資金集中在少數標的，個股波動對整體感受影響較大。"),
    "diversified_holder": ("分散配置", "目前持股與產業分散度較高，風險來源較不集中。"),
    "active_adjuster": ("近期常調整", "近 30 日持股異動較頻繁，分析會額外提示風格與集中度變化。"),
    "balanced_builder": ("均衡建立中", "持股數量與集中度介於兩端，仍在形成穩定配置習慣。"),
}


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class InvestmentProfileService:
    def __init__(self, db: Session):
        self.db = db

    # ── 問卷與偏好風格 ──────────────────────────────────────

    def get_questionnaire(self, user_id: str) -> dict:
        row = self._profile_row(user_id)
        answers = json.loads(row.answers_json) if row else None
        return {
            "version": QUESTIONNAIRE_VERSION,
            "completed": row is not None,
            "current_answers": answers,
            "questions": QUESTIONNAIRE,
        }

    def submit_questionnaire(self, user_id: str, answers: Dict[str, str]) -> dict:
        dimensions = self._score_answers(answers)
        code = self._preference_style_code(dimensions)
        label, summary = PREFERENCE_STYLES[code]
        row = self._profile_row(user_id)
        if row is None:
            row = InvestmentProfileModel(
                user_id=user_id,
                questionnaire_version=QUESTIONNAIRE_VERSION,
                answers_json=json.dumps(answers, ensure_ascii=False),
                preference_style_code=code,
                preference_style_label=label,
                preference_style_summary=summary,
                dimension_scores_json=json.dumps(dimensions, ensure_ascii=False),
                completed_at=_utcnow(),
                updated_at=_utcnow(),
            )
            self.db.add(row)
        else:
            row.questionnaire_version = QUESTIONNAIRE_VERSION
            row.answers_json = json.dumps(answers, ensure_ascii=False)
            row.preference_style_code = code
            row.preference_style_label = label
            row.preference_style_summary = summary
            row.dimension_scores_json = json.dumps(dimensions, ensure_ascii=False)
            row.updated_at = _utcnow()
        self.db.flush()
        self.capture_habit_snapshot(user_id, "questionnaire")
        return self.get_profile(user_id)

    def _score_answers(self, answers: Dict[str, str]) -> dict:
        risk = {"conservative": 20, "balanced": 50, "aggressive": 85}[answers["risk_tolerance"]]
        activity = {"low": 20, "medium": 50, "high": 85}[answers["trading_frequency"]]
        horizon = {"short": 20, "medium": 55, "long": 90}[answers["investment_horizon"]]
        evidence = {"intuitive": 35, "news_driven": 60, "data_driven": 90}[answers["decision_style"]]
        if answers["primary_goal"] == "preservation":
            risk = max(0, risk - 10)
        elif answers["primary_goal"] == "growth":
            risk = min(100, risk + 8)
            horizon = min(100, horizon + 8)
        elif answers["primary_goal"] == "learning":
            evidence = min(100, evidence + 8)
        if answers["drawdown_response"] == "reduce":
            risk = max(0, risk - 8)
        elif answers["drawdown_response"] == "hold":
            horizon = min(100, horizon + 5)
        return {"risk": risk, "activity": activity, "horizon": horizon, "evidence": evidence}

    @staticmethod
    def _preference_style_code(dimensions: dict) -> str:
        if dimensions["risk"] <= 32:
            return "conservative_guardian"
        if dimensions["activity"] >= 70 and dimensions["horizon"] <= 55:
            return "active_opportunist"
        if dimensions["risk"] >= 65 or dimensions["horizon"] >= 75:
            return "growth_explorer"
        return "steady_balancer"

    # ── 實際持股習慣 ────────────────────────────────────────

    def portfolio_metrics(self, user_id: str) -> dict:
        lots = list(self.db.scalars(select(PortfolioItem).where(and_(
            PortfolioItem.user_id == user_id,
            (PortfolioItem.status.is_(None)) | (PortfolioItem.status != "exited"),
            PortfolioItem.shares > 0,
        ))).all())
        by_symbol: Dict[str, list] = {}
        for lot in lots:
            by_symbol.setdefault(lot.symbol, []).append(lot)

        stock_repo = StockRepository(self.db)
        positions = []
        complete_cost = 0
        for symbol, symbol_lots in by_symbol.items():
            shares = sum(l.shares or 0 for l in symbol_lots)
            stock = stock_repo.get_stock(symbol)
            price = stock_repo.get_daily_price(symbol)
            valid_costs = [(l.shares or 0, float(l.cost_price)) for l in symbol_lots if l.cost_price]
            avg_cost = (
                sum(s * c for s, c in valid_costs) / sum(s for s, _ in valid_costs)
                if valid_costs and sum(s for s, _ in valid_costs) > 0 else 0.0
            )
            if all(l.cost_price is not None for l in symbol_lots):
                complete_cost += 1
            close = float(price.close_price) if price and price.close_price is not None else avg_cost
            value = max(close * shares, 0.0)
            positions.append({
                "symbol": symbol,
                "industry": (stock.industry if stock and stock.industry else "其他"),
                "shares": shares,
                "value": value,
            })

        # 缺價格/成本時以股數作為暫時權重，至少能反映集中度變化。
        total = sum(p["value"] for p in positions)
        if total <= 0:
            total = float(sum(p["shares"] for p in positions))
            for p in positions:
                p["value"] = float(p["shares"])
        weights = sorted(
            [(p["value"] / total * 100.0 if total > 0 else 0.0) for p in positions],
            reverse=True,
        )
        tech_weight = sum(
            p["value"] / total * 100.0
            for p in positions
            if total > 0 and any(k in p["industry"] for k in TECH_KEYWORDS)
        )

        cutoff = _utcnow() - timedelta(days=30)
        activities = list(self.db.scalars(select(HoldingActivityModel).where(and_(
            HoldingActivityModel.user_id == user_id,
            HoldingActivityModel.created_at >= cutoff,
        ))).all())
        return {
            "holding_count": len(positions),
            "industry_count": len({p["industry"] for p in positions}),
            "top_holding_weight": round(weights[0] if weights else 0.0, 1),
            "top3_weight": round(sum(weights[:3]), 1),
            "tech_weight": round(tech_weight, 1),
            "activity_count_30d": len(activities),
            "buy_count_30d": sum(1 for a in activities if a.activity_type == "buy"),
            "sell_count_30d": sum(1 for a in activities if a.activity_type in ("sell", "exit")),
            "cost_completion_ratio": round(complete_cost / len(positions) * 100.0, 1) if positions else 0.0,
        }

    @staticmethod
    def _habit(metrics: dict) -> dict:
        if metrics["holding_count"] == 0:
            code = "insufficient_data"
        elif metrics["activity_count_30d"] >= 8:
            code = "active_adjuster"
        elif metrics["holding_count"] <= 2 or metrics["top_holding_weight"] >= 60:
            code = "focused_holder"
        elif metrics["holding_count"] >= 5 and metrics["top_holding_weight"] <= 35:
            code = "diversified_holder"
        else:
            code = "balanced_builder"
        label, summary = HABITS[code]
        return {"code": code, "label": label, "summary": summary}

    @staticmethod
    def _observed_style(preference_code: str, metrics: dict) -> dict:
        if metrics["holding_count"] == 0:
            code = preference_code if preference_code != "unclassified" else "unclassified"
        elif metrics["activity_count_30d"] >= 8:
            code = "active_opportunist"
        elif metrics["top_holding_weight"] >= 60 or metrics["tech_weight"] >= 75:
            code = "focused_growth"
        elif metrics["holding_count"] >= 5 and metrics["top_holding_weight"] <= 35:
            code = "diversified_balancer"
        else:
            code = preference_code if preference_code != "unclassified" else "unclassified"
        label, summary = OBSERVED_STYLES[code]
        return {"code": code, "label": label, "summary": summary}

    # ── Profile / 歷史 ─────────────────────────────────────

    def get_profile(self, user_id: str) -> dict:
        row = self._profile_row(user_id)
        preference = self._preference(row)
        dimensions = json.loads(row.dimension_scores_json) if row else {
            "risk": 50, "activity": 50, "horizon": 50, "evidence": 50,
        }
        metrics = self.portfolio_metrics(user_id)
        observed = self._observed_style(preference["code"], metrics)
        habit = self._habit(metrics)
        latest = self._latest_snapshot(user_id)
        return {
            "questionnaire_completed": row is not None,
            "questionnaire_version": row.questionnaire_version if row else QUESTIONNAIRE_VERSION,
            "preference_style": preference,
            "observed_style": observed,
            "investment_habit": habit,
            "style_dimensions": dimensions,
            "portfolio_metrics": metrics,
            "latest_change": latest.change_summary if latest else "尚未建立持股習慣歷史。",
            "updated_at": row.updated_at if row else None,
            "prompt_version": PROMPT_VERSION,
        }

    def capture_habit_snapshot(self, user_id: str, trigger: str) -> dict:
        row = self._profile_row(user_id)
        preference = self._preference(row)
        metrics = self.portfolio_metrics(user_id)
        observed = self._observed_style(preference["code"], metrics)
        habit = self._habit(metrics)
        previous = self._latest_snapshot(user_id)
        change_summary = self._change_summary(previous, observed, metrics)
        snapshot = InvestmentHabitSnapshotModel(
            user_id=user_id,
            trigger=trigger,
            preference_style_code=preference["code"],
            observed_style_code=observed["code"],
            observed_style_label=observed["label"],
            observed_style_summary=observed["summary"],
            habit_code=habit["code"],
            habit_label=habit["label"],
            habit_summary=habit["summary"],
            metrics_json=json.dumps(metrics, ensure_ascii=False),
            change_summary=change_summary,
        )
        self.db.add(snapshot)
        self.db.flush()
        return self._snapshot_dict(snapshot)

    def history(self, user_id: str, limit: int = 30) -> List[dict]:
        rows = self.db.scalars(
            select(InvestmentHabitSnapshotModel)
            .where(InvestmentHabitSnapshotModel.user_id == user_id)
            .order_by(InvestmentHabitSnapshotModel.created_at.desc(), InvestmentHabitSnapshotModel.id.desc())
            .limit(limit)
        ).all()
        return [self._snapshot_dict(row) for row in rows]

    def _change_summary(self, previous, observed: dict, metrics: dict) -> str:
        if previous is None:
            return f"建立第一筆習慣快照：{observed['label']}，目前持有 {metrics['holding_count']} 檔。"
        old = json.loads(previous.metrics_json)
        parts = []
        if previous.observed_style_code != observed["code"]:
            parts.append(f"觀察風格由「{previous.observed_style_label}」轉為「{observed['label']}」")
        holding_delta = metrics["holding_count"] - int(old.get("holding_count", 0))
        if holding_delta > 0:
            parts.append(f"持股增加 {holding_delta} 檔")
        elif holding_delta < 0:
            parts.append(f"持股減少 {abs(holding_delta)} 檔")
        concentration_delta = metrics["top_holding_weight"] - float(old.get("top_holding_weight", 0))
        if concentration_delta >= 5:
            parts.append(f"最大持股集中度上升 {concentration_delta:.1f} 個百分點")
        elif concentration_delta <= -5:
            parts.append(f"最大持股集中度下降 {abs(concentration_delta):.1f} 個百分點")
        return "；".join(parts) + "。" if parts else "本次更新後，整體風格沒有明顯轉變。"

    # ── Prompt context / 深度分析 ───────────────────────────

    def prompt_context(self, user_id: str) -> dict:
        profile = self.get_profile(user_id)
        style_code = profile["preference_style"]["code"]
        principles = {
            "conservative_guardian": [
                "先說明下行風險與波動來源，再說可能的正向條件。",
                "避免急迫語氣，用可承受波動與集中度幫助理解。",
            ],
            "steady_balancer": [
                "同時列出支持與反對目前判斷的證據。",
                "區分短線價格、產業結構與個人持倉位置。",
            ],
            "growth_explorer": [
                "短線波動之外，補充產業與長期結構，但不得把成長敘事當成保證。",
                "清楚標示哪些是事實、哪些是推論。",
            ],
            "active_opportunist": [
                "加強近期價格、相對大盤與事件變化，但不提供交易操作方向。",
                "提醒頻繁調整可能改變集中度與風格。",
            ],
            "unclassified": [
                "先用中性、教學式語氣呈現事實與公式。",
                "資料不足時明說不知道，不替使用者貼標籤。",
            ],
        }[style_code]
        habit = profile["investment_habit"]
        if habit["code"] == "focused_holder":
            principles.append("量化單一持股與產業集中度，說明它如何放大整體波動。")
        elif habit["code"] == "diversified_holder":
            principles.append("優先說明個股對整體組合的貢獻，不放大單一標的波動。")
        elif habit["code"] == "active_adjuster":
            principles.append("比較近期快照，指出風格變化，不把頻繁異動解讀為對錯。")

        metrics = profile["portfolio_metrics"]
        prompt_text = (
            f"[使用者投資脈絡 {PROMPT_VERSION}]\n"
            f"問卷偏好：{profile['preference_style']['label']}－{profile['preference_style']['summary']}\n"
            f"持股觀察：{profile['observed_style']['label']}－{profile['observed_style']['summary']}\n"
            f"投資習慣：{habit['label']}－{habit['summary']}\n"
            f"組合事實：持股 {metrics['holding_count']} 檔、產業 {metrics['industry_count']} 類、"
            f"最大持股 {metrics['top_holding_weight']:.1f}%、科技類 {metrics['tech_weight']:.1f}%、"
            f"近 30 日異動 {metrics['activity_count_30d']} 次。\n"
            "個人化寫作原則：\n- " + "\n- ".join(principles) + "\n"
            "共同邊界：只使用提供的市場與持股資料；標明事實、推論與未知；"
            "不預測漲跌、不承諾報酬、不提供任何交易操作方向。"
        )
        return {
            "prompt_version": PROMPT_VERSION,
            "preference_style": profile["preference_style"],
            "observed_style": profile["observed_style"],
            "investment_habit": habit,
            "applied_principles": principles,
            "portfolio_facts": metrics,
            "prompt_text": prompt_text,
        }

    def personalized_stock_analysis(
        self, user_id: str, *, symbol: str, name: str, industry: str,
        stock_change: float, market_change: float, data_date: str,
    ) -> dict:
        context = self.prompt_context(user_id)
        profile = self.get_profile(user_id)
        style = profile["preference_style"]
        observed = profile["observed_style"]
        habit = profile["investment_habit"]
        metrics = profile["portfolio_metrics"]
        relative = stock_change - market_change

        style_texts = {
            "conservative_guardian": f"對偏好穩定的你，先看 {name} 的波動是否會放大整體回撤，而不是只看單日方向。",
            "steady_balancer": f"對你的平衡取向，需要把 {name} 的短線價格、相對大盤與持股位置放在一起看。",
            "growth_explorer": f"對長期成長取向，單日 {stock_change:+.2f}% 只是短線訊號，還要和 {industry} 的長期結構分開判讀。",
            "active_opportunist": f"對偏好近期變化的你，{name} 相對大盤 {relative:+.2f} 個百分點是較有辨識度的短線資料。",
            "unclassified": f"尚未完成問卷，因此先以中性方式拆解 {name} 的價格、大盤與持股資料。",
        }
        habit_text = (
            f"目前最大持股占比 {metrics['top_holding_weight']:.1f}%、科技類占比 {metrics['tech_weight']:.1f}%；"
            f"你的實際習慣被辨識為「{habit['label']}」。{habit['summary']}"
        )
        market_text = (
            f"資料日 {data_date}：{name} {stock_change:+.2f}%、大盤 {market_change:+.2f}%、"
            f"相對差 {relative:+.2f} 個百分點。這些是現況資料，不代表下一交易日方向。"
        )
        return {
            "prompt_version": PROMPT_VERSION,
            "preference_style": style,
            "observed_style": observed,
            "investment_habit": habit,
            "title": f"以你的「{style['label']}」視角補充",
            "summary": style_texts[style["code"]],
            "sections": [
                {"key": "style", "title": "從問卷偏好看", "text": style_texts[style["code"]]},
                {"key": "habit", "title": "從實際持股習慣看", "text": habit_text},
                {"key": "market", "title": "和市場資料合併看", "text": market_text},
            ],
            "observation_points": context["applied_principles"],
            "data_date": data_date,
        }

    # ── helpers ──────────────────────────────────────────────

    def _profile_row(self, user_id: str) -> Optional[InvestmentProfileModel]:
        return self.db.get(InvestmentProfileModel, user_id)

    @staticmethod
    def _preference(row: Optional[InvestmentProfileModel]) -> dict:
        if row:
            return {
                "code": row.preference_style_code,
                "label": row.preference_style_label,
                "summary": row.preference_style_summary,
            }
        label, summary = PREFERENCE_STYLES["unclassified"]
        return {"code": "unclassified", "label": label, "summary": summary}

    def _latest_snapshot(self, user_id: str):
        return self.db.scalars(
            select(InvestmentHabitSnapshotModel)
            .where(InvestmentHabitSnapshotModel.user_id == user_id)
            .order_by(InvestmentHabitSnapshotModel.created_at.desc(), InvestmentHabitSnapshotModel.id.desc())
            .limit(1)
        ).first()

    @staticmethod
    def _snapshot_dict(row: InvestmentHabitSnapshotModel) -> dict:
        return {
            "id": row.id,
            "trigger": row.trigger,
            "preference_style_code": row.preference_style_code,
            "observed_style": {
                "code": row.observed_style_code,
                "label": row.observed_style_label,
                "summary": row.observed_style_summary,
            },
            "investment_habit": {
                "code": row.habit_code,
                "label": row.habit_label,
                "summary": row.habit_summary,
            },
            "portfolio_metrics": json.loads(row.metrics_json),
            "change_summary": row.change_summary,
            "created_at": row.created_at,
        }
