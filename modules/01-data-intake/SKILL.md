---
name: empirical-data-intake
description: Empirical data intake for raw data triage in econometrics and public-health / epidemiology research. Use when the user has just received a raw dataset (.csv, .dta, .xlsx, .sav, .sas7bdat, .parquet) and does not yet know what cleaning is needed or which downstream pipeline — 00 StatsPAI / 00.1 Python / 00.2 Stata / 00.3 R — to route to. Runs a data-driven 5-slot conditional Q&A (discipline, research design, unit of observation, focal variables, software target), where slots that the data already answers are skipped or pre-filled, and slots that the data cannot answer are surfaced as multiple-choice questions. Executes the deterministic 80% of Step 1 cleaning that the four flagships' references treat as user-decided — column rename to snake_case, automatic dtype coercion for unambiguous cases, duplicate detection, primary-key validation, panel structure inference, missing-rate inventory, outlier flagging (flag only, not winsorize). Produces four output files — cleaned dataset in the Slot-5 native format (.dta / .parquet / .rds), an always-on `cleaned_dataset.xlsx` 7-sheet inspection workbook for visual spot-check, `data_contract.yaml` describing verified dataset properties, and `routing_recommendation.md` pointing to the correct flagship and mode. Holds the public-health / epidemiology cleaning patterns the four flagships' Step 1 references omit — index date / time-zero alignment, censoring vs missing distinction, person-time construction, washout periods, immortal-time-bias detection, ICD/CPT/ATC code normalization. Does NOT replicate flagship Step 1 — multiple imputation, advanced outlier methods, detailed merge mechanics, event-study time alignment all hand off to the matched flagship by reference. Optionally offers a literature-consultation phase that, with explicit user consent, searches academic sources (preferring local skills like arxiv-database / perplexity-search / systematic-literature-review when installed, falling back to OpenAlex / arXiv MCP / WebSearch) for methodological precedent on each unresolved_decisions item; the phase only writes a markdown advisory report and never modifies analysis data. Triggers on phrases like "原始数据", "数据清洗", "不知道用哪个 pipeline", "怎么开始", "raw data", "data intake", "data triage", "data wrangling", "empirical data cleaning", "panel attrition", "cohort 数据", "index date", "public health data", "流行病学数据", ".dta 怎么处理", "this data is a mess", "查文献怎么处理缺失", "literature consultation".
license: CC BY-SA 4.0
---

# Empirical Data Intake — Routing-First Cleaning Skill

This skill is the **upstream triage layer** for empirical research. It sits between the user's raw data file and the four flagship analysis pipelines (`00`, `00.1`, `00.2`, `00.3`). Its job is to convert "a file someone handed me" into "an analysis-ready dataset, a verified contract, and a routing decision".

## Position in the repository

```
raw data file ──▶ 00.4 (this skill) ──▶ cleaned dataset + contract + routing ──▶ 00 / 00.1 / 00.2 / 00.3
```

This skill **complements** the flagships; it does not replace any of them. The flagship Step 1 references (`00.1/references/01-data-cleaning.md` etc.) remain the canonical execution manuals for advanced cleaning. This skill is the **decision layer**: what to do, when to ask, which flagship to send to.

## When to use

Use this skill when **any** of these are true:

- User just received a raw data file and asks "where do I start?"
- User does not know which of `00 / 00.1 / 00.2 / 00.3` to use
- User is doing a **public-health / epidemiology** study (Mode A) — the four flagships' cleaning references do not cover epi-specific cleaning
- User says the data needs cleaning but cannot articulate what kind of cleaning
- Data has obvious issues (missing values, duplicates, ambiguous types) that the user has not explicitly diagnosed

Do NOT use this skill when:

- User has already produced an analysis-ready dataset and wants to run regressions → go straight to flagship
- User asks for a specific cleaning operation in isolation ("winsorize at 1/99%", "run MICE on missing wage") → flagship reference handles it
- User is asking for purely descriptive statistics on a dataset they already trust → flagship Step 3 handles it

---

## The 5-slot conditional Q&A

The Q&A is a **decision graph, not a fixed questionnaire**. Each slot has three modes:

- **AUTO** — the data already answers it; do not ask
- **CONFIRM** — the data strongly suggests an answer; ask user to confirm in one yes/no
- **ASK** — the data cannot answer it; surface as multiple choice

Before any question, **always inspect the data first** (Section "Static inspection" below). The inspection result determines which slots are AUTO / CONFIRM / ASK.

### Slot 1 — Discipline (always ASK)

