-- =====================================================================
-- Bharat AI Atlas - business analysis queries (MySQL 8+)
-- Each block answers one question from the README.
-- Run them one at a time in MySQL Workbench (Ctrl+Enter on a statement).
-- =====================================================================
USE bharat_ai_atlas;

-- ---------------------------------------------------------------------
-- Q1. COVERAGE - Which Indian languages have AI, and which are left behind?
-- ---------------------------------------------------------------------

-- 1.1 Models per language, ranked
SELECT lang_name,
       total_models,
       RANK() OVER (ORDER BY total_models DESC) AS coverage_rank
FROM vw_language_coverage
ORDER BY total_models DESC;

-- 1.2 Fairness view: models per million speakers (lowest = most underserved)
SELECT lang_name,
       speakers_millions,
       total_models,
       models_per_million_speakers,
       RANK() OVER (ORDER BY models_per_million_speakers ASC) AS underserved_rank
FROM vw_language_coverage
ORDER BY models_per_million_speakers ASC;

-- 1.3 Coverage tiers: split languages into 4 groups by model count
SELECT lang_name,
       total_models,
       CASE NTILE(4) OVER (ORDER BY total_models DESC)
            WHEN 1 THEN 'Tier 1 - Well served'
            WHEN 2 THEN 'Tier 2 - Emerging'
            WHEN 3 THEN 'Tier 3 - Thin'
            ELSE        'Tier 4 - Left behind'
       END AS coverage_tier
FROM vw_language_coverage;

-- 1.4 Share of all language-model links held by each language
SELECT lang_name,
       total_models,
       ROUND(100.0 * total_models / SUM(total_models) OVER (), 2) AS pct_of_all_links
FROM vw_language_coverage
ORDER BY pct_of_all_links DESC;

-- 1.5 Dedicated vs multilingual: how many models are built ONLY for this language?
SELECT lang_name,
       total_models,
       dedicated_models,
       ROUND(100.0 * dedicated_models / NULLIF(total_models, 0), 1) AS pct_dedicated
FROM vw_language_coverage
ORDER BY pct_dedicated DESC;

-- ---------------------------------------------------------------------
-- Q2. GROWTH - How fast is Indic AI growing?
-- ---------------------------------------------------------------------

-- 2.1 New models per year with year-over-year growth
--     Excludes models with Hugging Face's placeholder date 2022-03-02 (created earlier, real year unknown).
--     The current year is partial (Jan up to today), so its growth % is not comparable.
WITH yearly AS (
    SELECT created_year, COUNT(*) AS new_models
    FROM models
    WHERE created_year IS NOT NULL AND date_is_placeholder = 0
    GROUP BY created_year
)
SELECT created_year,
       CASE WHEN created_year = YEAR(CURDATE())
            THEN CONCAT(created_year, ' (partial: Jan-', DATE_FORMAT(CURDATE(), '%b'), ')')
            ELSE CAST(created_year AS CHAR) END AS year_label,
       new_models,
       LAG(new_models) OVER (ORDER BY created_year) AS prev_year,
       ROUND(100.0 * (new_models - LAG(new_models) OVER (ORDER BY created_year))
             / NULLIF(LAG(new_models) OVER (ORDER BY created_year), 0), 1) AS yoy_growth_pct,
       SUM(new_models) OVER (ORDER BY created_year) AS cumulative_models
FROM yearly
ORDER BY created_year;

-- 2.2 Cumulative models per language per year (feeds a line chart)
WITH lang_year AS (
    SELECT l.lang_name, m.created_year, COUNT(*) AS new_models
    FROM models m
    JOIN model_languages ml ON ml.model_id = m.model_id
    JOIN languages l        ON l.lang_code = ml.lang_code
    WHERE m.created_year IS NOT NULL
    GROUP BY l.lang_name, m.created_year
)
SELECT lang_name,
       created_year,
       new_models,
       SUM(new_models) OVER (PARTITION BY lang_name ORDER BY created_year) AS cumulative_models
FROM lang_year
ORDER BY lang_name, created_year;

