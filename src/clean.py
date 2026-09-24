"""
STEP 2 - CLEAN & TRANSFORM
Turns the latest raw snapshot into analysis-ready tables:

    data/processed/languages.csv        dimension: 22 languages + speakers
    data/processed/organizations.csv    dimension: who built the model
    data/processed/models.csv           fact: one row per model
    data/processed/model_languages.csv  bridge: model <-> language (many-to-many)
    data/processed/model_snapshots.csv  history: downloads/likes per snapshot date
    reports/top_unmapped_authors.csv    authors you should label by hand

Usage:
    python src/clean.py                       # uses newest file in data/raw
    python src/clean.py --file data/raw/x.csv
"""
import argparse
import re
from datetime import date
from pathlib import Path

import pandas as pd

from config import CONFIG_DIR, PROCESSED_DIR, RAW_DIR, REPORTS_DIR

TASK_GROUPS = {
    "translation": "Translation",
    "text2text-generation": "Text-to-Text (Translation/Summarisation)",
    "summarization": "Text-to-Text (Translation/Summarisation)",
    "automatic-speech-recognition": "Speech Recognition",
    "text-to-speech": "Text-to-Speech",
    "text-to-audio": "Text-to-Speech",
    "audio-classification": "Audio Classification",
    "text-generation": "Text Generation (LLMs)",
    "fill-mask": "Language Understanding (Fill-Mask)",
    "text-classification": "Classification & NER",
    "token-classification": "Classification & NER",
    "zero-shot-classification": "Classification & NER",
    "question-answering": "Question Answering",
    "sentence-similarity": "Embeddings & Search",
    "feature-extraction": "Embeddings & Search",
    "image-to-text": "Vision & Multimodal",
    "image-text-to-text": "Vision & Multimodal",
    "visual-question-answering": "Vision & Multimodal",
    "text-to-image": "Vision & Multimodal",
    "image-classification": "Vision & Multimodal",
}

LICENSE_GROUPS = {
    "Permissive": ["apache-2.0", "mit", "bsd", "bsd-2-clause", "bsd-3-clause", "cc-by-4.0",
                   "cc-by-3.0", "cc-by-2.0", "cc0-1.0", "unlicense", "afl-3.0", "isc",
                   "artistic-2.0", "ecl-2.0", "odc-by", "pddl"],
    "Copyleft / Share-alike": ["gpl", "gpl-2.0", "gpl-3.0", "agpl-3.0", "lgpl", "lgpl-2.1",
                               "lgpl-3.0", "cc-by-sa-3.0", "cc-by-sa-4.0", "mpl-2.0", "odbl"],
    "Non-commercial": ["cc-by-nc-2.0", "cc-by-nc-3.0", "cc-by-nc-4.0", "cc-by-nc-sa-2.0",
                       "cc-by-nc-sa-3.0", "cc-by-nc-sa-4.0", "cc-by-nc-nd-3.0", "cc-by-nc-nd-4.0",
                       "cc-by-nd-4.0"],
}
BASE_RELATIONS = {"finetune", "adapter", "quantized", "merge"}

# Hugging Face gives this createdAt to every model created before its March 2022 migration
PLACEHOLDER_DATE = date(2022, 3, 2)

# ---------- strict "India-dedicated" rule ----------
# A model is India-dedicated (is_india_dedicated = 1) when BOTH are true:
#   1) it matches exactly one of the 22 official languages (n_indic_languages == 1), and
#   2) at least half of its non-English language tags are Indian languages.
# Language tags = tags of 2-3 lowercase letters ("hi", "mar", "fr"), minus the short tags
# below that are not languages. English is ignored, so an English + Marathi model counts
# as dedicated, but Llama-3.1-8B-Instruct (en, de, fr, it, pt, hi, es, th) does not.
NOT_LANGUAGE_TAGS = {"mlx", "tts", "jax", "asr", "nlp", "llm", "ner", "iso", "art", "moe", "sft",
                     "rag", "pii", "trl", "dpo", "gpt", "vit", "ocr", "ctc", "awq", "tf", "kto",
                     "qat", "sql", "api", "cpu", "gpu"}