> 你这份研究是 **(A) 经济学 / 计量 / 金融 / 政治学等社科默认轨**, 还是 **(B) 公共卫生 / 流行病学 / 临床研究**?

This determines:
- Whether to invoke Mode A epi-specific cleaning patterns (`references/01-mode-a-epi-patterns.md`)
- Whether the variable name is "treatment" (econ) or "exposure" (epi)
- Routing target: flagship default mode vs Mode A

Cannot be inferred from data alone. Always ask.

### Slot 2 — Research design (CONFIRM if data suggests, ASK otherwise)

Inspection signals:

| Data signal | Likely design | Action |
|---|---|---|
| Single (id, time) candidate key with high uniqueness, time has 5+ distinct values | Panel | CONFIRM ("This looks like panel data with units `{id}` over `{time}`. Correct?") |
| No date / time column at all | Cross-section | CONFIRM ("No time variable detected — this is a cross-section. Correct?") |
| Single time series (one entity, many time points) | Time series | CONFIRM |
| Discipline=epi + has columns matching `index_date|enrol|baseline|follow*|event_date|censor` | Cohort with index date | CONFIRM |
| Time variable but no consistent (id, time) key | Repeated cross-section | CONFIRM |
| None of the above patterns | Unknown | ASK with all 5 options |

If user says "I'm not sure" on confirmation, fall through to ASK with all options.

When discipline=epi, replace "panel" wording with "longitudinal cohort" in the confirm message.

### Slot 3 — Unit of observation (CONFIRM)

After Slot 2 is set, inspect the strongest candidate primary key. Ask:

> 看起来每一行代表 **一个 {推断单位} 的一个 {时间点}** (主键候选: `{id_col}, {time_col}`). 对吗?

Where `推断单位` is one of: 个人, 家庭, 公司, 国家, 患者, 患者-访视, 学校, observation. The inference is by column name heuristic (e.g., `worker_id` → 个人; `firm_id` → 公司; `patient_id` → 患者) and uniqueness pattern. If no `id_col` is detectable, ASK directly with multiple choice.

### Slot 4 — Focal variables (CONDITIONAL on Slot 2 + 1)

This slot's content depends entirely on the prior answers:

| Slot 2 answer | Slot 4 content |
|---|---|
| Cross-section + causal | Outcome + treatment + key controls |
| Panel + causal (econ) | Outcome + treatment + treatment start time + (id, time) key |
| Cohort + index date (epi) | Outcome (event) + **exposure** (not "treatment") + index date column + censoring column |
| Time series prediction | Target variable + frequency (D/W/M/Q/A) — no treatment |
| Repeated cross-section | Outcome + group identifier + time |
| Descriptive / inequality | Focal variable + group / stratification dimension — **no treatment** |
| Pure exploratory | SKIP entire slot — go to "exploratory mode" |

Within each branch, use **column-name pattern matching** to pre-fill candidates:

| User intent | Auto-suggest candidates from columns matching |
|---|---|
| Outcome (econ) | `wage`, `income`, `earnings`, `output`, `employment`, `y` |
| Outcome (epi) | `event`, `mortality`, `outcome`, `death`, `incidence`, `complication` |
| Treatment (econ) | binary 0/1 column with name in `treat`, `policy`, `program`, `intervention` |
| Exposure (epi) | binary or continuous in `exposure`, `dose`, `treatment_initiated`, `drug_*` |
| Index date (epi) | `index_date`, `enrol*_date`, `baseline_date`, `t0` |
| Censor (epi) | `censor`, `lost_followup`, `last_seen` |

Format the question as: "Outcome 是 `wage` 吗? Treatment 是 `training` 吗? (y / 选其他列 / 我也不确定)". Combine into one question, do not ask serially.

If user says "我也不确定", offer **the top 3 candidates by name pattern + dtype**, plus "skip — flag for later".

### Slot 5 — Software target (CONFIRM if file extension reveals, ASK otherwise)

| File extension | Default target |
|---|---|
| `.dta` | Stata (route to 00.2) |
| `.rds`, `.RData` | R (route to 00.3) |
| `.parquet`, `.feather` | Python (route to 00.1 or 00 StatsPAI) |
| `.csv`, `.xlsx`, `.sav`, `.sas7bdat` | ASK |

When ASK, present 4 options: Python (general), Python (StatsPAI), Stata, R.

When CONFIRM (e.g. `.dta`), the message is: "文件是 `.dta`, 默认走 Stata (00.2). 确认吗?".

---

## Prerequisites (Python environment)

Required (hard fail if missing):
- `pandas >= 2.0`
- `numpy`
- `pyyaml`
- `openpyxl` (for `.xlsx` read **and** write — the always-on inspection workbook needs it)

