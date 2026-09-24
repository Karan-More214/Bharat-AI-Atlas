# Build Guide: Bharat AI Atlas, step by step

**Project title:** Bharat AI Atlas: Mapping India's Open-Source AI Language Gap

**One-line pitch:** An end-to-end data pipeline (Python → MySQL → Power BI) that measures how much open-source AI exists for each of India's 22 official languages, who builds it, and whether anyone uses it.

**Your stack:** Python (collect + clean) → MySQL (store + analyze) → Power BI (dashboard) → GitHub + LinkedIn (share)

---

## Part 0: Tools to install (Day 1)

| # | Tool | Why | Where to get it |
|---|------|-----|-----------------|
| 1 | **Python 3.11 or 3.12** | Collect and clean data | python.org. On Windows, tick **"Add Python to PATH"** |
| 2 | **VS Code** | Write and run code | code.visualstudio.com, plus the *Python* extension |
| 3 | **MySQL Community Server 8.x** | Database | dev.mysql.com/downloads/installer. Remember the root password |
| 4 | **MySQL Workbench** | Run SQL queries visually | Included in the MySQL installer |
| 5 | **Power BI Desktop** | Dashboard | Microsoft Store (free) |
| 6 | **MySQL Connector/NET** | Lets Power BI talk to MySQL | dev.mysql.com/downloads/connector/net |
| 7 | **Git** | Version control | git-scm.com |
| 8 | **GitHub account** | Portfolio | github.com |
| 9 | **Hugging Face account** | Free API token | huggingface.co/join |
| 10 | **Canva** | LinkedIn carousel | canva.com (free) |

Check that everything works (Command Prompt):
```bash
python --version
git --version
mysql --version
```
If `mysql` is "not recognized", that's fine. You'll use MySQL Workbench instead.

---

## Part 1: Set up the project (Day 1)

### 1.1 Put the project folder somewhere simple
For example `C:\Projects\bharat-ai-atlas`. Open that folder in VS Code (File → Open Folder).

