# Flagship Step 1 Audit

> **目的**：在写本 skill（00.4 Empirical Data Intake）之前，对 `00 / 00.1 / 00.2 / 00.3` 四个 flagship 的 Step 1 (Data cleaning) 内容做一次质量与覆盖审计，作为本 skill 设计的输入。
>
> **审计范围**：
> - `skills/00-Full-empirical-analysis-skill_StatsPAI/SKILL.md`（Section 0，line 220–300）
> - `skills/00.1-Full-empirical-analysis-skill_Python/references/01-data-cleaning.md`（351 行）
> - `skills/00.2-Full-empirical-analysis-skill_Stata/references/01-data-cleaning.md`（435 行）
> - `skills/00.3-Full-empirical-analysis-skill_R/references/01-data-cleaning.md`（450 行）

## 评级总表

| Flagship | 等级 | 范围 | 覆盖完整度 | 方法学正确度 | 学科适配 |
|---|---|---|---|---|---|
| **00 StatsPAI** | B+ | "data contract" 概念层（不执行 ETL，假设用户已经 pandas 做完） | 部分（仅 5-check + sample_log） | 高（MCAR hint via t-test 是亮点） | 仅 econ |
| **00.1 Python** | A− | 全 11 节执行手册 | 全 | 高 | 仅 econ；epi 零覆盖 |
| **00.2 Stata** | A− | 全 12 节执行手册 | 全 | 高（gold rule on row-count assertion） | 仅 econ；epi 零覆盖 |
| **00.3 R** | A− | 全 12 节执行手册 | 全 | 高（validate + assertr 是四个里最严的） | 仅 econ；epi 零覆盖；`fct_explicit_na` 已 deprecated |

整体结论：**四个 flagship 的 Step 1 在 econ 默认轨上质量过硬，可以信任**。但都存在两个共性缺口（见下文），这正是本 intake skill 的设计依据。

---

## 各 flagship 强弱项详查

### 00 StatsPAI — Section 0（"Sample construction & data contract"）

**强项**：
- `data_contract()` 函数返回 dict + JSON 持久化 → **直接成为本 skill 输出 `data_contract.yaml` 的概念原型**
- `sample_log` 列表 + JSON 落盘 → AER footnote 4 标准对应物
- MCAR hint：对 missing-on-y 的行 vs 观察到 y 的行做协变量 t-test，p<0.05 即提示非 MCAR — 简洁有效
- 5-check：(1) shape (2) dtypes (3) missing (4) duplicate keys (5) panel balance — 干净的 go/no-go 检查

**弱项**：
- **明确声明"假设 ETL 已在 pandas 完成"**（line 223）→ 本身不执行清洗，只校验
- 不处理：dtype 强转、重复行、merge、字符串清洗、outlier
- 把执行层全部转嫁给 00.1 Python — 没有 Stata/R 的对应版本

**对 intake 的启示**：直接采用 StatsPAI 的 contract + sample_log 概念，**跨语言泛化**为本 skill 的输出格式（YAML 而非 JSON 以便人读）。

---

### 00.1 Python — references/01-data-cleaning.md

**11 节内容**：
1. Inspection（`shape`, `info`, `head`, `describe`, `isna().mean()`, `missingno`）
2. Non-CSV 格式（`.dta` via `pyreadstat`, SAS/SPSS, Parquet, Excel, JSON, SQL）
3. Dtype 强转（`pd.to_numeric`, `Int64`, `Categorical`, `to_datetime`）
4. 缺失（MCAR/MAR/MNAR + 4 种处理 + MICE via `statsmodels.imputation.mice`）
5. Outlier（z-score, IQR, Mahalanobis）
6. 去重 + 面板键校验
7. Merge with `validate=` argument
8. 面板结构诊断（coverage, gap detection, entry/exit, balanced subset）
9. 时间/日期处理（含 event-study 相对时间、business calendar、tz）
10. 字符串清洗（含 `rapidfuzz` 模糊去重）
11. 可复用 `clean()` 函数模板

**强项**：
- 最完整。每一节都给可运行代码
- MICE 演示规范（10 iterations × 5 imputations）
- `merge_asof` for 金融场景（panel 数据接 CPI 等连续时间字段）
- 章节末有 `clean()` 函数可直接复用

