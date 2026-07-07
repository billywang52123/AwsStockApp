import sys
from pathlib import Path

# Add backend directory to path so imports work correctly
backend_dir = Path(__file__).resolve().parent.parent
sys.path.append(str(backend_dir))

from app.calculators.card_draw_engine import CardDrawEngine

def test_card_draw_by_score():
    engine = CardDrawEngine()
    
    # Tier 1: <= 30
    card1 = engine.draw_by_score(25)
    assert card1["card_type"] == "CALM_OBSERVE"
    
    # Tier 2: 31 - 50
    card2 = engine.draw_by_score(45)
    assert card2["card_type"] == "CONFIDENCE_RESTORE"
    
    # Tier 3: 51 - 70
    card3 = engine.draw_by_score(65)
    assert card3["card_type"] == "MARKET_IMPACT"
    
    # Tier 4: 71 - 85
    card4 = engine.draw_by_score(80)
    assert card4["card_type"] == "VOLATILITY_ALERT"
    
    # Tier 5: > 85
    card5 = engine.draw_by_score(90)
    assert card5["card_type"] == "STOCK_EVENT"
