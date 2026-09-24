-- =====================================================================
-- Bharat AI Atlas - reporting views (Power BI can import these directly)
-- =====================================================================
USE bharat_ai_atlas;

-- One row per model with its builder details
CREATE OR REPLACE VIEW vw_models_enriched AS
SELECT m.*,
       o.org_name,
       o.org_type,
       o.is_indian
FROM models m
JOIN organizations o ON o.author = m.author;

-- One row per language: supply (models) vs demand (speakers) vs usage (downloads)
CREATE OR REPLACE VIEW vw_language_coverage AS
SELECT l.lang_code,
       l.lang_name,
       l.script,
       l.speakers_millions,
       COUNT(ml.model_id)                                        AS total_models,
       ROUND(COUNT(ml.model_id) / l.speakers_millions, 2)        AS models_per_million_speakers,
       COALESCE(SUM(m.downloads_all_time), 0)                    AS downloads_all_time,
       COALESCE(SUM(m.downloads_30d), 0)                         AS downloads_30d,
       SUM(CASE WHEN m.n_indic_languages = 1 THEN 1 ELSE 0 END)  AS dedicated_models,
       SUM(CASE WHEN m.task_group = 'Text Generation (LLMs)' THEN 1 ELSE 0 END) AS llm_models,
       SUM(CASE WHEN m.task_group = 'Speech Recognition' THEN 1 ELSE 0 END)     AS asr_models,
       SUM(CASE WHEN m.task_group = 'Text-to-Speech' THEN 1 ELSE 0 END)         AS tts_models,
       -- strict: built for this language only (is_india_dedicated, rule in src/clean.py)
       SUM(CASE WHEN m.is_india_dedicated = 1 THEN 1 ELSE 0 END)                AS dedicated_strict_models,
       SUM(CASE WHEN m.is_india_dedicated = 1 AND m.task_group = 'Text Generation (LLMs)' THEN 1 ELSE 0 END) AS dedicated_llm_models,
       SUM(CASE WHEN m.is_india_dedicated = 1 AND m.task_group = 'Speech Recognition' THEN 1 ELSE 0 END)     AS dedicated_asr_models,
       SUM(CASE WHEN m.is_india_dedicated = 1 AND m.task_group = 'Text-to-Speech' THEN 1 ELSE 0 END)         AS dedicated_tts_models
FROM languages l
LEFT JOIN model_languages ml ON ml.lang_code = l.lang_code
LEFT JOIN models m           ON m.model_id  = ml.model_id
GROUP BY l.lang_code, l.lang_name, l.script, l.speakers_millions;

-- One row per builder
CREATE OR REPLACE VIEW vw_org_summary AS
SELECT o.author,
       o.org_name,
       o.org_type,
       o.is_indian,
       COUNT(m.model_id)            AS total_models,
       SUM(m.downloads_all_time)    AS downloads_all_time,
       SUM(m.downloads_30d)         AS downloads_30d,
       SUM(m.likes)                 AS likes,
       MIN(m.created_date)          AS first_model_date
FROM organizations o
JOIN models m ON m.author = o.author
GROUP BY o.author, o.org_name, o.org_type, o.is_indian;