-- 2.3 Momentum: share of each language's models created since the start of the year before last
--     (e.g. run in 2026: 2024 + 2025 + the partial 2026)
SELECT l.lang_name,
       COUNT(*) AS total_models,
       SUM(CASE WHEN m.created_year >= YEAR(CURDATE()) - 2 THEN 1 ELSE 0 END) AS recent_models,
       ROUND(100.0 * SUM(CASE WHEN m.created_year >= YEAR(CURDATE()) - 2 THEN 1 ELSE 0 END)
             / COUNT(*), 1) AS pct_recent
FROM models m
JOIN model_languages ml ON ml.model_id = m.model_id
JOIN languages l        ON l.lang_code = ml.lang_code
GROUP BY l.lang_name
ORDER BY pct_recent DESC;

-- ---------------------------------------------------------------------
-- Q3. BUILDERS - Who is building AI for India?
-- ---------------------------------------------------------------------

-- 3.1 Models and downloads by builder type
SELECT org_type,
       COUNT(*)                                                         AS models,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)               AS pct_models,
       SUM(downloads_all_time)                                          AS downloads,
       ROUND(100.0 * SUM(downloads_all_time)
             / SUM(SUM(downloads_all_time)) OVER (), 1)                 AS pct_downloads
FROM vw_models_enriched
GROUP BY org_type
ORDER BY downloads DESC;

-- 3.2 Top 15 builders by all-time downloads (one row per organisation, e.g. meta-llama +
--     facebook + FacebookAI are all "Meta")
SELECT *
FROM (
    SELECT org_name, org_type,
           COUNT(DISTINCT author)  AS hf_accounts,
           SUM(total_models)       AS total_models,
           SUM(downloads_all_time) AS downloads_all_time,
           DENSE_RANK() OVER (ORDER BY SUM(downloads_all_time) DESC) AS rnk
    FROM vw_org_summary
    GROUP BY org_name, org_type
) ranked
WHERE rnk <= 15
ORDER BY rnk;

-- 3.3 Top builder for every language
--     Uses only strict India-dedicated models (is_india_dedicated = 1). With all models, Meta
--     "wins" almost every language because XLM-RoBERTa tags 15 Indian languages and has
--     ~725 M downloads - that shows global popularity, not who builds for each language.
WITH builder_lang AS (
    SELECT l.lang_name, e.org_name, e.org_type, COUNT(*) AS models,
           SUM(e.downloads_all_time) AS downloads,
           ROW_NUMBER() OVER (PARTITION BY l.lang_name
                              ORDER BY SUM(e.downloads_all_time) DESC) AS rn
    FROM vw_models_enriched e
    JOIN model_languages ml ON ml.model_id = e.model_id
    JOIN languages l        ON l.lang_code = ml.lang_code
    WHERE e.is_india_dedicated = 1
    GROUP BY l.lang_name, e.org_name, e.org_type
)
SELECT lang_name, org_name AS top_builder, org_type, models, downloads
FROM builder_lang
WHERE rn = 1
ORDER BY downloads DESC;

-- 3.4 Indian vs foreign builders (only for classified authors)
SELECT CASE is_indian WHEN 1 THEN 'Indian' WHEN 0 THEN 'Foreign' ELSE 'Unknown' END AS origin,
       COUNT(*) AS models,
       SUM(downloads_all_time) AS downloads
FROM vw_models_enriched
GROUP BY origin
ORDER BY downloads DESC;

-- ---------------------------------------------------------------------
-- Q4. USAGE - Are these models actually used?
-- ---------------------------------------------------------------------

-- 4.1 Share of models that have never been downloaded
SELECT COUNT(*)                                        AS total_models,
       SUM(is_zero_download)                           AS zero_download_models,
       ROUND(100.0 * SUM(is_zero_download) / COUNT(*), 1) AS pct_zero_download
FROM models;

