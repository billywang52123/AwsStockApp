from dataclasses import dataclass

@dataclass
class AnxietyScoreInput:
    portfolio_change_percent: float
    market_change_percent: float
    max_drop_percent: float

@dataclass
class AnxietyScoreOutput:
    score: int
    level: str
    risk_label: str

class AnxietyScoreCalculator:
    def calculate(self, data: AnxietyScoreInput) -> AnxietyScoreOutput:
        score = 30

        avg = data.portfolio_change_percent
        market = data.market_change_percent
        max_drop = data.max_drop_percent

        # 1. Portfolio Average Drop
        if avg < -3.0:
            score += 40
        elif avg < -1.0:
            score += 25
        elif avg < 0.0:
            score += 10

        # 2. Max Drop
        if max_drop < -5.0:
            score += 25
        elif max_drop < -2.0:
            score += 15
        elif max_drop < 0.0:
            score += 5

        # 3. Market Drop
        if market < -2.0:
            score += 20
        elif market < -1.0:
            score += 10
        elif market < 0.0:
            score += 5

        # 4. Underperforming Market
        diff = avg - market
        if diff < -3.0:
            score += 20
        elif diff < -1.0:
            score += 10

        # Boundary checks
        score = max(0, min(100, score))

        return AnxietyScoreOutput(
            score=score,
            level=self._get_level(score),
            risk_label=self._get_risk_label(score)
        )

    def _get_level(self, score: int) -> str:
        if score <= 30:
            return "穩定"
        if score <= 50:
            return "有點波動"
        if score <= 70:
            return "有點緊張"
        if score <= 85:
            return "焦慮偏高"
        return "需要冷靜一下"

    def _get_risk_label(self, score: int) -> str:
        """Returns a risk classification label distinct from the emotional level."""
        if score <= 30:
            return "低風險"
        if score <= 50:
            return "中低風險"
        if score <= 70:
            return "中風險"
        if score <= 85:
            return "中高風險"
        return "高風險"
