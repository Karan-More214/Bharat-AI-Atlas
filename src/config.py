"""Shared settings: folder paths and database connection."""
import os
from pathlib import Path

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / ".env")

CONFIG_DIR = ROOT / "config"
RAW_DIR = ROOT / "data" / "raw"
PROCESSED_DIR = ROOT / "data" / "processed"
REPORTS_DIR = ROOT / "reports"
SQL_DIR = ROOT / "sql"

for folder in (RAW_DIR, PROCESSED_DIR, REPORTS_DIR):
    folder.mkdir(parents=True, exist_ok=True)

HF_TOKEN = os.getenv("HF_TOKEN") or None

DB = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", "3306")),
    "user": os.getenv("DB_USER", "root"),
    "password": os.getenv("DB_PASSWORD", ""),
    "database": os.getenv("DB_NAME", "bharat_ai_atlas"),
}


def db_url(with_database: bool = True) -> str:
    """SQLAlchemy connection string for MySQL."""
    from urllib.parse import quote_plus

    base = f"mysql+pymysql://{DB['user']}:{quote_plus(DB['password'])}@{DB['host']}:{DB['port']}"
    return f"{base}/{DB['database']}?charset=utf8mb4" if with_database else base