# The 22 official languages (2- and 3-letter codes) plus other Indian regional languages
# (Bhojpuri, Awadhi, Magahi, Chhattisgarhi, Tulu, Mizo, Khasi, Rajasthani, Gondi, ...)
INDIAN_LANGUAGE_TAGS = {
    "hi", "bn", "mr", "te", "ta", "gu", "ur", "kn", "or", "ory", "ml", "pa", "as", "mai", "sat",
    "ks", "ne", "npi", "sd", "doi", "kok", "gom", "mni", "brx", "sa",
    "hin", "ben", "mar", "tel", "tam", "guj", "urd", "kan", "ori", "mal", "pan", "asm", "nep",
    "san", "snd", "kas",
    "bho", "awa", "mag", "hne", "tcy", "lus", "kha", "gbm", "anp", "raj", "bgc", "sck", "gon",
    "kru", "unr", "hoc", "bpy",
}


def indian_tag_share(tags):
    """Share (0-1) of a model's non-English language tags that are Indian languages."""
    langs = {t for t in tags if re.fullmatch(r"[a-z]{2,3}", t) and t not in NOT_LANGUAGE_TAGS}
    langs -= {"en", "eng"}
    return len(langs & INDIAN_LANGUAGE_TAGS) / len(langs) if langs else 0.0


def license_of(tags):
    for t in tags:
        if t.startswith("license:"):
            return t.split(":", 1)[1].lower()
    return None


def license_group(lic):
    if not isinstance(lic, str) or not lic:
        return "Not specified"
    for group, names in LICENSE_GROUPS.items():
        if lic in names:
            return group
    if any(k in lic for k in ("llama", "gemma", "openrail", "bigscience", "bigcode")):
        return "Model-specific (Llama/Gemma/RAIL)"
    return "Other"


def base_model_of(tags):
    """'base_model:finetune:google/gemma-2b' -> ('google/gemma-2b', 'finetune')."""
    base, relation = None, None
    for t in tags:
        if not t.startswith("base_model:"):
            continue
        parts = t.split(":")
        if len(parts) == 3 and parts[1] in BASE_RELATIONS:
            return parts[2], parts[1]
        if len(parts) == 2 and base is None:
            base = parts[1]
    return base, ("finetune" if base else None)