Conditional:
- `pyreadstat` — only if source is `.sav` (SPSS) or `.sas7bdat` (SAS). Pandas's built-in `read_stata` handles `.dta` so pyreadstat is optional even there.
- `scipy` — only used for the MCAR Welch t-test on focal-variable missingness. If absent, **fall back to a numpy manual implementation** with the |t|>1.96 large-n approximation (see § "MCAR hint fallback" below).
- `pyarrow` — only if Slot 5 = Python (writes `.parquet` native). Skip silently if absent and the chosen target is not parquet.

If a hard-required package is missing, intake stops with a clear install hint. If a conditional package is missing AND its file type is requested, stop with a hint. If a conditional package is missing AND not needed for this run, proceed silently.

---

## Static inspection (always run before any question)

Before Slot 1, **always perform** this inspection and store results for use in slot decisions. Choose the inspection language based on the file extension (does not require user choice yet):

```python
# Run this regardless of user's eventual software target
from pathlib import Path
import pandas as pd

def inspect_file(file_path: str) -> dict:
    path = Path(file_path)
    ext  = path.suffix.lower()

    # --- Load ---
    if ext == ".dta":
        df = pd.read_stata(path, convert_categoricals=False)
    elif ext == ".sav":
        import pyreadstat
        df, _meta = pyreadstat.read_sav(path)
    elif ext == ".sas7bdat":
        import pyreadstat
        df, _meta = pyreadstat.read_sas7bdat(path)
    elif ext == ".parquet":
        df = pd.read_parquet(path)
    elif ext in {".csv", ".tsv"}:
        sep = "\t" if ext == ".tsv" else ","
        df = pd.read_csv(path, sep=sep, low_memory=False)
    elif ext == ".xlsx":
        # Multi-sheet handling — never silently take Sheet1 if there are alternatives
        xl = pd.ExcelFile(path)
        sheet = xl.sheet_names[0]
        if len(xl.sheet_names) > 1:
            print(f"[intake] WARNING: {len(xl.sheet_names)} sheets found ({xl.sheet_names}); "
                  f"defaulting to '{sheet}'. To override, pass sheet_name explicitly.")
        df = pd.read_excel(path, sheet_name=sheet)
    else:
        raise ValueError(f"Unsupported file: {ext}")

    # --- Helpers ---
    def is_string_like(s):
        # pandas 2.x: string columns may be 'object' or 'string'/'string[pyarrow]'
        return pd.api.types.is_string_dtype(s) or s.dtype == object

    def looks_like_id_name(c):
        cl = c.lower()
        return cl == "id" or cl.endswith("_id") or cl in {"uid", "uuid", "key"}

    def looks_like_time_name(c):
        cl = c.lower()
        return cl in {"year","date","time","ym","quarter","month","wave","period","t"}

    # --- Single-column primary-key candidates (filter out numeric measures) ---
    # An "ID-shaped" single column must look like an ID by name OR be integer/string,
    # not a continuous numeric measure that happens to be unique by coincidence.
    single_pkey_candidates = []
    for c in df.columns:
        if not (df[c].is_unique and df[c].notna().all()):
            continue
        is_id_name  = looks_like_id_name(c)
        is_int_like = pd.api.types.is_integer_dtype(df[c])
        is_str_like = is_string_like(df[c])
        if is_id_name or is_int_like or is_str_like:
            single_pkey_candidates.append(c)

    # --- Composite (id, time) primary-key candidate ---
    id_cols   = [c for c in df.columns if looks_like_id_name(c)]
    time_cols = [c for c in df.columns
                  if looks_like_time_name(c) or pd.api.types.is_datetime64_any_dtype(df[c])]
    composite_pkey = None
    for ic in id_cols:
        for tc in time_cols:
            if not df.duplicated(subset=[ic, tc]).any() and df[ic].notna().all() and df[tc].notna().all():
                composite_pkey = (ic, tc)
                break
        if composite_pkey:
            break

    # --- Binary 0/1 columns (treatment-candidate detection) ---
    binary_01_cols = [c for c in df.columns
                       if df[c].dropna().nunique() == 2
                       and set(df[c].dropna().unique()) <= {0, 1, True, False, 0.0, 1.0}]
    # Two-valued text columns (e.g. 东南侧/西北侧) — flag separately
    binary_text_cols = [c for c in df.columns
                         if is_string_like(df[c])
                         and df[c].dropna().nunique() == 2]

    return {
        "file_path":              str(path),
        "ext":                    ext,
        "n_rows":                 len(df),
        "n_cols":                 df.shape[1],
        "columns":                list(df.columns),
        "dtypes":                 df.dtypes.astype(str).to_dict(),
        "missing_rate":           df.isna().mean().to_dict(),
        "n_unique":               df.nunique().to_dict(),
        "single_pkey_candidates": single_pkey_candidates,    # ID-shaped unique cols only
        "composite_pkey":         composite_pkey,            # (id_col, time_col) or None
        "candidate_id_cols":      id_cols,
        "candidate_time_cols":    time_cols,
        "binary_01_cols":         binary_01_cols,
        "binary_text_cols":       binary_text_cols,
        "epi_signal_cols": [c for c in df.columns
                              if any(k in c.lower() for k in
                                     ["index_date","baseline","enrol","followup","censor","event_date","t0"])],
        "string_cols":  [c for c in df.columns if is_string_like(df[c])],
        "_df":          df,    # intentional: downstream cleaning needs the actual DataFrame
    }
```

