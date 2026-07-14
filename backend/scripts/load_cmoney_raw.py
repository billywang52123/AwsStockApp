"""把 CMoney Hackathon 資料包 CSV 載入 `raw` schema(對齊 RDS stockmood 的表名/欄名)。

用法(容器內):
    python scripts/load_cmoney_raw.py /path/to/Delivery_Hackathon_DataPackage_20260624

- 表結構全部 text 欄位,欄名 = CSV 標頭(去 BOM),與 docs/file/stockmood_database_schema_utf8.md 一致
- 冪等:已載入(行數相符)的表跳過;行數不符則整表重灌
"""
import csv
import sys
from pathlib import Path

from sqlalchemy import text

sys.path.append(str(Path(__file__).resolve().parent.parent))
from app.db.database import engine  # noqa: E402

CSV_TABLE_MAP = {
    "00_Field_Dictionary_and_Usage_Notes.csv": "raw_00_field_dictionary_and_usage_notes",
    "01_Price_Valuation_2025.csv": "raw_01_price_valuation_2025",
    "02_Institutional_Trading_2025.csv": "raw_02_institutional_trading_2025",
    "03_Return_Rate_2025.csv": "raw_03_return_rate_2025",
    "04_Distance_from_High_Low_Momentum_2025.csv": "raw_04_distance_from_high_low_momentum_2025",
    "05_Dividend_Ex_Dividend_2025.csv": "raw_05_dividend_ex_dividend_2025",
    "06_Consecutive_Dividend_Stocks_2025.csv": "raw_06_consecutive_dividend_stocks_2025",
    "06b_Consecutive_Dividend_ETF_2025.csv": "raw_06b_consecutive_dividend_etf_2025",
    "07_Industry_Classification_Mapping.csv": "raw_07_industry_classification_mapping",
    "09_Wide_Table_Summary_One_Row_Per_Stock_2025.csv": "raw_09_wide_table_summary_one_row_per_stock_2025",
    "10_Forum_Posts_Replies_Daily_Stats_2025.csv": "raw_10_forum_posts_replies_daily_stats_2025",
}

BATCH = 5000


def load_csv(conn, csv_path: Path, table: str) -> None:
    with open(csv_path, encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        header = [h.strip() for h in header]
        rows = list(reader)

    existing = conn.execute(text(
        "SELECT to_regclass(:name)"), {"name": f"raw.{table}"}).scalar()
    if existing:
        count = conn.execute(text(f'SELECT count(*) FROM raw."{table}"')).scalar()
        if count == len(rows):
            print(f"  = {table}: 已載入 {count} 行,跳過")
            return
        conn.execute(text(f'DROP TABLE raw."{table}"'))

    cols_ddl = ", ".join(f'"{c}" text' for c in header)
    conn.execute(text(f'CREATE TABLE raw."{table}" ({cols_ddl})'))

    cols = ", ".join(f'"{c}"' for c in header)
    params = ", ".join(f":c{i}" for i in range(len(header)))
    insert = text(f'INSERT INTO raw."{table}" ({cols}) VALUES ({params})')
    for start in range(0, len(rows), BATCH):
        chunk = rows[start:start + BATCH]
        conn.execute(insert, [
            {f"c{i}": (v if v != "" else None) for i, v in enumerate(row)}
            for row in chunk
        ])
    print(f"  + {table}: 載入 {len(rows)} 行")


def main() -> None:
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    data_dir = Path(sys.argv[1])

    with engine.begin() as conn:
        conn.execute(text("CREATE SCHEMA IF NOT EXISTS raw"))
        for csv_name, table in CSV_TABLE_MAP.items():
            csv_path = data_dir / csv_name
            if not csv_path.exists():
                print(f"  ! 缺 {csv_name},跳過")
                continue
            load_csv(conn, csv_path, table)
    print("完成。")


if __name__ == "__main__":
    main()
