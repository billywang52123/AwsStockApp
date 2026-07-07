import sys
from pathlib import Path

# Add backend directory to path so imports work correctly
backend_dir = Path(__file__).resolve().parent.parent
sys.path.append(str(backend_dir))

from app.calculators.anxiety_score_calculator import AnxietyScoreCalculator, AnxietyScoreInput

def test_stable_anxiety_conditions():
    calculator = AnxietyScoreCalculator()
    # Positive return, stable market
    input_data = AnxietyScoreInput(
        portfolio_change_percent=1.5,
        market_change_percent=0.5,
        max_drop_percent=0.0
    )
    result = calculator.calculate(input_data)
    assert result.score == 30
    assert result.level == "穩定"
    assert result.risk_label == "低風險"

def test_mild_market_pullback():
    calculator = AnxietyScoreCalculator()
    # Moderate average drop, average drop max 3%
    input_data = AnxietyScoreInput(
        portfolio_change_percent=-1.5, # average drop: -1.5% (+25)
        market_change_percent=-0.5,    # market drop: -0.5% (+5)
        max_drop_percent=-2.5          # max drop: -2.5% (+15)
        # diff = -1.5 - (-0.5) = -1.0 (+0, since it is not < -1.0)
    )
    # expected score: 30 + 25 + 15 + 5 = 75
    result = calculator.calculate(input_data)
    assert result.score == 75
    assert result.level == "焦慮偏高"

def test_high_anxiety_market_correction():
    calculator = AnxietyScoreCalculator()
    input_data = AnxietyScoreInput(
        portfolio_change_percent=-4.0, # average drop: -4.0% (+40)
        market_change_percent=-2.5,    # market drop: -2.5% (+20)
        max_drop_percent=-6.0          # max drop: -6.0% (+25)
        # diff = -4.0 - (-2.5) = -1.5 (+10)
    )
    # expected score: 30 + 40 + 25 + 20 + 10 = 125 -> capped at 100
    result = calculator.calculate(input_data)
    assert result.score == 100
    assert result.level == "需要冷靜一下"