**Bug-fix log for this code (vs v0.1)**:
- Composite primary-key detection: v0.1 only found single-column unique cols, which on panel data wrongly flagged continuous numeric measures (e.g., `Y`, `X`) as "primary keys" because their 1970 floats happened to be unique. v0.2 filters single-column candidates to ID-shaped names / int / string only, AND separately searches for `(id_col, time_col)` composite keys.
- `string_cols` detection: v0.1 used `dtype == object`, which **misses pandas 2.x string-dtype columns**. v0.2 uses `pd.api.types.is_string_dtype(s) or s.dtype == object`.
- Binary detection: v0.1 only caught 0/1; v0.2 separately catches two-valued text columns (e.g. `东南侧/西北侧`) as `binary_text_cols` for moderator-candidate identification.
- `path` variable: v0.1 referenced `path` without defining it; v0.2 wraps in `inspect_file(file_path)` with `path = Path(file_path)`.
- xlsx multi-sheet: v0.1 silently read Sheet1; v0.2 prints a warning when multiple sheets exist.

This inspection is **silent** in user-facing output — show the user a one-page summary table (rows×cols, missing summary, top candidate keys, suspected design, suspected discipline), not the dict.

---

### MCAR hint fallback (when scipy missing)

If `scipy` is not installed, use this numpy-only implementation for the focal-variable MCAR check:

```python
import numpy as np

def welch_t_manual(a, b):
    """Welch's t-statistic without scipy. For large n (>30 each), |t|>1.96 ≈ p<0.05."""
    a = np.asarray(a)[~np.isnan(np.asarray(a, dtype=float))]
    b = np.asarray(b)[~np.isnan(np.asarray(b, dtype=float))]
    if len(a) < 2 or len(b) < 2:
        return np.nan
    se = np.sqrt(a.var(ddof=1)/len(a) + b.var(ddof=1)/len(b))
    return (a.mean() - b.mean()) / se if se > 0 else 0.0
```

Threshold: `|t| > 1.96` flags non-MCAR at α≈0.05 with normal approximation (valid for n_miss > 30 and n_obs > 30, which is the usual case).

---

## Execution scope — the 80% intake does

Auto-execute (no user choice needed) once Slots 1–5 are resolved:

| Action | What | Why auto |
|---|---|---|
| **Column rename** | `janitor::clean_names` equivalent — strip whitespace, lowercase, snake_case, dedupe column names | Mechanical, no judgment |
| **Dtype coercion (unambiguous)** | Numeric strings with `[0-9.,$%]` → numeric; `\d{4}-\d{2}-\d{2}` strings → datetime | Mechanical |
| **Whitespace + encoding cleanup** | Strip leading/trailing whitespace, fix mojibake on UTF-8 round-trip | Mechanical |
| **Duplicate detection** | Report exact duplicates and panel-key duplicates | Inform, then ask only for resolution |
| **Primary-key validation** | If user's Slot 3 unit + Slot 2 design implies a key, assert uniqueness; **stop with error if violated** | Hard prerequisite |
| **Panel structure check** | If panel: compute coverage, gaps, entry/exit; report (do not force balance) | Diagnostic, no decision |
| **Missing-rate inventory** | Compute per-column missing rate, classify into <5% / 5–30% / >30% buckets, flag focal-variable missingness for MCAR hint | Diagnostic |
| **Outlier flag** | Compute z-score and IQR flags on numeric variables; **only add `*_outlier_z4` and `*_outlier_iqr` columns**, do NOT winsorize or trim | Decision is method-dependent — flagship handles |
| **Sample log initialization** | Create `sample_log = [("0. raw", n_rows)]`; record any rows the intake itself drops | Reproducibility |

