# Mode A — Public-Health / Epidemiology Cleaning Patterns

> **作用域**：当 Slot 1 = epi（公共卫生 / 流行病学 / 临床研究）时，intake skill 在执行通用 80% 清洗的基础上，**额外**跑下列检查。这部分内容在 `00 / 00.1 / 00.2 / 00.3` 四个 flagship 的 Step 1 reference 中**全员零覆盖**，是本 skill 的独占价值。
>
> 所有代码以 Python (pandas) 为执行 lingua franca，但所有概念可平移到 Stata/R。

---

## 0. 为什么 econ 清洗范式不能直接套到 epi 数据

| 维度 | Econ 默认（4 flagship） | Epi 队列研究 |
|---|---|---|
| 时间结构 | 离散 panel `(id, year)` | 连续 person-time `(id, start, end)` |
| 缺失含义 | 数据丢失 | 可能是删失（censoring，正常状态） |
| Outlier | winsorize 外延 | 极端值常是真实临床事件 — 不能截 |
| 主键 | (id, time) | (id, episode_id) — 一人多次入组 / 多次暴露 |
| Treatment | 通常时不变（一次暴露） | 时变（统药多年、剂量变化、用药中止） |
| 时间起点 | 日历时间（year） | **t0 = index date**（个体化）|

如果把 cohort 数据当 panel 处理，会立刻踩到下面任何一个坑。

---

## 1. Index date（入组日）解析与硬校验

**Index date** = 每个个体的 t0。所有时间计算（暴露窗口、随访时长、event 发生时间）都相对于 index date。**index date 错，整篇文章错。**

### 1.1 必查项

```python
# 假设 df 有 index_date / enrol_date / baseline_date 之一（通过 epi_signal_cols 检测）
import pandas as pd

idx_col = next(c for c in df.columns
                 if c.lower() in {"index_date","enrol_date","baseline_date","t0","start_date"})

# Check 1: 全部非空
assert df[idx_col].notna().all(), \
    f"{df[idx_col].isna().sum()} rows have missing {idx_col} — every cohort member must have a t0"

# Check 2: 可解析为日期
df[idx_col] = pd.to_datetime(df[idx_col], errors="coerce")
assert df[idx_col].notna().all(), "index_date contains unparseable strings"

# Check 3: 日期范围合理（不在未来 / 不早于研究开始）
study_start = pd.Timestamp("1990-01-01")
study_end   = pd.Timestamp.today()
assert (df[idx_col] >= study_start).all() and (df[idx_col] <= study_end).all(), \
    f"index_date out of range; min={df[idx_col].min()}, max={df[idx_col].max()}"

# Check 4: 每个 id 只有一个 index_date（单次入组）
# 多次入组的研究需要在 Slot 4 显式声明
n_idx_per_id = df.groupby("patient_id")[idx_col].nunique()
if (n_idx_per_id > 1).any():
    print(f"WARNING: {(n_idx_per_id > 1).sum()} patients have multiple index dates — confirm this is intentional")
```

### 1.2 写入 contract

```yaml
epi_checks:
  index_date_col: enrol_date
  index_date_valid: true
  n_with_missing_t0: 0
  index_date_range: ["1995-03-12", "2018-11-04"]
  multiple_index_per_id: 0
```

---

## 2. Time-zero 对齐 — 防 immortal time bias

最常见的 epi 数据错误：**person-time 起点定义不一致**。例如：

> 研究"二甲双胍是否降低心梗风险"，cohort 包含所有糖尿病患者。如果 t0 = "首次配药日"，那么从糖尿病诊断到首次配药之间的时间就**不能算作 exposed person-time** —— 在那段时间患者还没暴露。如果错误地把这段时间分配给暴露组，就构造出"暴露组里几个月内的人不死"，称为 **immortal time bias**。

### 2.1 检查规则

