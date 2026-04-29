# 数据合同规范 · Contract Specification

本文档定义 Empirical Research Pipeline 各模块共享的 yaml 合同字段。任何模块的输出 yaml 都必须遵循此规范。

版本：v0.1（与 pipeline 主版本同步）

---

## 1. 总览

每个模块产出一份 `*.yaml` 合同文件，下游模块读这份合同接手。合同分四大块：

1. **元信息** —— 模块版本、生成时间、源文件等
2. **数据描述** —— 行列数、主键、面板结构、focal 变量等
3. **运行记录** —— sample_log、unresolved_decisions、模块特有字段
4. **路由建议** —— routing_recommendation 指向下一个模块

---

## 2. 必需字段（所有模块）

```yaml
# ---- 元信息 ----
contract_version: "0.1"                # 合同 schema 版本
module_name: "01-data-intake"          # 产生此合同的模块名
module_version: "0.2"                  # 模块版本
generated_at: "2026-04-29T02:30:50Z"   # ISO-8601 UTC
input_contract: null                   # 上游合同路径；首模块为 null
upstream_module: null                  # 上游模块名；首模块为 null

# ---- 学科与研究设计（贯穿所有模块）----
discipline: econ                       # econ | epi
research_design: panel                 # cross_section | panel | time_series | cohort_index_date | repeated_cs | descriptive | exploratory
unit_of_observation: "city-year"
software_target: stata                 # python | python_statspai | stata | r

# ---- 运行记录 ----
sample_log:                            # 跨模块累积；每个模块的删行 / 筛选都追加一行
  - [raw, 12345]
  - [drop_missing_panel_key, 12300]

unresolved_decisions:                  # 留给下游 / 用户的开放问题
  - "..."

# ---- 路由 ----
routing_recommendation:
  next_module: "02-variable-construction"
  reason: "..."
  next_step_in_module: "..."           # 在下游模块里该跑哪一步

# ---- 研究上下文（用户在文献咨询前回答的 4 问；也可被下游模块复用）----
research_context:                      # 可空 — 只在用户启用文献咨询时填写
  research_question: "..."             # 一句话研究命题
  identification_strategy: TWFE        # TWFE | DID | IV | RDD | PSM | target_trial_emulation | descriptive | other
  key_references_known:                # 用户列的 1-5 篇关键文献，可空
    - "Author (Year), Journal"
  target_journal_tier: mainstream      # top | mainstream | unspecified

# ---- 文献咨询审计（仅在用户启用时存在）----
literature_consultation:
  performed: true                      # false 时整个字段可省略其他子字段
  performed_at: "2026-04-29T15:32:00Z"
  user_consented: true                 # 必须为 true 才能执行联网查询
  layers_used:                         # 按使用顺序记录三层 fallback
    - layer: 1
      strategy: "reuse local skills"
      skills_invoked:
        - {name: arxiv-database, n_queries: 2, n_results: 18}
        - {name: perplexity-search, n_queries: 1, n_results: 5}
    - layer: 2                         # 仅在 Layer 1 不足时存在
      strategy: "external MCP / WebSearch fallback"
      sources:
        - {name: openalex-mcp, n_queries: 1, n_results: 12}
    - layer: 3                         # 仅在 Layer 1+2 都不足时存在
      strategy: "Claude internal knowledge"
      confidence: medium               # 必须显式标记
  total_queries: 4
  total_papers_screened: 35
  output_file: "intake/literature_recommendations.md"
  papers_recommended: 9                # 最终入选展示给用户的数量
```

---

## 3. 模块特有字段

每个模块在必需字段之外，还会写入自己阶段的产物。

### 3.1 `01-data-intake` 输出

```yaml
source_file: "raw/panel.dta"
source_sheet: "Sheet1"                 # 仅 .xlsx 时存在
n_rows_raw: 12345
n_rows_clean: 12000
n_cols_raw: 26
n_cols_clean: 56                       # raw + outlier flag cols
n_outlier_flag_cols_added: 30

primary_key: [id, year]
key_uniqueness: 1.0                    # 必须等于 1.0，否则模块停止

panel_structure:
  balanced: true
  n_units: 197
  n_periods: 10
  year_range: [2014, 2023]
  coverage: 1.0
  units_with_gaps: 0

focal_vars:
  outcome: y
  main_x: x
  alt_outcome: y1
  controls: [edu, ind, fin, ...]
  heterogeneity: [city_cluster, resource_city, central_city]
  treatment: null                      # null 表示无 0/1 treatment
  treatment_note: "..."

design:
  type: two_way_fixed_effects_continuous
  specification: "y = beta*x + Gamma*Controls + city_FE + year_FE + epsilon"
  cluster_level: "id (city)"

missing_pattern:                       # 仅列出非零缺失的列
  city_cluster: 0.005076
  entropy_idx: 0.060914

mcar_hint_outcome: "no missingness on `y`"
mcar_hint_alt_outcomes:
  entropy_idx: "NOT MCAR — ..."

outlier_flags:
  y:    {n_z4: 31, n_iqr: 279}
  x:    {n_z4: 17, n_iqr: 105}

# Mode A only — 当 discipline == "epi" 时存在
epi_checks:
  index_date_col: enrol_date
  index_date_valid: true
  ...

renames_applied:                       # 原列名 → 新列名
  Y: y
  所属地域: region
```

