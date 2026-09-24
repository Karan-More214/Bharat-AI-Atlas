"""
STEP 4 - EXPORT FOR POWER BI
Exports the MySQL tables and reporting views to data/powerbi/*.csv, for when Power BI
cannot connect to MySQL directly (Get Data -> Text/CSV).

Usage:
    python src/export_for_powerbi.py
"""
import pandas as pd
from sqlalchemy import create_engine, text

from config import ROOT, db_url

POWERBI_DIR = ROOT / "data" / "powerbi"
EXPORTS = ["languages", "organizations", "models", "model_languages", "model_snapshots",
           "vw_language_coverage", "vw_org_summary"]


def main():
    POWERBI_DIR.mkdir(parents=True, exist_ok=True)
    engine = create_engine(db_url())
    with engine.connect() as conn:
        for name in EXPORTS:
            # nullable dtypes keep integer columns with NULLs as 1 / blank instead of 1.0 / NaN
            df = pd.read_sql(text(f"SELECT * FROM `{name}`"), conn, dtype_backend="numpy_nullable")
            # utf-8-sig = UTF-8 with a BOM, so Power BI detects the encoding (e.g. for non-ASCII names)
            df.to_csv(POWERBI_DIR / f"{name}.csv", index=False, encoding="utf-8-sig")
            print(f"  exported {name:<22} {len(df):>7,} rows")
    print(f"CSV files ready in {POWERBI_DIR}")


if __name__ == "__main__":
    main()