Conditional-execute (ask only when data leaves it ambiguous):

| Trigger | Question |
|---|---|
| Duplicates on panel key detected | "How to resolve? (A) keep most recent (B) aggregate within key (C) redefine key (D) abort and inspect" |
| String column with > 100 unique values that looks categorical | "Is `{col}` a free-text field or a categorical variable?" |
| Date string with ambiguous format (`01/02/2020` could be Jan 2 or Feb 1) | "Date format: MDY or DMY?" |
| Mixed encoding detected | "Detected mixed encoding in column `{col}` — fix to UTF-8?" |

---

## What intake does NOT do (hand off to flagship)

Explicitly delegate the following to the matched flagship's Step 1 reference:

- **Multiple imputation (MICE / `mi` / `mice`)** — flagship has full setup; intake only flags missingness pattern
- **Winsorize / trim / cap** — Step 2 of flagship; intake only flags outliers
- **Heckman selection / IPW for MNAR** — flagship Step 5; intake only hints at MCAR plausibility
- **Detailed merge with auxiliary data** — flagship Step 1 has `validate=` / `assert()` / `relationship` patterns; intake handles only the focal dataset
- **Event-study time alignment** — flagship Step 2; intake only validates that event time can be constructed
- **Within-group outlier detection (e.g. by industry-year)** — flagship; intake does global only
- **Survey weights handling** — out of scope for v0; flag and note in `unresolved_decisions`

If user attempts any of these inside intake, redirect: "This belongs in {flagship} Step {N}. Intake will hand off the contract first."

---

## Mode A — Public-health / epidemiology cleaning patterns

This is where intake does **more** than the flagships, because their Step 1 references omit it entirely. Full content in [`references/01-mode-a-epi-patterns.md`](references/01-mode-a-epi-patterns.md). Triggered when Slot 1 = epi.

Mode A intake additionally checks:

| Check | What | Why |
|---|---|---|
| **Index date present and parseable** | `index_date` (or named equivalent) is non-null for all rows; parsed as date | All time calculations relative to t0 |
| **Time-zero alignment** | Person-time starts at index date, not at calendar enrollment, not at first record | Avoid immortal time bias |
| **Censoring vs missing** | `event_date` missing → check `censor_date` exists; if both null, raise | Survival analysis cannot run on ambiguous status |
| **Person-time construction** | If long format, verify (id, start, end) intervals do not overlap or gap | Cox / KM require valid risk sets |
| **Washout period** | If user declared washout, drop person-time before washout end and log | Standard exposure-window convention |
| **ICD / CPT / ATC code normalization** | Strip dots, leading zeros, hyphens; flag codes that do not match a known regex | Diagnosis codes are the #1 epi data-quality issue |
| **Immortal-time-bias detection** | If exposure is time-varying and person-time before exposure is coded as exposed → raise | Methodological red flag |

These checks are **run automatically** when Slot 1 = epi; user is shown results, asked to confirm interpretation only when ambiguous.

---

## Literature consultation (optional, runs after Mode A and before output)

If `unresolved_decisions` is non-empty after the cleaning + Mode A checks complete, intake offers an optional **literature consultation** phase that produces a methodological-precedent report based on academic search.

This phase is **always opt-in** (default off). It does not modify any data field — it only writes a markdown report and augments the contract with an audit trail.

Full content in [`references/02-literature-consultation.md`](references/02-literature-consultation.md). Summary:

### Trigger

```
if len(unresolved_decisions) > 0:
    ask user: "I found {N} unresolved issues. Want me to search the literature for how others have handled these? [Y/N]"
    if user replies Y:
        run literature consultation phase
```

### 4-question research-context elicitation

Before any literature query, ask the user 4 questions to make searches precise:

1. **Research question** (one sentence) — required for non-trivial queries
2. **Identification strategy** — TWFE / DID / IV / RDD / PSM / target_trial_emulation / descriptive / other
3. **Key references already known** (1–5 papers) — optional but raises query quality 10x
4. **Target journal tier** — top / mainstream / unspecified

The answers go into `data_contract.yaml > research_context` and can be reused by downstream modules without re-asking.

### Three-layer query strategy

```
Layer 1: scan ~/.claude/skills/ for usable lit-search skills
   priority chain: systematic-literature-review → perplexity-search →
                   arxiv-database / biorxiv-database → research-lookup → parallel-web
   if any found, invoke them — STOP HERE if Layer 1 succeeds

Layer 2: external MCP / Claude Code built-in tools
   priority chain: OpenAlex MCP → arXiv MCP → WebSearch (built-in) → WebFetch
   trigger: only when Layer 1 returns nothing usable

Layer 3: Claude internal training knowledge (last-resort fallback)
   trigger: only when both Layer 1 and Layer 2 are unavailable
   confidence MUST be marked as `medium` or `low` in the output
   MUST add explicit disclaimer to the report header
```

