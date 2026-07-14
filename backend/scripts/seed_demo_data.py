import os
import sys
from pathlib import Path

# Add backend directory to path so imports work correctly
backend_dir = Path(__file__).resolve().parent.parent
sys.path.append(str(backend_dir))

from app.db.database import SessionLocal, Base, engine
from app.services.csv_import_service import CSVImportService
from app.services.services import PortfolioService

def seed(force: bool = False) -> bool:
    # Make sure tables are created
    Base.metadata.create_all(bind=engine)

    # Run migrations to add any missing columns before seeding
    from app.db.migrations import run_light_migrations
    run_light_migrations(engine)

    from app.models.stock import Stock

    db = SessionLocal()
    try:
        # 冪等守衛:容器每次啟動都會跑 seed,已有資料就跳過,避免重複塞 demo 持股
        if not force and db.query(Stock).count() > 0:
            print("Stocks already present; skipping seed (idempotent).")
            return False

        print("Seeding stock metadata...")
        stocks_csv = backend_dir / "data" / "stocks.csv"
        with open(stocks_csv, "rb") as f:
            stocks_count = CSVImportService.import_stocks(f.read(), db)
        print(f"Successfully seeded {stocks_count} stocks.")

        print("Seeding stock daily closing prices...")
        prices_csv = backend_dir / "data" / "stock_daily_prices.csv"
        with open(prices_csv, "rb") as f:
            prices_count = CSVImportService.import_daily_prices(f.read(), db)
        print(f"Successfully seeded {prices_count} price rows.")

        print("Seeding TAIEX market indices...")
        market_csv = backend_dir / "data" / "market_index_daily.csv"
        with open(market_csv, "rb") as f:
            market_count = CSVImportService.import_market_index(f.read(), db)
        print(f"Successfully seeded {market_count} market days.")

        print("Seeding demo portfolio items...")
        portfolio_service = PortfolioService(db)
        # Add TSMC and CTBC to the default demo user portfolio
        portfolio_service.add_item("2330", cost_price=980.0, shares=1000)
        portfolio_service.add_item("2891", cost_price=38.0, shares=3000)
        db.commit()
        print("Successfully seeded demo portfolio holdings.")
        return True

    except Exception as e:
        print(f"Error during seeding: {e}")
        return False
    finally:
        db.close()

if __name__ == "__main__":
    seed()