### 3.2 `02-variable-construction` 输出（计划中）

```yaml
# 在 intake 合同基础上追加：
variables_constructed:
  log_wage:
    formula: "log(wage)"
    source_var: wage
    n_rows_dropped: 0                  # log(0) / log(<0) 触发
  wage_w99:
    formula: "winsorize(wage, 0.01, 0.99)"
    source_var: wage
    cuts: [0.01, 0.99]
    n_replaced_low: 17
    n_replaced_high: 31
  treat_post:
    formula: "treat * (year >= policy_year)"
    source_vars: [treat, year]
    policy_year: 2018

variables_log:                         # 与 sample_log 平行的"变量构造日志"
  - {step: "winsorize wage at 1/99", n_replaced: 48}
  - {step: "construct log_wage", n_dropped: 0}

variables_unresolved:
  - "Should we use log(wage+1) instead of log(wage) given 12 zeros?"
```

### 3.3 `03-descriptive-table1` 输出（计划中）

```yaml
table1:
  panels:
    A: {label: "Outcomes", vars: [y, log_wage]}
    B: {label: "Treatment", vars: [treat, training_hours]}
    C: {label: "Controls", vars: [age, edu, tenure]}
  by_group: training                   # 按哪个变量分组
  test: ttest                          # 用哪种平衡检验
  output_files:
    - tables/table1_summary.docx
    - tables/table1_summary.xlsx
    - tables/table1_summary.tex

balance_check:
  imbalanced_vars:                     # 标准化差异 |Δ| / sd > 0.25 的变量
    - {var: edu, std_diff: 0.32, p_value: 0.001}
  recommendation: "Imbalance on edu — consider matching or weighting in baseline"
```

### 3.4 `05-baseline-modeling` 输出（计划中）

```yaml
baseline_results:
  models:
    M1: {spec: "y ~ x", se_type: cluster_id, n: 1970, r2: 0.123}
    M2: {spec: "y ~ x + controls", ...}
    M3: {spec: "y ~ x + controls + city_FE", ...}
    M4: {spec: "y ~ x + controls + year_FE", ...}
    M5: {spec: "y ~ x + controls + city_FE + year_FE", ...}

  preferred_model: M5
  estimates_store_paths:               # Stata estimates store / R model objects
    - estimates/M1.ster
    - estimates/M5.ster

baseline_unresolved:
  - "Standard error: cluster_id is conventional, but two-way clustering may be more conservative"
```

---

## 4. Schema invariants（所有模块必须保证）

任何模块的输出合同**违反下列任一条**都视为 bug，必须修复：

1. `contract_version` 字段必须存在并匹配 pipeline 当前主版本
2. `module_name` 字段必须等于实际产生此合同的模块目录名
3. 首模块（无 upstream）的 `input_contract` 必须为 `null`；非首模块必须为有效路径字符串
4. `sample_log` 第一行必须是 `[raw, <整数>]`（除非首模块在合同里显式声明从下游接管）
5. `discipline` 一旦在 intake 模块设定，**所有下游模块必须保留同一值**——除非用户在某个模块显式声明切换轨道
6. `key_uniqueness` 必须等于 1.0（任何模块发现主键不唯一应立即停止，不写出合同）
7. `unresolved_decisions` 中已被某模块解决的项必须显式标记 `resolved_in: <module-name>`
8. 当 `software_target == "stata"` 时，所有列名必须 ASCII / ≤32 字符 / 非保留字
9. 当 `discipline == "epi"` 时，`epi_checks` 字段必须存在
10. 路径字段（`input_contract`、`output_artifacts`）必须使用相对路径，不能写绝对路径

---

## 5. unresolved_decisions 字段规范

`unresolved_decisions` 是模块间最重要的"软"通信渠道。每条目可以是简单字符串（v0.1）或结构化对象（v0.2+ 推荐）：