Each layer's invocation is logged to the contract.

### Output

`intake/literature_recommendations.md` — for each `unresolved_decisions` item, lists 3–5 relevant papers with:
- Citation (author, year, journal)
- Their approach
- Why it's relevant to the user
- Which downstream module should apply it
- Paper-citation template ready to paste into the user's manuscript

### Contract integration

Two fields are added to `data_contract.yaml`:

- `research_context` — the 4 user answers (downstream modules read this to avoid re-asking)
- `literature_consultation` — full audit trail (timestamps, query strings, layers used, skills invoked, paper counts)

### Invariants for this phase

1. Never modifies any data field — only writes markdown + augments yaml
2. Never triggers without explicit user consent
3. Always logs every external call (skill / MCP / WebSearch invocation, query string, return count)
4. Layer 3 outputs MUST carry `confidence: medium|low` and a disclaimer
5. Reproducibility preserved: same original data + same 4 answers → same query strings (specific returns will vary as web resources update, but the query plan is reproducible)

---

## Output artifacts (the contract)

Write three files to the user's working directory under `intake/`:

### 1. `intake/cleaned_dataset.{dta|parquet|rds}` + `intake/cleaned_dataset.xlsx` (always)

Two formats are written **every time**, regardless of Slot 5:

- **Native format matching Slot 5**:  `.dta` (Stata) | `.parquet` (Python) | `.rds` (R)
- **Always-on Excel inspection workbook**: `cleaned_dataset.xlsx` with multi-sheet layout for visual spot-check before the user commits to flagship

The Excel workbook contains 7 sheets:

| Sheet | Content |
|---|---|
| `cleaned_data` | Substantive variables only (no outlier flag cols — they live in a separate sheet) |
| `outlier_flags` | `id` + `year` + `pro` + all `*_outlier_z4` / `*_outlier_iqr` columns |
| `rename_map` | original_name → new_name table (lets user verify rename decisions) |
| `missing_inventory` | column / missing_rate / n_missing |
| `outlier_summary` | per-variable z-flag and IQR-flag counts |
| `unresolved` | unresolved decisions surfaced for the flagship |
| `contract_summary` | the YAML contract flattened to key/value pairs for at-a-glance review |

The native-format file (`.dta` / `.parquet` / `.rds`) always includes:
- All original columns (renamed to snake_case)
- Auto-coerced types
- Outlier flag columns (`*_outlier_z4`, `*_outlier_iqr`)
- Missing flag columns for focal variables (`{focal}_missing`)
- For epi mode: parsed `index_date`, computed `time_to_event`, validated `censor` indicator

**Why always also write Excel?** Empirical researchers — especially in Chinese economics academia — spot-check cleaned data visually in Excel before trusting it to a Stata `.dta`. Refusing to write `.xlsx` because Slot 5 = Stata erodes trust unnecessarily. The cost is one extra file (typically smaller than the source xlsx since outlier flags are int8). Always write both.

### 2. `intake/data_contract.yaml`

Cross-language generalization of StatsPAI's `data_contract()` dict. **Canonical schema** (v0.2):

