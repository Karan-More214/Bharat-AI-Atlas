# Findings

**Data:** Hugging Face Hub snapshot of 2026-09-24. It covers 17,084 unique models tagged with at least one of India's 22 official languages, loaded into MySQL. Speaker counts are from Census 2011 (first-language speakers).

**Source column:** numbers like `4.3` refer to queries in [`sql/analysis.sql`](../sql/analysis.sql).

**Two definitions of "dedicated"**
- **Loose** (`n_indic_languages = 1`): the model tags exactly one of the 22 languages. This can include global models, e.g. Llama-3.1-8B-Instruct counts as "dedicated Hindi" because Hindi is its only Indian language among 8.
- **Strict** (`is_india_dedicated = 1`): loose, **and** at least half of the model's non-English language tags are Indian languages. 7,011 models qualify. The exact rule is in [`src/clean.py`](../src/clean.py) and the README. **The findings below use the strict definition unless they say otherwise.**

**Standing caveats**
- **Sanskrit is excluded from every "per million speakers" comparison.** Census 2011 lists only ~0.02 M first-language speakers, so its 1,863 models give 93,150 models per million speakers, a meaningless outlier.
- **Bengali, Urdu, Nepali, Punjabi and Sindhi** are also spoken in Bangladesh, Pakistan and Nepal. Many of their models are built for those countries, while the speaker counts only cover India. This inflates their per-speaker numbers the most for Nepali (1,427 per M) and Sindhi (678 per M).
- Only models **tagged** with a language are counted. A model that supports Tamil but doesn't say so is missing.
- `downloads_all_time` is **global**. It shows how popular a model is, not how much it is used in India or in a given language.

---

## The 10 strongest findings

### 1. Even among models built for one Indian language, Indian builders get only 9% of the downloads
**Among the 7,011 models dedicated to a single Indian language, Indian builders made 3.4% of the models and receive 9.2% of the downloads. Across all 17,084 models, their share is just 0.67% of downloads (1.97% of models).**
- Source: 8.1, 3.4
- Caveat: individuals were left with `is_indian` blank because nationality can't be verified, and many individuals fine-tuning Indian-language models are probably Indian. The true Indian share is therefore likely higher, so treat 9.2% as a floor.¹

### 2. A few models get almost all the downloads
**Just 41 of 17,084 models (0.24%) account for 80% of all-time downloads, and the top 10 models alone take 52.3%.**
- Source: 4.3, 4.2
- Caveat: the top 10 are all general-purpose global models: XLM-RoBERTa, multilingual BERT, Whisper, Llama-3.1-8B-Instruct and Sentence-Transformers. They are downloaded worldwide for many languages, so this measures global popularity, not Indian-language use.

### 3. "Indic AI" usage is mostly generic multilingual AI
**Models tagged with 10 or more Indian languages are 14.2% of all models (2,430) but receive 63.4% of all downloads.**
- Source: 8.4
- Caveat: these models usually tag 50–100+ languages, so Indian languages are a small part of what they do.

### 4. Global Big Tech: 1% of the models, 62% of the downloads
**Global Big Tech authors published only 1.4% of models (239) but receive 62.4% of downloads. Meta alone accounts for 2.28 billion downloads across its three Hugging Face accounts.**
- Source: 3.1, 3.2
- Caveat: same as finding 2: most of these downloads are global use of multilingual models.¹

### 5. On paper every language has AI; in practice the smallest have almost none built for them
**Counting only models built specifically for each language, Dogri and Bodo have no LLM, and Dogri, Manipuri, Kashmiri and Konkani have no text-to-speech model.**
- Source: 6.1
- Caveat: in raw counts all 22 languages have LLM, speech-recognition and TTS models, because huge multilingual models tag hundreds of languages. For example, Bodo appears in 112 TTS models, but only 1 is built for Bodo. "No" means no *tagged, dedicated, public* model. Untagged or private models may exist.

### 6. Small languages are covered almost entirely by "also supports" models
**Only 3 of Dogri's 221 models (1.4%), 8 of Manipuri's 523 (1.5%) and 9 of Bodo's 360 (2.5%) are built for that language. For Hindi it's 2,203 of 11,350 (19.4%).**
- Source: 8.2
- Caveat: query 1.5 uses the loose definition and shows 59.6% for Hindi, because it counts global models like Llama as "dedicated Hindi".

### 7. Hindi has the most models but the fewest per speaker
**Hindi has the most models (11,350) but the fewest per million speakers (21.5), behind Marathi (40.2) and Telugu (44.1), out of 21 languages (Sanskrit excluded).**
- Source: 1.2
- Caveat: this metric naturally favours small languages, because one multilingual model counts once for each of the 22 languages it tags. Counting only dedicated models, the most underserved are **Dogri (1.15 per M), Maithili (1.40 per M, only 19 models for 13.6 M speakers) and Gujarati (1.93 per M)**, with Hindi at 4.17 (8.2). Census 2011 counts only first-language speakers, so Hindi's true reach is larger still.

