"""
STEP 1 - COLLECT
Pulls metadata for every Hugging Face model tagged with one of India's
22 scheduled languages and saves a dated raw snapshot.

Usage:
    python src/collect.py                 # all 22 languages
    python src/collect.py --langs mr hi   # only some languages
    python src/collect.py --limit 50      # quick test: 50 models per language code
"""
import argparse
import time
from datetime import date

import pandas as pd
from huggingface_hub import HfApi

from config import CONFIG_DIR, HF_TOKEN, RAW_DIR

# Only the fields we need -> faster and lighter than full=True
FIELDS = [
    "author", "createdAt", "lastModified", "downloads", "downloadsAllTime",
    "likes", "pipeline_tag", "library_name", "tags", "gated",
]


def fetch_language(api: HfApi, lang_code: str, hf_code: str, limit=None, retries=3):
    """Return one row per model tagged with `hf_code`."""
    for attempt in range(1, retries + 1):
        try:
            rows = []
            for m in api.list_models(filter=hf_code, expand=FIELDS, limit=limit):
                rows.append({
                    "model_id": m.id,
                    "author": m.author or m.id.split("/")[0],
                    "query_lang": lang_code,          # our standard code
                    "hf_code": hf_code,               # tag actually matched
                    "pipeline_tag": m.pipeline_tag,
                    "library_name": m.library_name,
                    "downloads_30d": m.downloads,
                    "downloads_all_time": getattr(m, "downloads_all_time", None),
                    "likes": m.likes,
                    "gated": getattr(m, "gated", None),
                    "created_at": m.created_at,
                    "last_modified": getattr(m, "last_modified", None),
                    "tags": "|".join(m.tags or []),
                })
            return rows
        except Exception as err:  # network hiccup / rate limit
            wait = 10 * attempt
            print(f"   ! {hf_code}: {err.__class__.__name__} - retrying in {wait}s")
            time.sleep(wait)
    print(f"   x {hf_code}: failed after {retries} attempts, skipped")
    return []


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--langs", nargs="*", help="language codes to collect (default: all)")
    parser.add_argument("--limit", type=int, default=None, help="max models per language code")
    args = parser.parse_args()

    langs = pd.read_csv(CONFIG_DIR / "languages.csv")
    if args.langs:
        langs = langs[langs["lang_code"].isin(args.langs)]

    api = HfApi(token=HF_TOKEN)
    all_rows = []
    for _, lang in langs.iterrows():
        for hf_code in str(lang["hf_codes"]).split("|"):
            rows = fetch_language(api, lang["lang_code"], hf_code, args.limit)
            print(f"{lang['lang_name']:<10} [{hf_code:<4}] {len(rows):>6} models")
            all_rows.extend(rows)
            time.sleep(0.5)  # be polite to the API

    df = pd.DataFrame(all_rows)
    df["snapshot_date"] = date.today().isoformat()
    out = RAW_DIR / f"models_raw_{date.today().isoformat()}.csv"
    df.to_csv(out, index=False, encoding="utf-8")
    print(f"\nSaved {len(df):,} rows ({df['model_id'].nunique():,} unique models) -> {out}")


if __name__ == "__main__":
    main()