```yaml
intake_version: "0.2"
generated_at: "2026-04-29T02:30:50.876538+00:00"   # ISO-8601 UTC
source_file: "raw/panel.dta"
source_sheet: "Sheet1"                              # only for .xlsx; null otherwise
n_rows_raw: 12345
n_rows_clean: 12000
n_cols_raw: 26
n_cols_clean: 56                                    # raw + outlier flag cols added
n_outlier_flag_cols_added: 30

discipline: econ                                    # econ | epi
research_design: panel                              # cross_section | panel | time_series | cohort_index_date | repeated_cs | descriptive | exploratory
unit_of_observation: "city-year"
software_target: stata                              # python | python_statspai | stata | r

primary_key: [id, year]
key_uniqueness: 1.0                                 # must equal 1.0 (intake hard-asserts; otherwise stops)

panel_structure:
  balanced: true
  n_units: 197
  n_periods: 10
  year_range: [2014, 2023]
  coverage: 1.0
  units_with_gaps: 0

focal_vars:
  outcome: y
  main_x: x                                          # for econ
  alt_outcome: y1                                    # null if not declared
  controls: [edu, ind, fin, pepo, open, inv, hum, ind1, ind2, pgdp]
  heterogeneity: [city_cluster, resource_city, central_city]
  treatment: null                                    # null if no binary treatment; "exposure" name for epi
  treatment_note: "No binary treatment — Slot 4.3 = TWFE continuous-X"

design:
  type: two_way_fixed_effects_continuous             # or did_staggered | iv | rdd | cohort_iptw | km_cox | ...
  specification: "y = beta*x + Gamma*Controls + city_FE + year_FE + epsilon"
  cluster_level: "id (city)"

missing_pattern:                                     # flat: {col: rate}; high-missing flagged in unresolved
  city_cluster: 0.005076
  entropy_idx: 0.060914

mcar_hint_outcome: "no missingness on `y`"           # one of: "no missingness" | "likely MCAR" | "NOT MCAR — ..."
mcar_hint_alt_outcomes:                              # only for cols that have missingness
  entropy_idx: "NOT MCAR — entropy missingness differs on ind (|t|=2.81) ..."

outlier_flags:                                       # flat: {var: {n_z4, n_iqr}}
  y:    {n_z4: 31, n_iqr: 279}
  x:    {n_z4: 17, n_iqr: 105}

sample_log:                                          # list of [label, n] tuples
  - [raw, 12345]
  - [drop_missing_panel_key, 12300]
  - [drop_exact_duplicates, 12000]

# Mode A only — present iff discipline=epi
epi_checks:
  index_date_col: enrol_date
  index_date_valid: true
  n_with_missing_t0: 0
  index_date_range: ["1995-03-12", "2018-11-04"]
  time_zero_aligned: true
  n_pre_t0_events: 0
  n_pre_t0_exposures: 0
  immortal_time_risk: false
  censoring_unambiguous: true
  n_events: 487
  n_censored: 1942
  median_follow_days: 1095
  follow_time_col: follow_time
  status_col: status
  code_normalization:
    dx_code: {scheme: ICD-10, n_total: 12000, n_invalid: 7}

renames_applied:                                      # original → new column names
  Y: y
  所属地域: region

unresolved_decisions:                                 # human-readable list, surfaced for flagship
  - "tenure has 8% missingness and NOT MCAR — use MI in flagship Step 1.5"
  - "Survey weights not detected; declare in flagship before regression if applicable"

routing_recommendation:
  flagship: "00.2-Full-empirical-analysis-skill_Stata"
  mode: default                                       # default | mode_a_epi | mode_b_ml_causal
  reason: "Slot 5=Stata + balanced panel + econ + TWFE continuous → 00.2 default"
  next_step_in_flagship: "Step 1.5 (advanced missing) → Step 2 → Step 5 (reghdfe)"
```

**Schema invariants** (any deviation is a contract violation, intake should refuse to write):
- `key_uniqueness == 1.0` always — if not, intake stops before writing
- `n_rows_raw - n_rows_clean == sum of (drops in sample_log after [raw, ...])` — sample log must reconcile
- If `discipline == "epi"`, `epi_checks` block MUST be present
- If `software_target == "stata"`, all column names in `renames_applied.values()` MUST be ASCII and ≤32 chars (Stata variable name limit)
- `missing_pattern` only includes columns with non-zero missing rate (zero-missing cols are omitted to keep the contract small)

### 3. `intake/routing_recommendation.md`

A human-readable version of the routing portion above, with **explicit links** to the flagship's relevant sections. Format:

```markdown
# Intake routing recommendation

You should now invoke flagship: **00.2 Stata** (mode: default).

## Why this flagship

- File extension `.dta` → Stata native
- Detected panel structure → flagship Stata Step 5 has `reghdfe` + `csdid` + `did_imputation`
- Discipline = econ + research design = causal identification → default AER mode

## What's already done (don't redo)

- Column rename, dtype coercion, primary-key validation, duplicate handling, outlier flagging, panel structure check.

## What flagship should do next

- **Step 1.5 (Multiple imputation)**: tenure has 8% missingness, NOT MCAR. Use `mi impute chained`.
- **Step 2 (Variable construction)**: winsorize wage at 1/99% (intake only flagged outliers).
- **Step 3 (Table 1)**: balance table on training, with focus on tenure and education.
- **Step 5 (Baseline)**: `reghdfe wage training age edu tenure, absorb(worker_id year) vce(cluster worker_id)`.

## Open issues you must address in the flagship

- 23 units with year gaps. Decide whether to drop or accept unbalanced panel.
- Survey weights not detected — if applicable, declare before regression.
```

---

## Operating instructions for Claude

When this skill is invoked:

