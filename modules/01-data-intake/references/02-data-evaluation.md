# 数据评价 · Data Evaluation

> **作用域**：当 intake 模块跑完 80% 机械清洗（以及 Mode A 检查，如果适用）后，**总是**自动执行一次数据评价，输出 `intake/data_evaluation.md`。
>
> **关键约束**：评价完全基于 intake 自己已经算出来的指标——**不联网、不调外部模型、不调外部 skill**。所有规则都是确定性的模式匹配，可复现性 100%。

---

## 1. 为什么要这个

清洗完之后，研究者最想知道的是一个直接的"诊断"：**这份数据现在好不好用，差在哪里**？

之前的 `unresolved_decisions` 字段是一个**列表**，列出了所有没解决的问题，但没有一个综合判断——研究者还要自己消化。数据评价模块把这件事做了：

- **正面信号**汇总（数据扎实的地方）
- **风险信号**汇总（需要在 flagship / 写作时处理的地方）
- **整体评级**（A / B+ / B / C+ / C，附评语）

让研究者在进入 flagship 主流程之前，**用 30 秒**就知道这份数据值不值得做下去、需要补什么、能冲什么级别的期刊。

---

## 2. 触发与流程

```
80% 清洗完成
   ↓
(if Slot 1 = epi) Mode A 7 项检查
   ↓
=== 数据评价（始终运行） ===
   1. 读 contract 内部 dict (内存里, 还没写文件)
   2. 跑 23 条规则 (10 条 Strengths + 13 条 Optimization)
   3. 计算综合评级
   4. 渲染成 markdown
   ↓
写出 intake/data_evaluation.md (第 5 个文件)
   ↓
合同 yaml 增加 data_evaluation 字段做审计
   ↓
继续 Phase 8 (路由建议)
```

数据评价运行 **零网络调用、零外部 skill 调用、零 LLM 调用**——纯 Python 规则引擎，根据已有指标做判断。

---

## 3. 规则库

每条规则是一个 `(condition, message_template)` 对。当 condition 在当前数据上为真，触发并渲染消息。

### 3.1 Strengths（10 条）

| 规则 | 条件 | 触发消息 |
|---|---|---|
| `balanced_panel` | `panel_structure.balanced == True` | 完美平衡面板：{n_units} 单位 × {n_periods} 期 |
| `high_coverage` | `panel_structure.coverage >= 0.95` | 面板覆盖率 {coverage*100:.1f}%，无明显 attrition |
| `unique_pkey` | `key_uniqueness == 1.0` | 主键 {primary_key} 100% 唯一 |
| `low_missing_overall` | 平均 missing rate < 0.02 | 整体缺失率 < 2%，数据完整性强 |
| `clean_focal_vars` | outcome 与 main_x 列零缺失 | 焦点变量（{outcome}, {main_x}）零缺失 |
| `mostly_clean_columns` | 零缺失列数 ≥ 0.7 × n_cols | {N}/{n_cols} 列零缺失 |
| `multi_year_panel` | `n_periods >= 5` | 时间维度充足（{n_periods} 期），支持事件研究 / 长期趋势 |
| `multiple_heterogeneity` | heterogeneity 维度 ≥ 2 | 异质性维度齐全（{N} 个），robust 章节素材丰富 |
| `strong_main_relationship` | `\|cor(outcome, main_x)\| > 0.30` | 主关系（{outcome}, {main_x}）相关系数 {r:.2f}，主回归预期显著 |
| `sufficient_sample` | `n_rows_clean >= 1000` | 样本量 {n_rows_clean}，满足 TWFE 大样本估计要求 |

### 3.2 Optimization（13 条）

每条会根据严重程度标 `severity: critical | high | medium | low`，影响最终评级。