### 8. Indic AI is growing fast, and 2026 has already passed 2025
**New models per year grew 5.8×, from 939 in 2023 to 5,467 in 2025. 2026 already has 6,449 by 24 September, more than all of 2025.**
- Source: 2.1
- Caveat: 2026 is labelled "partial (Jan–Sep)", and its +18% growth compares 9 months with 12, so it understates growth. 311 models with Hugging Face's placeholder date (2022-03-02, meaning "created before March 2022") are excluded, which leaves 408 models in 2022. Deleted models aren't counted, so older years are slightly undercounted.

### 9. Most Indic AI is built on someone else's foundation, usually Meta's
**64% of models (10,926) are fine-tuned, adapted or quantized from another model. The most common foundations are Meta (2,174 derived models across meta-llama, facebook and FacebookAI) and OpenAI (1,181, mostly Whisper).**
- Source: 5.1, 5.2
- Caveat: models that don't declare a base model count as "original", so 64% is a minimum. 5.2 excludes self-derived models (an author fine-tuning their own model); before that, one individual with 813 self-derived Nepali models ranked #3.

### 10. Many classified models are just repackaged copies
**Model Repackagers, accounts that quantize or convert other people's models, published 43% of all classified models (12.3% of all models) but receive only 5.9% of downloads.**
- Source: 8.3, 3.1
- Caveat: the 43% only covers the 4,889 classified models. The unclassified long tail certainly contains more repackagers, so their true share of all models is unknown but above 12.3%.¹

**Also worth knowing:** 60.8% of models have a permissive license (Apache/MIT/CC-BY), 5.3% are non-commercial only and 6.0% list no license (6.2). 11.8% of models (2,011) have never been downloaded (4.1), but 191 of them are less than 30 days old, so "never downloaded" partly means "just published".

¹ *Builder-type counts: 71% of models are unclassified (a long tail of small authors), while 99.7% of downloads are classified. Shares based on downloads are reliable; shares based on model counts only describe the classified 29%.*

---

## Top 3 headlines

1. **Even among AI models built for a single Indian language, Indian builders get only 9% of the downloads.** Across all Indian-language AI, their share is 0.67%. *(Finding 1)*
2. **41 models out of 17,084 get 80% of all downloads.** The "Indic AI boom" is thousands of models that almost nobody uses, orbiting a handful of global giants. *(Finding 2)*
3. **Every Indian language "has" an LLM, until you look closer.** Not one LLM has been built specifically for Dogri or Bodo; their coverage comes entirely from global models that list them among 100+ languages. *(Finding 5)*

---

## Data issues

| Issue | Status |
|---|---|
| **Placeholder date 2022-03-02.** 311 models carry the date Hugging Face gives to anything created before March 2022 | **Fixed:** `created_year` is NULL for these and `date_is_placeholder = 1`. 2.1 excludes them. |
| **"Dedicated" was too loose.** 5,292 of the 12,303 `n_indic_languages = 1` models are global models | **Fixed:** new `is_india_dedicated` column, used in 6.1 and 8.x. Query 1.5 still shows the loose version for comparison. |
| **One author floods Nepali.** kiranpantha has 830 models (4.9% of all models, 20% of Nepali models) with 26,865 downloads combined; 813 are fine-tunes of their own models | **Partly fixed:** 5.2 excludes self-derived models. Nepali model counts (1.x, 8.2) still include them, so keep that caveat. |
| **3.2 split companies** (Meta ×3, Google ×2) | **Fixed:** grouped by `org_name`. |
| **2.3 label** said "last 2 full years" but covered 2024 through the partial 2026 | **Fixed:** the label now describes the query. |
| **3.3 was dominated by Meta** (top builder in 19 of 22 languages, driven by XLM-RoBERTa) | **Fixed:** 3.3 now uses dedicated models only. The top builder is now an individual or unclassified author in 17 of 22 languages, usually with one speech-recognition model, and an Indian institution in only 3 (Tamil: Vakyansh; Bodo and Dogri: AI4Bharat). |
| **5.2 split Meta** into meta-llama, facebook and FacebookAI rows (it grouped by handle) | **Fixed:** grouped by organisation name. Meta is one row (2,174). |
| **7.1 has one snapshot** | Open. Rerun the pipeline weekly; 7.1 works after the second run. |
| **Some language tags are wrong** (e.g. a Portuguese Whisper, a German sentiment model and a Korean model tagged Hindi) | Open. Listed under Limitations in the README. |
| **Per-language downloads look flat** (30-day downloads range only 99 M–230 M across the big languages in 7.1) | Open. The same multilingual models are counted in every language. Use dedicated models for per-language usage charts. |