**弱项**：
- 无调查权重（NHANES、CHARLS、HRS 等都需要）
- 无 epi 概念（index date / time-zero / censoring / person-time 全部缺失）
- 无数据驱动自适应（"here's how if you decide to" 风格，不会先看数据再决定）

**对 intake 的启示**：本 skill 不重做以上任何一节 — 全部交还。intake 只做"先看数据 → 决定调用 flagship 哪几节"。

---

### 00.2 Stata — references/01-data-cleaning.md

**12 节内容**：与 00.1 平行，加 Stata 专属：`destring/tostring/encode/decode/recode`、`misstable/mdesc/missings`、`duplicates`、`merge ... assert(match using)`、`xtset/tsset/xtdescribe`、`label var/value/values`。

**强项**：
- **Golden rule 写入**（line 272）："the row count before and after a lookup merge must match (or differ by a number you predicted)" — 加 `count` + `assert` 的成对模板
- `isid worker_id year` 作为 hard assert
- `xtdescribe` + gap 检测的 Stata 专属习语
- Labels 章节最完整（Stata 用户必备）
- `01_clean.do` 模板 9 段式可直接 do file 运行

**弱项**：
- `mahapick`（line 198）是冷门 SSC 包，多数用户没装；建议默认走 z-score / IQR
- 第 7 节没显式讲 `_merge == 1` 时该怎么解读（master 有 key 但 using 没有 — 是 master 数据脏还是 using 数据缺？）
- 同 00.1：无 epi、无调查权重

**对 intake 的启示**：本 skill 不重做。intake 只在 Slot 5 = Stata 时把 routing 指向 00.2，并把 contract YAML 与 Stata 习语对齐（如 `isid` 检查通过即报告 `key_uniqueness: 1.0`）。

---

### 00.3 R — references/01-data-cleaning.md

**12 节内容**：与 00.2 平行，加 R 专属：`haven` labels、`janitor::clean_names/get_dupes`、`naniar::vis_miss/gg_miss_upset`、`fct_explicit_na`、`mice` with PMM、dplyr 1.1+ `relationship` argument、`fuzzyjoin`、`panelr::panel_data`、`plm::pdata.frame`、`validate::validator/confront`、`assertr::verify/assert`。

**强项**：
- **验证层最强**：`validate` + `assertr` 双库，规则写成 `validator(...)` 对象，输出 confront summary，可视化 — 四个 flagship 里最严的验证
- dplyr 1.1+ `relationship` 参数 — 比 Python `validate=` 更优雅，默认警告 m:m
- `naniar::gg_miss_upset` 缺失上集图 — 找联合缺失模式的最佳工具
- `01_clean.R` 模板用 `here::here()` 处理路径，可移植性最好

**弱项**：
- **`fct_explicit_na` 已在 forcats 1.0+ 被弃用**（line 174）— 应改用 `fct_na_value_to_level()`。版本陈旧。
- `mice` 例子用 `method = "pmm"` 但未解释为什么（pmm 是 default，但用户应知道何时该用 norm / logreg / polyreg）
- `mahalanobis()` 例子在 line 222 — base R 的内置函数足够，没问题，但和 00.1 的 scipy 对比下显得克制
- 同其他：无 epi、无调查权重

**对 intake 的启示**：路由到 00.3 时，contract YAML 的 `key_uniqueness: 1.0` 应映射到 R 的 `assertr::assert(is_uniq, ...)`。可以提示 forcats 版本问题作为 unresolved decision。

---

## 跨 flagship 共性缺口（= intake skill 的独占价值）

下列项目在四个 flagship 的 Step 1 reference 中**全员零覆盖**或仅有零散提及，构成本 skill 的设计依据：

### 缺口 1：Mode A（公卫/流行病学）的清洗内容

四个 SKILL.md 的开篇 description 都说 "Mode A reuses the same Step 1 cleaning scaffolding"，但实际 references/01 全部是纯 AER econ 风格。**没有一行**关于：