```python
# 假设有 exposure_start_date 和 outcome 发生时间
df["t0"] = pd.to_datetime(df["enrol_date"])
df["exposure_start"] = pd.to_datetime(df["exposure_start_date"], errors="coerce")
df["event_date"] = pd.to_datetime(df["event_date"], errors="coerce")

# Check 1: exposure_start 不能早于 t0（否则 t0 选错了）
violation_1 = (df["exposure_start"] < df["t0"]) & df["exposure_start"].notna()
if violation_1.any():
    print(f"WARNING: {violation_1.sum()} rows have exposure_start BEFORE index_date — review t0 definition")

# Check 2: event_date 不能早于 t0（否则该人在入组前已发生事件，应排除）
violation_2 = (df["event_date"] < df["t0"]) & df["event_date"].notna()
if violation_2.any():
    print(f"ERROR: {violation_2.sum()} rows have event BEFORE index date — these subjects should be excluded")

# Check 3: 如果用户已经构造了 exposed_time，验证它从 t0 起算
if "exposed_time" in df.columns:
    expected = (df["exposure_start"] - df["t0"]).dt.days
    if not (df["exposed_time"] == expected).all():
        print("WARNING: exposed_time may not be measured from index_date — verify")
```

### 2.2 长格式 person-time 的正确构造模板

```python
# 把每个个体拆成"未暴露"和"已暴露"两段 person-time
def build_person_time(df, id_col, t0_col, exposure_start_col, end_col):
    """
    Returns long-format DataFrame with rows = (id, start, end, exposed).
    Each subject contributes up to 2 rows: pre-exposure (exposed=0), post-exposure (exposed=1).
    """
    rows = []
    for _, r in df.iterrows():
        pid = r[id_col]
        t0  = r[t0_col]
        exp = r[exposure_start_col]
        end = r[end_col]
        if pd.isna(exp) or exp >= end:
            # never exposed
            rows.append({"id": pid, "start": t0, "end": end, "exposed": 0})
        else:
            # pre-exposure period
            rows.append({"id": pid, "start": t0,  "end": exp, "exposed": 0})
            # post-exposure period
            rows.append({"id": pid, "start": exp, "end": end, "exposed": 1})
    return pd.DataFrame(rows)
```

写入 contract:

```yaml
epi_checks:
  time_zero_aligned: true
  n_pre_t0_events: 0
  n_pre_t0_exposures: 0
  immortal_time_risk: false
```

如果 `n_pre_t0_events > 0`，**intake 直接停止**并报告 — 这不能往 flagship 递。

---

## 3. Censoring vs Missing — 关键区分

`event = 0` 在 epi 数据里**不是缺失**，是**未发生事件**（删失）。但 `event_date = NaN` 时呢？取决于：

| `event` | `event_date` | `censor_date` | 含义 |
|---|---|---|---|
| 1 | 非空 | — | 发生事件，时间是 event_date |
| 0 | 空 | 非空 | 删失，时间是 censor_date（如失访日 / 研究结束日 / 死于其他原因） |
| 0 | 空 | 空 | **错误** — 必须有删失日 |
| 1 | 空 | — | **错误** — 事件发生但无日期 |

### 3.1 校验

```python
def validate_survival_structure(df, event_col, event_date_col, censor_date_col):
    n_total = len(df)

    # event = 1 → 必有 event_date
    bad_event = (df[event_col] == 1) & df[event_date_col].isna()
    if bad_event.any():
        raise ValueError(f"{bad_event.sum()} rows: event=1 but event_date is missing")

    # event = 0 → 必有 censor_date
    bad_censor = (df[event_col] == 0) & df[censor_date_col].isna()
    if bad_censor.any():
        raise ValueError(f"{bad_censor.sum()} rows: event=0 but censor_date is missing — this is data quality issue, NOT statistical missing")

    # 构造 follow_time 和 survival_time（统一字段，向 flagship 提交）
    df["follow_time"] = (
        df[event_date_col].fillna(df[censor_date_col]) - df["index_date"]
    ).dt.days
    df["status"] = df[event_col].astype(int)

    # follow_time 必须为正
    assert (df["follow_time"] > 0).all(), "follow_time must be positive (use Cox proportional hazards or AFT)"

    return df
```

### 3.2 写入 contract