1. **First**: identify the data file from user message or working directory. If unclear, ask for the path.
2. **Run static inspection** silently. Show user a one-page summary table of: rows × cols, missing summary, top candidate keys, suspected design, suspected discipline.
3. **Walk through Slots 1–5** in order. For each slot:
   - Compute mode (AUTO / CONFIRM / ASK) from inspection
   - Skip if AUTO
   - Show single-line confirmation if CONFIRM
   - Show multiple-choice if ASK
   - **One question per turn** — never batch unrelated slots
4. **Execute the 80%** auto-cleaning pipeline. Print `[intake]` log lines for every row drop.
5. **Run Mode A checks** if Slot 1 = epi.
6. **Offer literature consultation** if `unresolved_decisions` is non-empty. Ask the user [Y/N]; if Y, run the 4-question research-context elicitation, then the three-layer query strategy. Write `intake/literature_recommendations.md` and augment the contract with `research_context` and `literature_consultation` fields. Skip silently if user declines or `unresolved_decisions` is empty.
7. **Write the four data-output files** to `<parent>/intake/`. Show the user the file paths. The four files are: `cleaned_dataset.{dta|parquet|rds}`, `cleaned_dataset.xlsx` (always), `data_contract.yaml`, `routing_recommendation.md`. (If literature consultation ran, a fifth file `literature_recommendations.md` will also exist.)
8. **Print the routing message** ("now invoke flagship 00.X — see `intake/routing_recommendation.md`").

Never:
- Silently drop rows (always print count + reason)
- Winsorize / impute (those are flagship's job)
- Skip Slot 1 (discipline is never inferable from data)
- Write to anywhere other than `intake/` and the user's specified output path

If the user's data triggers a hard error (no rows, no columns, fully duplicated keys with no resolution path), stop and report — do not produce a contract.

### Output directory convention

By default, write the four output files to `<parent-of-source-file>/intake/` (sibling to the data folder, not inside it). For example, `/path/to/yjn/data/foo.xlsx` → outputs at `/path/to/yjn/intake/`. If `intake/` already exists from a previous run, **overwrite without prompting** but log `[intake] overwriting previous run at {path}`. If the user wants to preserve previous runs, instruct them to rename the old `intake/` to `intake_backup/` before re-invoking.

### Stata-target column-name guard

When `software_target == "stata"`, after rename, assert every column name is:
- ASCII only (no Chinese, no whitespace, no punctuation except `_`)
- Starts with a letter
- ≤ 32 characters
- Not a Stata reserved word (`if`, `in`, `using`, `_n`, `_N`, `_merge`, etc.)

If any column fails, append a numeric suffix (`col_1`, `col_2`) and log the change to `renames_applied`. **Never silently truncate** — Stata silently truncating to 32 chars has caused real-world publication bugs.

---

## Version

- **v0.3** (2026-04-29) — Adds optional literature consultation phase:
  - New phase between Mode A and Output: opt-in literature search for `unresolved_decisions`.
  - 4-question research-context elicitation (research_question / identification_strategy / key_references_known / target_journal_tier) written to `data_contract.yaml > research_context` for downstream module reuse.
  - Three-layer query fallback: local skills → external MCP/WebSearch → Claude internal knowledge.
  - New file `intake/literature_recommendations.md` produced when phase runs.
  - New contract field `literature_consultation` for full audit (timestamps, query strings, skills invoked, paper counts, layer used).
  - Refines architecture Principle 4: networking allowed for informational queries (literature, BibTeX, docs); still forbidden for any data that affects the analysis dataset or estimates.
  - See [`references/02-literature-consultation.md`](references/02-literature-consultation.md) for the full design.
- **v0.2** (2026-04-29) — Bug-fix release after first real-data test:
  - `cleaned_dataset.xlsx` 7-sheet inspection workbook now always written (in addition to Slot-5 native format).
  - Inspection code rewritten as `inspect_file()` function — fixes `path` undefined bug.
  - Composite primary-key detection added — v0.1 misidentified continuous numeric measures as primary keys.
  - `string_cols` now uses `pd.api.types.is_string_dtype` — pandas 2.x string-dtype columns were silently missed by `dtype == object`.
  - `binary_text_cols` separately captured (e.g. `东南侧/西北侧`) — was previously lost.
  - xlsx multi-sheet warning added — v0.1 silently read Sheet1.
  - YAML schema in this file now matches actual production output (was inconsistent in v0.1).
  - Prerequisites section added; scipy fallback documented.
  - Output directory convention pinned to `<parent>/intake/`.
  - Stata-target column-name guard added (32-char limit, reserved words).
- **v0.1** (2026-04-29) — first cut. Audit report at [`audit-flagship-cleaning.md`](audit-flagship-cleaning.md).