-- 4.2 Download concentration: what share do the top 10 / top 1% of models hold?
WITH ranked AS (
    SELECT downloads_all_time,
           ROW_NUMBER()   OVER (ORDER BY downloads_all_time DESC) AS rn,
           COUNT(*)       OVER ()                                 AS n
    FROM models
)
SELECT ROUND(100.0 * SUM(CASE WHEN rn <= 10 THEN downloads_all_time END)
             / SUM(downloads_all_time), 1)                        AS top10_share_pct,
       ROUND(100.0 * SUM(CASE WHEN rn <= CEIL(n * 0.01) THEN downloads_all_time END)
             / SUM(downloads_all_time), 1)                        AS top1pct_share_pct
FROM ranked;

-- 4.3 Pareto curve: how many models make up 80% of all downloads?
WITH ranked AS (
    SELECT model_id, downloads_all_time,
           SUM(downloads_all_time) OVER (ORDER BY downloads_all_time DESC, model_id
                                         ROWS UNBOUNDED PRECEDING) AS running_total,
           SUM(downloads_all_time) OVER ()                         AS grand_total,
           ROW_NUMBER() OVER (ORDER BY downloads_all_time DESC, model_id) AS rn
    FROM models
)
SELECT MIN(rn) AS models_needed_for_80pct,
       (SELECT COUNT(*) FROM models) AS total_models
FROM ranked
WHERE running_total >= 0.8 * grand_total;

-- 4.4 Usage by task: supply vs demand
SELECT task_group,
       COUNT(*)                          AS models,
       SUM(downloads_all_time)           AS downloads,
       ROUND(AVG(downloads_all_time))    AS avg_downloads_per_model,
       ROUND(100.0 * AVG(is_zero_download), 1) AS pct_zero_download
FROM models
GROUP BY task_group
ORDER BY downloads DESC;

-- ---------------------------------------------------------------------
-- Q5. FOUNDATIONS - Whose base models does Indic AI stand on?
-- ---------------------------------------------------------------------

-- 5.1 Original vs derivative (fine-tuned / adapted / quantized) models
SELECT CASE WHEN is_derivative = 1 THEN 'Built on another model' ELSE 'Original / no base listed' END AS model_origin,
       COUNT(*) AS models,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM models
GROUP BY model_origin;

-- 5.2 Most-used foundation providers (one row per organisation, e.g. meta-llama +
--     facebook + FacebookAI are all "Meta")
--     Excludes self-derived models (an author fine-tuning their own earlier model).
SELECT COALESCE(o.org_name, m.base_author) AS base_provider,
       COUNT(DISTINCT m.base_author)       AS hf_accounts,
       COUNT(*)                            AS derived_models
FROM models m
LEFT JOIN organizations o ON o.author = m.base_author
WHERE m.is_derivative = 1
  AND m.base_author <> m.author
GROUP BY base_provider
ORDER BY derived_models DESC
LIMIT 15;

-- ---------------------------------------------------------------------
-- Q6. CAPABILITY GAPS & OPENNESS
-- ---------------------------------------------------------------------

-- 6.1 Capability matrix: which languages lack an LLM, speech recognition or TTS
--     built specifically for them? (strict India-dedicated models only - raw counts would
--     show no gaps because huge multilingual models tag almost every language)
SELECT lang_name,
       dedicated_strict_models,
       dedicated_llm_models,
       dedicated_asr_models,
       dedicated_tts_models,
       CONCAT_WS(', ',
           CASE WHEN dedicated_llm_models = 0 THEN 'No dedicated LLM' END,
           CASE WHEN dedicated_asr_models = 0 THEN 'No dedicated speech recognition' END,
           CASE WHEN dedicated_tts_models = 0 THEN 'No dedicated text-to-speech' END) AS gaps
FROM vw_language_coverage
ORDER BY (dedicated_llm_models = 0) + (dedicated_asr_models = 0) + (dedicated_tts_models = 0) DESC,
         dedicated_strict_models;

-- 6.2 How open are these models? (license mix)
SELECT license_group,
       COUNT(*) AS models,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM models
GROUP BY license_group
ORDER BY models DESC;

-- ---------------------------------------------------------------------
-- Q7. TRENDS - needs 2+ weekly snapshots (run the pipeline every week)
-- ---------------------------------------------------------------------