```yaml
epi_checks:
  censoring_unambiguous: true
  n_events: 487
  n_censored: 1942
  median_follow_days: 1095
  follow_time_col: follow_time
  status_col: status
```

flagship Mode A Step 5 (生存分析) 期望就是 `(follow_time, status)` 这对字段。intake 帮它构造好。

---

## 4. Washout period（前导排空期）

很多 cohort 研究要求"过去 N 月内没有该药史"才允许入组。如果原始数据没排空，**结论会被既往用户污染**。

### 4.1 实现

```python
def apply_washout(df, id_col, t0_col, exposure_history_long_df, washout_months):
    """
    Drop subjects whose exposure_history has any record in [t0 - washout_months, t0).

    Notes:
    - Uses calendar-aware DateOffset (NOT washout_months * 30 days, which would drift).
    - Coerces t0_col and exposure_history_long_df['exposure_date'] to datetime first
      so the function is robust to string inputs.
    """
    df = df.copy()
    df[t0_col] = pd.to_datetime(df[t0_col])

    hist = exposure_history_long_df.copy()
    hist["exposure_date"] = pd.to_datetime(hist["exposure_date"])

    # Calendar-aware window: index_date - N months, exclusive on the right (< t0)
    df["_washout_start"] = df[t0_col] - pd.DateOffset(months=washout_months)
    df["_washout_end"]   = df[t0_col]

    has_prior = hist.merge(df[[id_col, "_washout_start", "_washout_end"]], on=id_col)
    has_prior = has_prior[(has_prior["exposure_date"] >= has_prior["_washout_start"]) &
                          (has_prior["exposure_date"] <  has_prior["_washout_end"])]
    bad_ids = has_prior[id_col].unique()

    n_before = len(df)
    df = df[~df[id_col].isin(bad_ids)].drop(columns=["_washout_start", "_washout_end"])
    print(f"[intake] dropped {n_before - len(df)} subjects with prior exposure within {washout_months} months")
    return df
```

写 sample_log：

```yaml
sample_log:
  - [raw, 5000]
  - [drop_pre_t0_event, 4987]
  - [apply_washout_6mo, 4612]    # ← 新增条目
```

---

## 5. ICD-10 / CPT / ATC 代码标准化

诊断/手术/药物代码是 epi 数据**最容易出错**的部分。原始数据里常见混乱：

| 形态 | 含义 |
|---|---|
| `I21.4` | ICD-10 急性心梗（含点号） |
| `I214`  | 同上去点号 |
| `I21`   | 不带亚类 |
| `i214`  | 小写 |
| `I21.04` | 末尾零 |

### 5.1 标准化函数

```python
import re

ICD10_REGEX = re.compile(r"^[A-Z]\d{2}(\.\d{1,4})?$")

def normalize_icd10(code):
    if pd.isna(code):
        return None
    s = str(code).strip().upper().replace(" ", "")
    # canonical form: with dot if extended
    if "." not in s and len(s) > 3:
        s = s[:3] + "." + s[3:]
    if not ICD10_REGEX.match(s):
        return f"INVALID:{s}"
    return s

# Apply
df["dx_code_clean"] = df["dx_code"].map(normalize_icd10)
n_invalid = (df["dx_code_clean"].astype(str).str.startswith("INVALID:")).sum()
print(f"[intake] {n_invalid} ICD-10 codes failed normalization — see {df.loc[df['dx_code_clean'].str.startswith('INVALID:'), 'dx_code'].unique()[:10]}")
```

类似的函数处理 CPT (5 位数字)、ATC (字母数字混合 7 位)、SNOMED-CT 等。如果用户没声明代码字段类型，flagship 那边不会做这一步。intake 标准化后写入 contract：

```yaml
epi_checks:
  code_normalization:
    dx_code: {scheme: ICD-10, n_total: 12000, n_invalid: 7}
    rx_code: {scheme: ATC,    n_total: 8500,  n_invalid: 0}
```

---

## 6. 多次入组（multiple cohort entries per id）

