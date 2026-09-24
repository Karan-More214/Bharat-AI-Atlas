"""
STEP 3 - LOAD INTO MYSQL
Creates the database + tables (sql/schema.sql), loads data/processed/*.csv,
appends today's snapshot to the history table and builds the reporting views.

Usage:
    python src/load_to_sql.py
"""
import re

import pandas as pd
from sqlalchemy import create_engine, text

from config import DB, PROCESSED_DIR, SQL_DIR, db_url

LOAD_ORDER = ["languages", "organizations", "models", "model_languages"]


def run_sql_file(conn, path):
    """Execute a .sql file statement by statement (skips comment lines)."""
    sql = path.read_text(encoding="utf-8").replace("bharat_ai_atlas", DB["database"])
    sql = "\n".join(line for line in sql.splitlines() if not line.strip().startswith("--"))
    for statement in (s.strip() for s in sql.split(";")):
        if statement:
            conn.execute(text(statement))


def main():
    # 1) create database + tables
    server = create_engine(db_url(with_database=False))
    with server.begin() as conn:
        run_sql_file(conn, SQL_DIR / "schema.sql")
    print(f"Schema ready in database '{DB['database']}'")

    engine = create_engine(db_url())

    # 2) load current-state tables (parents before children because of foreign keys)
    for table in LOAD_ORDER:
        df = pd.read_csv(PROCESSED_DIR / f"{table}.csv")
        df = df.astype(object).where(pd.notna(df), None)  # NaN -> NULL
        df.to_sql(table, engine, if_exists="append", index=False, chunksize=2000, method="multi")
        print(f"  loaded {table:<16} {len(df):>7,} rows")

    # 3) append snapshot history (replace rows for the same date if re-run)
    snaps = pd.read_csv(PROCESSED_DIR / "model_snapshots.csv")
    snap_date = str(snaps["snapshot_date"].iloc[0])
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", snap_date):
        raise SystemExit(f"Unexpected snapshot date: {snap_date}")
    with engine.begin() as conn:
        conn.execute(text("DELETE FROM model_snapshots WHERE snapshot_date = :d"), {"d": snap_date})
    snaps.to_sql("model_snapshots", engine, if_exists="append", index=False, chunksize=2000, method="multi")
    print(f"  appended snapshot {snap_date}    {len(snaps):>7,} rows")

    # 4) reporting views
    with engine.begin() as conn:
        run_sql_file(conn, SQL_DIR / "views.sql")
    print("Views created: vw_models_enriched, vw_language_coverage, vw_org_summary")


if __name__ == "__main__":
    main()