| 规则 | 条件 | 严重度 | 触发消息 |
|---|---|---|---|
| `not_mcar_outcome` | mcar_hint_outcome contains "NOT MCAR" | **critical** | outcome `{outcome}` 缺失非随机（{evidence}），listwise 删除会引入选择偏倚，必须 MICE / IPW |
| `not_mcar_alt_outcome` | mcar_hint_alt_outcomes 任一为 "NOT MCAR" | high | `{col}` 缺失非随机（{evidence}），如做 robustness 必须 MICE |
| `high_missing_var` | 任一列 missing rate > 0.05 | high | `{col}` 缺失率 {rate*100:.1f}%（>5%），flagship Step 1.5 处理 |
| `single_unit_missing_pattern` | 一单位占缺失行 ≥ 80% | medium | 单一单位（{unit}）占缺失行 {share*100:.0f}%，疑似数据采集漏洞，可手动补 |
| `severe_outliers_focal` | focal var 任一 z>4 占比 > 0.05 | high | `{var}` 极端异常值（\|z\|>4）占 {rate*100:.1f}%，flagship Step 2 winsorize |
| `moderate_outliers_focal` | focal var 任一 IQR 异常占比 > 0.10 | medium | `{var}` IQR 异常占 {rate*100:.1f}%，分布右偏，cluster-robust SE 必要 |
| `correlation_concern` | 任一 (focal_x, control) `\|r\| > 0.7` | high | `{x}` 与 `{control}` 高度相关 (r={r:.2f})，VIF 检查必要 |
| `weak_focal_relationship` | `\|cor(outcome, main_x)\| < 0.10` | **critical** | 主关系 cor({outcome}, {main_x}) = {r:.3f} 弱，TWFE 系数可能不显著 |
| `counterintuitive_correlation` | 已知应相关的 control（edu/hum/...）`\|r\|` < 0.05 | medium | `{control}` 与 `{outcome}` 几乎无关 (r={r:.3f})，反直觉，建议查测度或非线性 |
| `pgdp_dominates_x` | `\|cor(outcome, pgdp)\| > \|cor(outcome, main_x)\|` | medium | `pgdp` 与 outcome 相关（r={r_pgdp:.2f}）比 main_x 还强（r={r_x:.2f}），加 pgdp 可能吃掉 X 的解释力，需 progressive controls 表 |
| `heterogeneity_imbalance` | 异质性分组某组占比 < 0.20 或 > 0.80 | low | 异质性维度 `{dim}` 不平衡（{group_a}: {share*100:.0f}%），样本量差距大 |
| `categorical_level_mismatch` | 列层级数 ≠ codebook 描述 | low | `{col}` 有 {k} 个层级（codebook 写 {k_doc}），需确认未文档化层级含义 |
| `right_skewed_outcome` | outcome `SD/mean > 1.5` | medium | outcome `{outcome}` 重尾分布（SD/Mean = {ratio:.2f}），TWFE SE 可能偏小，wild bootstrap robust 必要 |

### 3.3 综合评级

```python
def compute_grade(strengths, optimizations):
    n_strengths = len(strengths)
    n_optims = len(optimizations)
    n_critical = sum(1 for o in optimizations if o.severity == 'critical')
    n_high = sum(1 for o in optimizations if o.severity == 'high')

    if n_critical >= 3:
        return ("C", "数据存在多个核心问题，需要在进入 flagship 之前集中处理")
    if n_critical >= 1 and n_strengths < 3:
        return ("C+", "数据基础有限且存在核心问题，处理后才能可靠估计")
    if n_strengths >= 7 and n_optims <= 2 and n_critical == 0:
        return ("A", "数据质量优秀。基础扎实，仅有少量边缘问题，可直接进入 flagship 主流程")
    if n_strengths >= 6 and n_high <= 2 and n_critical == 0:
        return ("A-", "数据质量很好。基础扎实，少量非阻塞问题在主回归之前处理即可")
    if n_strengths >= 5 and n_high + n_critical <= 4:
        return ("B+", "数据质量良好。基础扎实，但有 N 个非阻塞问题在主回归之前需要解决")
    if n_strengths >= 3 and n_optims <= 6 and n_critical <= 2:
        return ("B", "数据基础合格。有 N 个 issue 需要在 flagship 处理。论文方法部分需详细说明每个 issue 的处理")
    return ("B-", "数据基础勉强可用，建议先做 sample size 检验和数据来源校准再继续")
```

---

## 4. 输出格式：`intake/data_evaluation.md`