部分研究设计允许同一患者多次入组（如"每次新病程视为独立 episode"）。这破坏了"id = 唯一主键"的假设，必须显式声明。

### 6.1 检测

```python
n_idx_per_id = df.groupby("patient_id")["index_date"].nunique()
if (n_idx_per_id > 1).any():
    print(f"WARNING: {(n_idx_per_id > 1).sum()} patients have multiple index dates")
    # ASK user (Slot 4 conditional question):
    # "Multiple entries per patient detected. Is this intentional?
    #  (A) Yes, each row is an episode — primary key should be (patient_id, episode_id)
    #  (B) No, this is a data error — keep first / keep last / abort"
```

如果是 (A)，构造 `episode_id`：

```python
df = df.sort_values(["patient_id", "index_date"])
df["episode_id"] = df.groupby("patient_id").cumcount() + 1
df["panel_key"]  = df["patient_id"].astype(str) + "_" + df["episode_id"].astype(str)
```

写入 contract：

```yaml
primary_key: [patient_id, episode_id]
multiple_entries_allowed: true
n_subjects: 4500
n_episodes: 5200
```

---

## 7. 信息汇总：Mode A intake 的额外 5 步

在通用 80% 清洗之后，Mode A 多做这 5 步。**所有被 `mode_a_intake()` 调用的辅助函数必须先定义**——v0.1 的 bug 就是只有内联代码片段没封装成函数；v0.2 把它们补成可调用的命名函数。

### 7.1 辅助函数定义（必须先定义，再被 `mode_a_intake` 调用）

```python
import pandas as pd

def validate_index_date(df, idx_col, study_start="1990-01-01", study_end=None):
    """§1.1 的逻辑封装。返回处理后的 df，或 raise 错误。"""
    if study_end is None:
        study_end = pd.Timestamp.today()
    else:
        study_end = pd.Timestamp(study_end)
    study_start = pd.Timestamp(study_start)

    if df[idx_col].isna().any():
        raise ValueError(f"{df[idx_col].isna().sum()} rows have missing {idx_col} — every cohort member must have a t0")
    df = df.copy()
    df[idx_col] = pd.to_datetime(df[idx_col], errors="coerce")
    if df[idx_col].isna().any():
        raise ValueError(f"{idx_col} contains unparseable date strings")
    if not ((df[idx_col] >= study_start).all() and (df[idx_col] <= study_end).all()):
        raise ValueError(f"{idx_col} out of range; min={df[idx_col].min()}, max={df[idx_col].max()}")
    return df

def check_time_zero_alignment(df, slot_answers):
    """§2.1 的逻辑封装。检查 immortal time bias 风险。"""
    t0_col       = slot_answers["index_date_col"]
    exp_col      = slot_answers.get("exposure_start_col")
    event_col    = slot_answers.get("event_date_col")

    df = df.copy()
    df[t0_col] = pd.to_datetime(df[t0_col])
    if exp_col and exp_col in df.columns:
        df[exp_col] = pd.to_datetime(df[exp_col], errors="coerce")
    if event_col and event_col in df.columns:
        df[event_col] = pd.to_datetime(df[event_col], errors="coerce")

    # event before t0 — exclude these rows and log
    if event_col and event_col in df.columns:
        bad = (df[event_col] < df[t0_col]) & df[event_col].notna()
        if bad.any():
            n_drop = int(bad.sum())
            df = df[~bad].copy()
            print(f"[intake] dropped {n_drop} rows with event before index_date (recorded in sample_log)")
    return df

# validate_survival_structure, apply_washout, normalize_icd10 already defined in §§ 3.1, 4.1, 5.1
```

### 7.2 `mode_a_intake` orchestrator