-- 7.1 Week-over-week change in 30-day downloads per language
WITH weekly AS (
    SELECT s.snapshot_date, l.lang_name, SUM(s.downloads_30d) AS downloads_30d
    FROM model_snapshots s
    JOIN model_languages ml ON ml.model_id = s.model_id
    JOIN languages l        ON l.lang_code = ml.lang_code
    GROUP BY s.snapshot_date, l.lang_name
)
SELECT snapshot_date,
       lang_name,
       downloads_30d,
       downloads_30d - LAG(downloads_30d) OVER (PARTITION BY lang_name ORDER BY snapshot_date) AS change_vs_last_snapshot
FROM weekly
ORDER BY lang_name, snapshot_date;

-- ---------------------------------------------------------------------
-- Q8. DEDICATED MODELS & MULTILINGUAL NOISE
-- "Dedicated (loose)" = n_indic_languages = 1 (can include global models that list one Indian
-- language next to many others). "Dedicated (strict)" = is_india_dedicated = 1 (rule in src/clean.py).
-- ---------------------------------------------------------------------

-- 8.1 Indian builders' share: all models vs loose vs strict dedicated models
SELECT scope,
       COUNT(*)                                                               AS models,
       ROUND(100.0 * SUM(is_indian = 1) / COUNT(*), 2)                        AS indian_pct_models,
       ROUND(100.0 * SUM(CASE WHEN is_indian = 1 THEN downloads_all_time ELSE 0 END)
             / SUM(downloads_all_time), 2)                                    AS indian_pct_downloads,
       ROUND(100.0 * SUM(org_type <> 'Unclassified') / COUNT(*), 1)           AS pct_models_classified,
       ROUND(100.0 * SUM(CASE WHEN org_type <> 'Unclassified' THEN downloads_all_time ELSE 0 END)
             / SUM(downloads_all_time), 1)                                    AS pct_downloads_classified
FROM (
    SELECT '1. All models' AS scope, e.* FROM vw_models_enriched e
    UNION ALL
    SELECT '2. Dedicated (loose)', e.* FROM vw_models_enriched e WHERE n_indic_languages = 1
    UNION ALL
    SELECT '3. Dedicated (strict)', e.* FROM vw_models_enriched e WHERE is_india_dedicated = 1
) scoped
GROUP BY scope
ORDER BY scope;

-- 8.2 Per language: total vs loose vs strict dedicated models
--     (Sanskrit excluded from the per-speaker column: ~0.02 M first-language speakers)
SELECT lang_name,
       total_models,
       dedicated_models                                                   AS dedicated_loose,
       ROUND(100.0 * dedicated_models / NULLIF(total_models, 0), 1)       AS pct_dedicated_loose,
       dedicated_strict_models                                            AS dedicated_strict,
       ROUND(100.0 * dedicated_strict_models / NULLIF(total_models, 0), 1) AS pct_dedicated_strict,
       CASE WHEN lang_code <> 'sa'
            THEN ROUND(dedicated_strict_models / speakers_millions, 2) END AS strict_per_million_speakers
FROM vw_language_coverage
ORDER BY total_models DESC;

-- 8.3 Model Repackagers: share of models vs share of downloads
SELECT ROUND(100.0 * SUM(org_type = 'Model Repackager') / COUNT(*), 1)                     AS pct_all_models,
       ROUND(100.0 * SUM(org_type = 'Model Repackager') / SUM(org_type <> 'Unclassified'), 1) AS pct_classified_models,
       ROUND(100.0 * SUM(CASE WHEN org_type = 'Model Repackager' THEN downloads_all_time ELSE 0 END)
             / SUM(downloads_all_time), 1)                                                  AS pct_downloads
FROM vw_models_enriched;

-- 8.4 How much usage comes from broad multilingual models (10+ Indian languages)?
SELECT SUM(n_indic_languages >= 10)                                           AS broad_models,
       ROUND(100.0 * SUM(n_indic_languages >= 10) / COUNT(*), 1)              AS pct_models,
       ROUND(100.0 * SUM(CASE WHEN n_indic_languages >= 10 THEN downloads_all_time ELSE 0 END)
             / SUM(downloads_all_time), 1)                                    AS pct_downloads
FROM models;