def latest_raw_file() -> Path:
    files = sorted(RAW_DIR.glob("models_raw_*.csv"))
    if not files:
        raise SystemExit("No raw file found. Run: python src/collect.py")
    return files[-1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", type=Path, default=None)
    args = parser.parse_args()
    raw_path = args.file or latest_raw_file()
    raw = pd.read_csv(raw_path, dtype={"tags": str})
    print(f"Loaded {len(raw):,} raw rows from {raw_path.name}")

    # ---------- basic hygiene ----------
    raw = raw.dropna(subset=["model_id"]).copy()
    raw["tags"] = raw["tags"].fillna("")
    raw["author"] = raw["author"].fillna(raw["model_id"].str.split("/").str[0]).str.strip()
    for col in ("downloads_30d", "downloads_all_time", "likes"):
        raw[col] = pd.to_numeric(raw[col], errors="coerce").fillna(0).astype("int64")
    raw["created_at"] = pd.to_datetime(raw["created_at"], errors="coerce", utc=True)
    snapshot_date = raw["snapshot_date"].iloc[0]

    # ---------- bridge: model <-> language ----------
    model_languages = (raw[["model_id", "query_lang"]]
                       .drop_duplicates()
                       .rename(columns={"query_lang": "lang_code"}))

    # ---------- fact: one row per model ----------
    models = raw.sort_values("downloads_all_time", ascending=False).drop_duplicates("model_id").copy()
    tag_lists = models["tags"].str.split("|")
    models["license"] = tag_lists.apply(license_of)
    models["license_group"] = models["license"].apply(license_group)
    base = tag_lists.apply(base_model_of)
    models["base_model"] = base.str[0]
    models["base_relation"] = base.str[1]
    models["base_author"] = models["base_model"].str.split("/").str[0]
    models["is_derivative"] = models["base_model"].notna().astype(int)
    models["task"] = models["pipeline_tag"].fillna("unspecified")
    models["task_group"] = models["pipeline_tag"].map(TASK_GROUPS).fillna(
        models["pipeline_tag"].apply(lambda p: "Unspecified" if pd.isna(p) else "Other"))
    models["library"] = models["library_name"].fillna("unspecified")
    models["model_name"] = models["model_id"].str.split("/", n=1).str[-1]
    models["created_date"] = models["created_at"].dt.date
    models["created_year"] = models["created_at"].dt.year.astype("Int64")
    models["date_is_placeholder"] = (models["created_date"] == PLACEHOLDER_DATE).astype(int)
    models.loc[models["date_is_placeholder"] == 1, "created_year"] = pd.NA  # real year unknown
    models["is_gated"] = models["gated"].astype(str).str.lower().isin(["auto", "manual", "true"]).astype(int)
    n_langs = model_languages.groupby("model_id").size().rename("n_indic_languages")
    models = models.merge(n_langs, on="model_id", how="left")
    models["is_india_dedicated"] = ((models["n_indic_languages"] == 1)
                                    & (tag_lists.apply(indian_tag_share).values >= 0.5)).astype(int)
    models["is_zero_download"] = (models["downloads_all_time"] == 0).astype(int)

    models = models[[
        "model_id", "author", "model_name", "task", "task_group", "library", "license",
        "license_group", "base_model", "base_author", "base_relation", "is_derivative",
        "is_gated", "n_indic_languages", "is_india_dedicated", "downloads_30d", "downloads_all_time",
        "likes", "is_zero_download", "created_date", "created_year", "date_is_placeholder",
    ]]

    # ---------- dimension: organizations ----------
    mapping = pd.read_csv(CONFIG_DIR / "author_mapping.csv")
    orgs = pd.DataFrame({"author": models["author"].unique()})
    orgs = orgs.merge(mapping, on="author", how="left")
    orgs["org_name"] = orgs["org_name"].fillna(orgs["author"])
    orgs["org_type"] = orgs["org_type"].fillna("Unclassified")
    orgs["is_indian"] = orgs["is_indian"].astype("Int64")

    # ---------- dimension: languages ----------
    languages = pd.read_csv(CONFIG_DIR / "languages.csv").drop(columns=["hf_codes"])

    # ---------- history snapshot ----------
    snapshots = models[["model_id", "downloads_30d", "downloads_all_time", "likes"]].copy()
    snapshots.insert(0, "snapshot_date", snapshot_date)

    # ---------- report: who to label next ----------
    unmapped = (models.merge(orgs[["author", "org_type"]], on="author")
                .query("org_type == 'Unclassified'")
                .groupby("author")
                .agg(n_models=("model_id", "count"), downloads_all_time=("downloads_all_time", "sum"))
                .sort_values(["downloads_all_time", "n_models"], ascending=False)
                .head(100)
                .reset_index())
    unmapped.to_csv(REPORTS_DIR / "top_unmapped_authors.csv", index=False)

    # ---------- save ----------
    for name, df in {"languages": languages, "organizations": orgs, "models": models,
                     "model_languages": model_languages, "model_snapshots": snapshots}.items():
        df.to_csv(PROCESSED_DIR / f"{name}.csv", index=False, encoding="utf-8")
        print(f"  {name:<16} {len(df):>7,} rows")

    # small sample that is safe to commit to GitHub (full data stays local)
    sample_dir = PROCESSED_DIR.parent / "sample"
    sample_dir.mkdir(exist_ok=True)
    models.head(200).to_csv(sample_dir / "models_sample.csv", index=False, encoding="utf-8")

    # ---------- data-quality checks ----------
    assert models["model_id"].is_unique, "duplicate model_id in models"
    assert set(model_languages["lang_code"]) <= set(languages["lang_code"]), "unknown language code"
    missing = models["created_date"].isna().sum()
    print(f"\nQuality: {missing} models without created date, "
          f"{models['date_is_placeholder'].sum()} with placeholder date {PLACEHOLDER_DATE} (created_year set to NULL), "
          f"{models['is_india_dedicated'].sum():,} India-dedicated models, "
          f"{(orgs['org_type'] == 'Unclassified').mean():.0%} of authors unclassified "
          f"(label the top ones from reports/top_unmapped_authors.csv)")


if __name__ == "__main__":
    main()