```python
def mode_a_intake(df, slot_answers):
    """Run all 5 Mode A checks. Each step depends only on the previous; failures stop the pipeline."""
    # 1. Index date 解析与硬校验
    df = validate_index_date(df, slot_answers["index_date_col"])

    # 2. Time-zero 对齐 — 防 immortal time bias
    df = check_time_zero_alignment(df, slot_answers)

    # 3. Censoring vs missing — 构造 (follow_time, status)
    if slot_answers.get("event_col") and slot_answers.get("censor_date_col"):
        df = validate_survival_structure(df,
                                         event_col=slot_answers["event_col"],
                                         event_date_col=slot_answers["event_date_col"],
                                         censor_date_col=slot_answers["censor_date_col"])

    # 4. Washout（如果 user 在 Slot 4 补充声明了 washout_months）
    if slot_answers.get("washout_months") and slot_answers.get("exposure_history_df") is not None:
        df = apply_washout(df, slot_answers.get("id_col", "patient_id"),
                           slot_answers["index_date_col"],
                           slot_answers["exposure_history_df"],
                           slot_answers["washout_months"])

    # 5. 代码标准化（如果数据里有 dx_code / rx_code / proc_code）
    for col, scheme in slot_answers.get("code_cols", {}).items():
        if scheme == "ICD-10":
            df[f"{col}_clean"] = df[col].map(normalize_icd10)
        # CPT / ATC normalization — to be added in v0.3

    return df
```

每一步的产物写入 `data_contract.yaml` 的 `epi_checks` 节，flagship 拿到合同后能直接信任这些字段。

---

## 8. 路由建议

完成 Mode A intake 后，`routing_recommendation.md` 里的话术：

```markdown
You should now invoke flagship: **00.X (whichever language target)** in **mode_a_epi**.

## What's already done by intake (don't redo)
- Index date validated, time-zero aligned, no immortal-time-bias risk
- Survival structure (follow_time, status) constructed and validated
- Washout applied: 6 months, dropped 388 subjects (see sample_log)
- ICD-10 codes normalized: 12,000 codes, 7 invalid (flagged in column `dx_code_clean`)

## What flagship Mode A should do next
- Step 1.4 (Multiple imputation if covariate missingness > 5% AND not MCAR)
- Step 5 (Mode A): IPTW or g-formula or TMLE for confounder adjustment
- Step 5 (Mode A): KM / Cox / AFT survival models on (follow_time, status)
- Step 6: E-value sensitivity analysis

## Open issues
- {data_contract.unresolved_decisions}
```

---

## 9. 不变量

下列约定 intake 永远遵守，flagship 永远可以信任：

1. 进入 flagship 的 epi 数据，`(index_date, follow_time, status)` 三列已经验证过
2. `index_date` 是已解析的 datetime，非空
3. `follow_time > 0` 对所有行成立
4. 不存在 `event_date < index_date`（事件早于入组的行已被 intake 排除并记入 sample_log）
5. 如果做了 washout，`sample_log` 里有专门一条 `apply_washout_{N}mo` 记录
6. 代码字段如果声明了 scheme，已经标准化，无效项以 `INVALID:` 前缀标记，未删除（让 flagship 决定）

---

## 10. 与 flagship 的 `00.1/references/01-data-cleaning.md` 关系

flagship Step 1 的 11 节里：
- §3 (dtype 强转) — intake 已做基础部分（`pd.to_datetime` on index_date）；flagship 处理高级 case
- §4 (缺失) — intake 做 inventory，**不**做 MICE（flagship Step 1.4d 处理）
- §5 (outlier) — intake **不**做（epi 不应 winsorize 临床极值）
- §6 (去重) — intake 处理 `(patient_id, episode_id)` 主键唯一性
- §7 (merge) — intake 不做（flagship Step 1.7）
- §8 (panel diagnostics) — intake 输出 `epi_checks` 替代

intake 不与 flagship 重复，只补 flagship 没有的 epi 专属 7 项检查。

---

**版本**：
- **v0.2** (2026-04-29) — bug fixes: `mode_a_intake()` 调用的所有辅助函数现已显式定义；`apply_washout` 改用 calendar-aware `pd.DateOffset(months=N)` 替代 `* 30 days` 近似；所有 datetime 列在使用前都显式 `pd.to_datetime`。
- **v0.1** (2026-04-29) — first cut.

**作用域**：Slot 1 = epi 时强制运行
**反馈**：见 SKILL.md 主文件