- Index date / 入组日 / baseline date 的对齐与校验
- Time-zero 选择（calendar 入组 vs exposure 启动 vs eligibility met）
- Censoring（censored == "失访" or "尚未发生事件"）vs missing 的区别
- Person-time 的长格式构造（id, start, end）
- Washout period（前导排空期）的实现
- Immortal time bias 检测（exposure 启动前的 person-time 不能编码为 exposed）
- ICD-10 / CPT / ATC 等诊断/手术/药物代码的标准化（去点号、去前导零）
- 生存数据 (time, event) 二元结构的硬校验（event=1 必须有 time；event=0 时 time = censor time）

**这是 flagship 文档的实质性缺陷**（aspirational claim 与实际内容不符）。本 skill 必须独占这部分能力。落地在 [`references/01-mode-a-epi-patterns.md`](references/01-mode-a-epi-patterns.md)。

### 缺口 2：学科感知的 Q&A 决策层

四个 reference 全部是参考手册体例，描述 **how**（如何写 destring / mice / merge），不描述 **when / which**（什么时候该 destring，哪种缺失策略适合本数据）。它们假设用户已经做完研究设计、已经知道 unit of observation、已经知道 outcome 是哪一列。

→ 本 skill 提供 5-slot conditional Q&A 来弥补。

### 缺口 3：数据驱动的自适应决策

四个 reference 没有"先 inspect 数据再决定问什么"的逻辑。它们是静态文档。

→ 本 skill 在 Q&A 之前先跑一次完整 inspection，根据 inspection 结果决定 Slots 的 AUTO / CONFIRM / ASK 模式。

### 缺口 4：路由概念

四个 reference 各自假设用户已经选好语言生态系统。无人指导用户在 Python / Stata / R / StatsPAI 之间选。

→ 本 skill 的 Slot 5 + `routing_recommendation.md` 输出处理这件事。

### 缺口 5：sample_log 跨语言规范

仅 00 StatsPAI 有规范的 `sample_log` 结构（list of (label, n) tuples 落盘 JSON）。00.1 / 00.2 / 00.3 都只有零散 `print(f"dropped N rows")` 语句，无统一格式。

→ 本 skill 输出统一的 `sample_log` 节（YAML 格式），所有 flagship 可读。

---

## 设计含义（→ intake skill 边界）

| Intake 做什么 | 理由 |
|---|---|
| ✅ 5-slot conditional Q&A | 缺口 2 |
| ✅ 静态 inspection 驱动 Q&A 模式 | 缺口 3 |
| ✅ 跨语言 `data_contract.yaml`（继承 StatsPAI 概念） | 整合 + 缺口 5 |
| ✅ 统一 `sample_log` 结构 | 缺口 5 |
| ✅ 路由到正确 flagship + mode | 缺口 4 |
| ✅ Mode A epi 清洗模式 | 缺口 1（独占） |
| ✅ 自动执行机械清洗（rename / dtype 明确情形 / 重复检测 / 主键校验 / 缺失清单 / outlier flag） | 用户负担最低的 80% |
| ❌ MICE / MI 实现 | 已在 flagship；intake 只 flag |
| ❌ Winsorize / 截尾 | flagship Step 2；intake 只 flag |
| ❌ Heckman / IPW for MNAR | flagship Step 5 |
| ❌ 主分析数据外的辅助 merge | flagship Step 1.7 |
| ❌ Event-study 时间对齐 | flagship Step 2 |
| ❌ 调查权重处理 | v0 不做，标记为 unresolved_decision |
| ❌ 行业代码 / 地域代码标准化（NAICS, ISIC, FIPS） | v0 不做（数据库太散），可作 v0.2 添加 |

---

## 不变量

无论 flagship 上游怎么变（00 StatsPAI 是周一自动同步），下列假设保持：

1. flagship Step 1 reference 永远是详细执行手册 — intake 不与之竞争，只在前面做 triage
2. flagship Step 1 永远不会主动跑学科感知 Q&A — intake 占据这个生态位
3. flagship 永远默认用户提供 analysis-ready 数据 — intake 把"接近 analysis-ready"的产物递交过去
4. flagship 永远不实质性覆盖 epi cleaning — intake 永远独占这部分

如果未来上游 StatsPAI 自己加上了 epi cleaning，本 skill 的 Mode A 模块会从"独占价值"变成"提前预演" — 仍然有用，因为 intake 的决策层和路由层不会被替代。

---

**审计完成日**：2026-04-29
**下一步**：见 SKILL.md 主文件。