```markdown
# 数据评价报告

**生成时间**: <ISO-8601 UTC>
**数据**: <source_file> (<sheet>, <n_rows> 行 × <n_cols> 列, <n_units> 单位 × <n_periods> 期)
**研究设计**: <research_design> | <discipline> | <unit_of_observation>

---

## 一、数据表现好的地方

<对每条触发的 strength 规则, 渲染一行带编号的项>

1. **完美平衡面板**: 197 城市 × 10 年 (2014-2023)，覆盖率 100%
2. **主键唯一**: (id, year) 100% 唯一
...

## 二、需要完善和优化的地方

<对每条触发的 optimization 规则, 按 severity 排序 (critical → high → medium → low) 渲染>

### 关键问题（必须处理）
1. **{rule_name}** ⚠️ critical
   - 现象: {evidence}
   - 影响: {impact}
   - 建议: {recommendation}

### 重要问题（强烈建议处理）
...

### 一般问题（论文写作时讨论）
...

## 三、综合评价

**评级**: <A / A- / B+ / B / B- / C+ / C>

<2-4 段评语>:
- 第一段: 总结数据基础（哪些做对了）
- 第二段: 总结主要风险（哪些必须处理）
- 第三段（可选）: 写作时需要讨论的点
- 最后一句: 推荐的期刊定位（基于数据质量给出"适合冲击哪个层次"的建议）
```

---

## 5. 合同集成

写出 `data_evaluation.md` 的同时，在 `data_contract.yaml` 增加审计字段：

```yaml
data_evaluation:
  generated_at: "2026-04-29T15:32:00Z"
  output_file: "intake/data_evaluation.md"
  grade: "B+"
  n_strengths_triggered: 8
  n_optimizations_triggered: 6
  n_critical: 1
  n_high: 2
  n_medium: 2
  n_low: 1
  rules_triggered:
    strengths:
      - balanced_panel
      - unique_pkey
      - clean_focal_vars
      - mostly_clean_columns
      - multi_year_panel
      - multiple_heterogeneity
      - strong_main_relationship
      - sufficient_sample
    optimizations:
      - {rule: not_mcar_alt_outcome, severity: high, target: entropy_idx}
      - {rule: pgdp_dominates_x, severity: medium}
      - {rule: counterintuitive_correlation, severity: medium, target: edu}
      - {rule: right_skewed_outcome, severity: medium, target: y}
      - {rule: single_unit_missing_pattern, severity: medium, target: 常德市}
      - {rule: categorical_level_mismatch, severity: low, target: city_cluster}
```

下游模块或论文写作模块可以直接读这个字段决定怎么处理（如 grade=A 直接进 flagship，B+ 显示风险清单后再进，C 必须先解决某些 issue）。

---

## 6. 不变量

数据评价模块必须保证：

1. **零外部依赖** —— 不联网、不调外部 skill、不调 LLM
2. **完全确定性** —— 同一份输入 contract 永远产生同一份评价（评级 + 触发的规则集）
3. **不修改任何数据字段** —— 只产生 markdown 报告 + 合同审计字段
4. **总是运行** —— 不是 opt-in，是 intake 标准流程的一部分（除非用户用 `--no-evaluation` 显式关闭）
5. **规则优先级** —— critical > high > medium > low；评级算法依据严重度而非数量
6. **可读性优先** —— 每条触发的规则在报告中必须有具体证据（数字 / 列名 / 比例），不能写成"有问题"这种泛泛的话

---

## 7. 与 Mode A 的关系

如果 Slot 1 = epi，数据评价**额外**会触发以下规则（来自 epi_checks）：

| 规则 | 条件 | 严重度 |
|---|---|---|
| `epi_index_date_valid` | epi_checks.index_date_valid == True | strength |
| `epi_time_zero_aligned` | epi_checks.time_zero_aligned == True | strength |
| `epi_immortal_time_risk` | epi_checks.immortal_time_risk == True | **critical** |
| `epi_invalid_codes` | code_normalization.* 任一 n_invalid > 0 | low–medium |

具体细则见 `01-mode-a-epi-patterns.md` 的 § 8（路由建议中已包含）。

---

## 8. 版本

- **v0.3** (2026-04-29) — 初版，与 intake v0.3 同步发布
- 未来 v0.4 计划: 把规则库做成可插件化（用户可以贡献自己学科的规则）