```yaml
unresolved_decisions:
  # v0.1 简单形式
  - "tenure has 8% missingness and NOT MCAR — use MI in flagship Step 1.5"

  # v0.2+ 结构化形式（向后兼容）
  - issue: "tenure has 8% missingness and NOT MCAR"
    raised_in: "01-data-intake"
    severity: medium                   # low | medium | high | critical
    candidates:
      - "Use MICE in 02-variable-construction"
      - "Use IPW for sample selection in 05-baseline-modeling"
    recommended_action: "Use MICE in 02-variable-construction"
    resolved_in: null                  # 若已被下游模块解决则填模块名
```

下游模块应当在自己的合同里**复制并标注**所有上游 unresolved_decisions 的处理状态：解决了的标 `resolved_in`，未解决的原样保留。

---

## 6. routing_recommendation 字段规范

```yaml
routing_recommendation:
  next_module: "02-variable-construction"   # 必需，模块目录名
  mode: default                              # default | mode_a_epi | ...
  reason: "..."                              # 为什么推荐这个下一步
  next_step_in_module: "Step 2.3 (winsorize) and Step 2.5 (interaction terms)"
  alternatives:                              # 可选：列出其他可行的路径
    - module: "05-baseline-modeling"
      condition: "if you want to skip variable construction (data already in good shape)"
```

下游模块开始执行时应该**先读** `routing_recommendation.next_module` 验证自己是被正确路由到的；如果不匹配应警告用户。

---

## 7. 版本演进策略

合同 schema 遵循语义版本（semver）：

- **patch** (v0.1.x) —— 字段语义微调、文档修正，向后兼容
- **minor** (v0.x.0) —— 新增字段，向后兼容（旧 yaml 可读，新字段为 null）
- **major** (v1.0.0+) —— 破坏性变更，需要 migration script

新增字段时必须更新本文档并在变更日志里记录。废弃字段保留至少两个 minor 版本再移除。

---

## 8. 字段索引（按字母）

为了方便查阅，所有顶层字段按字母列出：

| 字段名 | 类型 | 模块 | 含义 |
|---|---|---|---|
| `baseline_results` | dict | 05 | 主回归模型估计 |
| `contract_version` | string | 全部 | 合同 schema 版本 |
| `design` | dict | 01+ | 研究设计（type / specification / cluster_level） |
| `discipline` | enum | 01+ | econ / epi |
| `epi_checks` | dict | 01+（仅 epi） | Mode A 专属检查结果 |
| `focal_vars` | dict | 01+ | outcome / treatment / controls / heterogeneity |
| `generated_at` | datetime | 全部 | 生成时间 |
| `input_contract` | string | 全部 | 上游合同文件路径 |
| `key_uniqueness` | float | 01+ | 主键唯一性比例（必须 1.0） |
| `mcar_hint_*` | string | 01+ | MCAR 判断提示 |
| `missing_pattern` | dict | 01+ | 列名 → 缺失率 |
| `module_name` | string | 全部 | 产生此合同的模块名 |
| `module_version` | string | 全部 | 模块版本 |
| `n_cols_raw` / `n_cols_clean` | int | 01+ | 行列数 |
| `n_rows_raw` / `n_rows_clean` | int | 01+ | 行列数 |
| `outlier_flags` | dict | 01+ | 每个变量的 z>4 / IQR 异常计数 |
| `panel_structure` | dict | 01+ | 面板结构（balanced / n_units / n_periods / coverage） |
| `primary_key` | list | 01+ | 主键列名列表 |
| `renames_applied` | dict | 01+ | 原列名 → 新列名 |
| `research_design` | enum | 01+ | 研究设计类型 |
| `routing_recommendation` | dict | 全部 | 下一个该跑哪个模块 |
| `sample_log` | list | 全部 | 跨模块累积的删行日志 |
| `software_target` | enum | 01+ | python / python_statspai / stata / r |
| `source_file` | string | 01 | 原始数据文件路径 |
| `source_sheet` | string | 01 | xlsx 的 sheet 名 |
| `table1` | dict | 03 | Table 1 描述统计 |
| `unit_of_observation` | string | 01+ | 观测单位（city-year / individual / firm-year / ...） |
| `unresolved_decisions` | list | 全部 | 待决问题清单 |
| `upstream_module` | string | 全部 | 上游模块名 |
| `variables_constructed` | dict | 02 | 02 模块构造的所有变量及其公式 |
| `research_context` | dict | 全部（可空） | 用户回答的 4 问，文献咨询查询用 |
| `literature_consultation` | dict | 全部（可空） | 文献咨询审计字段；含 layers_used / 调用的 skill / 查询数 / 输出文件 |