### 1.2 Create a virtual environment and install libraries
In the VS Code terminal (Ctrl + `):
```bash
python -m venv venv
venv\Scripts\activate          # Windows
# source venv/bin/activate     # Mac/Linux
pip install -r requirements.txt
```
You'll see `(venv)` at the start of the terminal line. Activate it every time you work on the project.

### 1.3 Get your Hugging Face token
huggingface.co → profile picture → **Settings → Access Tokens → Create new token** → type **Read** → copy it.

### 1.4 Create a MySQL user for the project
Open MySQL Workbench → connect as root → run:
```sql
CREATE USER 'atlas_user'@'localhost' IDENTIFIED BY 'ChooseAStrongPassword';
GRANT ALL PRIVILEGES ON bharat_ai_atlas.* TO 'atlas_user'@'localhost';
FLUSH PRIVILEGES;
```

### 1.5 Create your `.env` file
```bash
copy .env.example .env         # Windows  (Mac/Linux: cp .env.example .env)
```
Open `.env` and fill in your token and password. **`.env` is in `.gitignore`, so it never goes to GitHub.**

---

## Part 2: Define the business questions (Day 1)

A strong project starts with questions, not code. These are already in the README:

1. **Coverage:** Which Indian languages have AI models, and which are left behind (models per million speakers)?
2. **Growth:** How fast is Indic AI growing each year?
3. **Builders:** Who builds it: Indian research labs, Indian startups, global big tech, or individuals?
4. **Usage:** Are the models actually downloaded, or just published?
5. **Foundations:** How many are fine-tuned from someone else's base model, and whose?
6. **Capability gaps:** Which languages have no LLM, no speech recognition or no text-to-speech?
7. **Openness:** What licenses do they use (can businesses use them)?

---

## Part 3: Collect the data with Python (Day 2)

**Test first with a small run:**
```bash
python src/collect.py --langs mr hi --limit 20
```
Then **run the full collection**:
```bash
python src/collect.py
```
**What it does:**
- Reads the 22 languages from `config/languages.csv` (some have two tag codes, e.g. Konkani `kok` and `gom`).
- Calls the Hugging Face API for every model tagged with each language.
- Keeps only the fields needed: author, task, downloads (last 30 days and all-time), likes, license tags, base model tags, created date.
- Retries automatically on network errors.
- Saves a dated file: `data/raw/models_raw_YYYY-MM-DD.csv`.

Hindi has the most models, so the full run can take several minutes.

> **Interview tip:** Explain *why* you save raw data untouched. It lets you re-clean later without calling the API again, and each dated file is a historical snapshot.

---

## Part 4: Clean and transform (Day 3–4)

```bash
python src/clean.py
```
**What it does:**
| Step | Why it matters |
|---|---|
| Removes duplicates (a model tagged with 5 languages appears 5 times in raw data) | One row per model in the fact table |
| Builds a **bridge table** `model_languages` | Correct many-to-many modeling, a strong talking point |
| Extracts the **license** from tags and groups it (Permissive / Non-commercial / ...) | Answers "can businesses use it?" |
| Extracts the **base model** (`base_model:finetune:google/...`) | Answers "whose foundations?" |
| Groups 20+ Hugging Face task names into ~12 business-friendly task groups | Cleaner charts |
| Flags zero-download models and counts languages per model | Ready-made metrics |
| Joins the author mapping to classify builders | Indian vs global, research vs startup |
| Runs data-quality checks (unique IDs, valid language codes) | Shows data-quality discipline |

### 4.1 Label the builders (the step that makes your project unique)
Open `reports/top_unmapped_authors.csv`. It lists the most-downloaded authors not yet classified. For the top ~50–100, look each one up on huggingface.co and add a row to `config/author_mapping.csv`:
```
author,org_name,org_type,is_indian
someorg,Some Organisation,Indian Startup & Company,1
```
Use these `org_type` values consistently:
`Indian Research & Academia`, `Indian Startup & Company`, `Indian Open Community` (volunteer/community groups such as OdiaGenAI), `Global Big Tech`, `Global AI Company`, `Global Research & Open Community`, `Model Repackager` (accounts that mainly convert/quantize other models, e.g. mlx-community, bartowski), `Individual`

Then run `python src/clean.py` again. Aim for **80%+ of downloads classified**. It's manual work, and that's what makes your dataset different from anyone else's.

---

## Part 5: Load into MySQL (Day 5)

```bash
python src/load_to_sql.py
```
**What it does:**
1. Runs `sql/schema.sql`: creates the database and 5 tables with primary and foreign keys.
2. Loads the processed CSVs (parents first because of foreign keys).
3. Appends today's rows to `model_snapshots`, the history table that grows every week.
4. Creates 3 reporting views from `sql/views.sql`.

**Data model:**
```
organizations 1 ──< models 1 ──< model_languages >── 1 languages
                        │
                        └──< model_snapshots (history, one row per model per week)
```

Check it in Workbench:
```sql
USE bharat_ai_atlas;
SELECT COUNT(*) FROM models;
SELECT * FROM vw_language_coverage;
```

**From now on, one command runs everything:**
```bash
python src/run_pipeline.py
```

---

## Part 6: Analyze with SQL (Week 2)

Open `sql/analysis.sql` in Workbench and run each query (cursor on the query → **Ctrl + Enter**). There are 25 queries: 21 organized by the 7 business questions, plus section 8 on dedicated vs multilingual models. SQL skills they show:

| Skill | Where |
|---|---|
| Joins across 3–4 tables | 2.2, 3.3, 7.1 |
| CTEs (`WITH`) | 2.1, 3.3, 4.2, 4.3 |
| `RANK`, `DENSE_RANK`, `ROW_NUMBER` | 1.1, 1.2, 3.2, 3.3 |
| `LAG` for growth | 2.1, 7.1 |
| Running totals `SUM() OVER (ORDER BY ...)` | 2.1, 2.2, 4.3 (Pareto) |
| Percent of total `SUM() OVER ()` | 1.4, 3.1, 5.1, 6.2 |
| `NTILE` segmentation | 1.3 |
| Conditional aggregation `CASE WHEN` | 2.3, views |
| Views for BI | `views.sql` |

**Write your findings as you go.** Create `docs/findings.md` and note the numbers:
- "X of 22 languages have fewer than N models"
- "Hindi has X models but only Y per million speakers, vs Z for Assamese"
- "The top 10 models get X% of all downloads"
- "X% of models have never been downloaded"
- "X% are fine-tuned from Global Big Tech base models"
- "N languages have no speech recognition model"

These sentences become your README, your dashboard subtitles and your LinkedIn post.

**Watch out for:**
- **Sanskrit** has very few native speakers (Census ~0.02M), so its "per million speakers" number is huge. Exclude it from that one chart and say why.
- **Bengali, Urdu, Nepali, Punjabi, Sindhi** are also spoken outside India, so some models are built for Bangladesh, Pakistan or Nepal. Frame the metric as "AI available in the language", not "AI built for India".

---

## Part 7: Build the Power BI dashboard (Week 3)

### 7.1 Connect to MySQL
Power BI Desktop → **Get Data → MySQL database** → Server: `localhost`, Database: `bharat_ai_atlas` → enter the atlas_user credentials (Database tab).

Select: `languages`, `organizations`, `models`, `model_languages`, `model_snapshots`, `vw_language_coverage`, `vw_org_summary` → **Load**.

*If the MySQL connector gives trouble:* use **Get Data → Text/CSV** on the files in `data/processed/` instead. The dashboard works the same.

### 7.2 Set up relationships (Model view)
| From | To | Cardinality | Cross-filter |
|---|---|---|---|
| organizations[author] | models[author] | 1 : * | Single |
| models[model_id] | model_languages[model_id] | 1 : * | **Both** |
| languages[lang_code] | model_languages[lang_code] | 1 : * | Single |
| models[model_id] | model_snapshots[model_id] | 1 : * | Single |

Setting "Both" on the bridge is what lets a language slicer filter models. Mention it in interviews.

### 7.3 Create a measures table and DAX measures
Home → Enter data → name it `_Measures` → then New measure:

```DAX
Total Models = DISTINCTCOUNT ( models[model_id] )

Total Downloads = SUM ( models[downloads_all_time] )

Downloads 30d = SUM ( models[downloads_30d] )

Builders = DISTINCTCOUNT ( models[author] )

Languages Covered = DISTINCTCOUNT ( model_languages[lang_code] )

Zero-Download % =
DIVIDE ( CALCULATE ( [Total Models], models[is_zero_download] = 1 ), [Total Models] )

Derivative % =
DIVIDE ( CALCULATE ( [Total Models], models[is_derivative] = 1 ), [Total Models] )

Models per Million Speakers =
DIVIDE ( [Total Models], SUM ( languages[speakers_millions] ) )

Indian Builder Download Share =
DIVIDE ( CALCULATE ( [Total Downloads], organizations[is_indian] = 1 ), [Total Downloads] )

Cumulative Models =
CALCULATE (
    [Total Models],
    FILTER ( ALL ( models[created_year] ), models[created_year] <= MAX ( models[created_year] ) )
)

YoY Growth % =
VAR cur  = [Total Models]
VAR prev = CALCULATE ( [Total Models], models[created_year] = MAX ( models[created_year] ) - 1 )
RETURN DIVIDE ( cur - prev, prev )
```
Format the % measures as percentages (Measure tools → %).

### 7.4 The four pages
Use one consistent theme (View → Themes), and give every page a **title plus a one-line insight text box** (e.g. *"Hindi has the most models, but per speaker it ranks near the bottom"*).

**Page 1: Executive Overview**
- KPI cards: Total Models, Languages Covered, Builders, Total Downloads, Zero-Download %
- Line chart: Cumulative Models by created_year
- Bar chart: Total Models by languages[lang_name] (top 10)
- Slicers: lang_name, task_group, org_type, created_year

**Page 2: The Language Gap (your headline page)**
- Bar chart: Models per Million Speakers by lang_name, sorted ascending (filter out Sanskrit, with a footnote)
- Scatter: X = speakers_millions, Y = total_models, size = downloads_all_time (from `vw_language_coverage`). Languages far below the trend are underserved.
- Table: lang_name, llm_models, asr_models, tts_models with **conditional formatting** (0 = red). This is the capability-gap matrix.

**Page 3: Who Builds Indic AI**
- Donut: Total Downloads by org_type
- Bar: top 15 org_name by Total Downloads (Top N filter)
- Matrix: rows lang_name, columns org_type, values Total Models (heatmap formatting)
- Card: Indian Builder Download Share

**Page 4: Usage & Foundations**
- Bar: Total Models vs Total Downloads by task_group (supply vs demand)
- Bar: top base_author for derivative models (filter is_derivative = 1)
- Donut: license_group
- Cards: Zero-Download %, Derivative %
- (After 2+ weekly runs) line chart: Downloads 30d by snapshot_date

### 7.5 Finish
- Add tooltips and drill-through from a language to its model list.
- Save as `dashboard/bharat_ai_atlas.pbix`.
- Export screenshots of every page to `dashboard/screenshots/`.
- Optional: record a 20–30 second screen GIF (ScreenToGif, free) of you clicking slicers. It's great for LinkedIn and the README.

---

## Part 8: Automate weekly refresh (optional, recommended)

Windows **Task Scheduler** → Create Basic Task → Weekly →
- Program: `C:\Projects\bharat-ai-atlas\venv\Scripts\python.exe`
- Arguments: `src\run_pipeline.py`
- Start in: `C:\Projects\bharat-ai-atlas`

After 4+ weeks, query 7.1 and the trend chart show real growth, which gives you a second LinkedIn post.

---

## Part 9: Publish on GitHub (Week 4)

1. On github.com → **New repository** → name `bharat-ai-atlas` → Public → don't add a README (you have one).
2. In the terminal:
```bash
git init
git add .
git commit -m "Bharat AI Atlas: pipeline, SQL analysis and Power BI dashboard"
git branch -M main
git remote add origin https://github.com/<your-username>/bharat-ai-atlas.git
git push -u origin main
```
3. Before pushing, check that `git status` does **not** list `.env`.
4. Fill the `[X]` placeholders in `README.md` with your real findings and add the screenshots/GIF.
5. On the repo page: add a description, topics (`data-analysis`, `power-bi`, `sql`, `python`, `huggingface`, `indic-nlp`, `india`), and **pin the repo** on your GitHub profile.

---

## Part 10: LinkedIn launch

### 10.1 Carousel (Canva, 8 slides, 1080×1350)
1. **Hook:** "India has 22 official languages. I analyzed every open-source AI model built for them."
2. **Why it matters:** hundreds of millions of Indians don't use English online.
3. **The gap:** models-per-million-speakers chart
4. **Left behind:** capability matrix (no LLM / no speech / no TTS)
5. **Who builds it:** org-type split plus the top builders
6. **Reality check:** "X% of models have never been downloaded"
7. **How I built it:** pipeline diagram (Hugging Face API → Python → MySQL → Power BI)
8. **CTA:** "Full code + dashboard on GitHub. Which language surprised you?"

### 10.2 Post text (fill in your numbers)
```
India has 22 official languages.
I analyzed [X,XXX] open-source AI models built for them on Hugging Face.

What I found:
→ Hindi has the most models, but per speaker it ranks #[X] of 22
→ [N] languages still have no speech-recognition model
→ The top 10 models get [X]% of all downloads
→ [X]% of models have never been downloaded

How I built it:
• Python: pulled data from the Hugging Face API, cleaned [X,XXX] records
• MySQL: star schema + 25 analysis queries (window functions, CTEs)
• Power BI: 4-page interactive dashboard

The biggest insight: [your most surprising finding in one line].

Code + dashboard: [GitHub link]

Which Indian language do you think needs AI the most?

#DataAnalytics #PowerBI #SQL #Python #AI #IndicNLP #DataAnalyst
```

### 10.3 Posting tips
- Post Tuesday–Thursday, 8–10 AM IST.
- Put the GitHub link in the **first comment** if you notice lower reach with links in the post.
- Reply to every comment in the first 2 hours.
- Tag organizations you mention (e.g. AI4Bharat) only if your finding about them is accurate and respectful.
- Add the project to your LinkedIn **Featured** section and your resume.

---

## Part 11: Interview talking points
- **Why the bridge table?** One model supports many languages. Without a bridge you'd double-count models or lose languages.
- **Why snapshots?** The API only gives current numbers. Storing weekly snapshots creates the history needed for trend analysis.
- **Why manual author labeling?** No API says "this is an Indian startup". Domain research turned raw handles into a business dimension.
- **Limitations you're aware of:** only language-*tagged* models are counted; `downloads` is the last 30 days while `downloads_all_time` is cumulative; some languages are shared with neighboring countries; Census 2011 speaker counts.
- **What you'd do next:** add datasets (not just models), compare against Hugging Face Spaces (apps), or build a "language readiness score".

---

## Timeline

| Week | Days | Work |
|---|---|---|
| 1 | 1 | Install tools, set up project, `.env`, MySQL user |
| 1 | 2 | Test + full collection |
| 1 | 3–4 | Clean, label top authors, re-clean |
| 1 | 5 | Load to MySQL, check views |
| 2 | 1–5 | Run and understand all SQL queries, write `docs/findings.md` |
| 3 | 1–5 | Power BI: relationships, DAX, 4 pages, screenshots/GIF |
| 4 | 1–2 | README with real findings, push to GitHub |
| 4 | 3–4 | Canva carousel + post |
| 4 | 5 | Publish; set up weekly refresh |

---

## Troubleshooting
| Problem | Fix |
|---|---|
| `ModuleNotFoundError` | Activate the venv: `venv\Scripts\activate`, then `pip install -r requirements.txt` |
| `Access denied for user` | Check DB_USER / DB_PASSWORD in `.env` and the GRANT in Part 1.4 |
| `cryptography package is required` | `pip install cryptography` (already in requirements) |
| Power BI can't find a MySQL driver | Install MySQL Connector/NET, restart Power BI, or use the CSV route |
| API errors / 429 | Add your HF token in `.env`; the script retries automatically. Run again later |
| `list_models() got an unexpected keyword` | `pip install -U huggingface_hub` |
| Foreign key error on load | Run `clean.py` again before `load_to_sql.py` (the files must come from the same run) |
