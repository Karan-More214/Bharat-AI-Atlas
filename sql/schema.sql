-- =====================================================================
-- Bharat AI Atlas - database schema (MySQL 8+)
-- Star-schema style: 1 fact table (models), 2 dimensions, 1 bridge,
-- 1 history table that grows with every weekly snapshot.
-- =====================================================================

CREATE DATABASE IF NOT EXISTS bharat_ai_atlas
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE bharat_ai_atlas;

-- Rebuilt on every load (current state)
DROP TABLE IF EXISTS model_languages;
DROP TABLE IF EXISTS models;
DROP TABLE IF EXISTS organizations;
DROP TABLE IF EXISTS languages;

CREATE TABLE languages (
    lang_code          VARCHAR(10)   PRIMARY KEY,
    lang_name          VARCHAR(50)   NOT NULL,
    script             VARCHAR(50),
    speakers_millions  DECIMAL(8,2)  NOT NULL   -- Census 2011, first-language speakers
);

CREATE TABLE organizations (
    author      VARCHAR(200)  PRIMARY KEY,      -- Hugging Face user / org handle
    org_name    VARCHAR(200)  NOT NULL,
    org_type    VARCHAR(60)   NOT NULL,         -- Indian Research, Global Big Tech, ...
    is_indian   TINYINT       NULL              -- 1 = Indian, 0 = foreign, NULL = unknown
);

CREATE TABLE models (
    model_id            VARCHAR(200)  PRIMARY KEY,
    author              VARCHAR(200)  NOT NULL,
    model_name          VARCHAR(200),
    task                VARCHAR(60),
    task_group          VARCHAR(60),
    library             VARCHAR(60),
    license             VARCHAR(80),
    license_group       VARCHAR(60),
    base_model          VARCHAR(200),              -- model it was fine-tuned from
    base_author         VARCHAR(200),
    base_relation       VARCHAR(20),               -- finetune / adapter / quantized / merge
    is_derivative       TINYINT       NOT NULL DEFAULT 0,
    is_gated            TINYINT       NOT NULL DEFAULT 0,
    n_indic_languages   SMALLINT      NOT NULL DEFAULT 1,
    is_india_dedicated  TINYINT       NOT NULL DEFAULT 0,  -- strict rule, see src/clean.py
    downloads_30d       BIGINT        NOT NULL DEFAULT 0,
    downloads_all_time  BIGINT        NOT NULL DEFAULT 0,
    likes               INT           NOT NULL DEFAULT 0,
    is_zero_download    TINYINT       NOT NULL DEFAULT 0,
    created_date        DATE,
    created_year        SMALLINT,                  -- NULL when date_is_placeholder = 1
    date_is_placeholder TINYINT       NOT NULL DEFAULT 0,  -- 1 = HF placeholder date 2022-03-02 (created earlier)
    CONSTRAINT fk_models_author FOREIGN KEY (author) REFERENCES organizations(author),
    INDEX idx_models_year (created_year),
    INDEX idx_models_task (task_group)
);

CREATE TABLE model_languages (
    model_id   VARCHAR(200) NOT NULL,
    lang_code  VARCHAR(10)  NOT NULL,
    PRIMARY KEY (model_id, lang_code),
    CONSTRAINT fk_ml_model FOREIGN KEY (model_id)  REFERENCES models(model_id),
    CONSTRAINT fk_ml_lang  FOREIGN KEY (lang_code) REFERENCES languages(lang_code)
);

-- Kept forever: one row per model per collection date (for growth trends)
CREATE TABLE IF NOT EXISTS model_snapshots (
    snapshot_date       DATE          NOT NULL,
    model_id            VARCHAR(200)  NOT NULL,
    downloads_30d       BIGINT        NOT NULL DEFAULT 0,
    downloads_all_time  BIGINT        NOT NULL DEFAULT 0,
    likes               INT           NOT NULL DEFAULT 0,
    PRIMARY KEY (snapshot_date, model_id)
);
