# 数据流图 · Pipeline Flow

本文档以**抽象的端到端流程**说明 Empirical Research Pipeline 如何把一份原始数据变成一份可发表论文。流程为概念示意；具体每一步的细节见对应模块的 `SKILL.md` 和 `references/`。

---

## 1. 完整数据流

```
+--------------+
| 原始数据文件  |   .csv / .dta / .xlsx / .sav / .parquet / .sas7bdat
+--------------+
        |
        v
+============================================================+
| 阶段 I：数据准备                                            |
+============================================================+
+----------------------+
| 01-data-intake       |
+----------------------+
        |
        +-> cleaned_dataset.{dta,parquet,rds}
        +-> cleaned_dataset.xlsx
        +-> data_contract.yaml         <--- 关键合同
        +-> routing_recommendation.md
        |
        v
+----------------------+
| 02-variable-         |
| construction         |
+----------------------+
        |
        +-> dataset_with_variables.{dta,parquet,rds}
        +-> variables_log.yaml         <--- 变量构造日志
        +-> data_contract.yaml         <--- 更新后的合同
        |
        v
+============================================================+
| 阶段 II：描述与诊断                                          |
+============================================================+
        |
        +---------+----------+
        |                    |
        v                    v
+----------------+   +-------------------+
| 03-descriptive-|   | 04-diagnostic-    |
| table1         |   | tests             |
+----------------+   +-------------------+
        |                    |
        +-> table1.{rtf,    +-> diagnostics_
        |   xlsx,tex}       |   report.yaml
        +-> table1_         +-> diagnostic_
            results.yaml        results.yaml
        |                    |
        +---------+----------+
                  |
                  v
+============================================================+
| 阶段 III：主估计                                            |
+============================================================+
+----------------------+
| 05-baseline-modeling |
+----------------------+
        |
        +-> baseline_M1.ster ... baseline_M5.ster   (Stata estimates store)
        +-> baseline_results.yaml
        +-> table2_baseline.{rtf,tex}
        |
        v
+============================================================+
| 阶段 IV：稳健性与机制                                        |
+============================================================+
        |
        +---------+----------+
        |                    |
        v                    v
+--------------------+   +-------------------------+
| 06-robustness-     |   | 07-mechanism-           |
| battery            |   | heterogeneity           |
+--------------------+   +-------------------------+
        |                    |
        +-> robustness_     +-> mechanism_results.yaml
        |   results.yaml    +-> heterogeneity_results.yaml
        +-> tableA1_        +-> table3_mechanism.{rtf,tex}
            robustness.tex   +-> table4_heterogeneity.{rtf,tex}
        |                    |
        +---------+----------+
                  |
                  v
+============================================================+
| 阶段 V：输出与发表                                           |
+============================================================+
+--------------------+
| 08-tables-figures  |
+--------------------+
        |
        +-> tables/*.{rtf,tex,docx}    (paper-ready tables)
        +-> figures/*.png             (paper-ready figures)
        +-> output_manifest.yaml
        |
        v
+--------------------+
| 09-paper-writing   |
+--------------------+
        |
        +-> paper_draft.tex
        +-> paper_outline.md
        |
        v
+--------------------+
| 10-rebuttal-       |
| revision           |
+--------------------+
        |
        +-> rebuttal_draft.tex
        +-> revision_summary.md
        |
        v
+--------------+
| 最终论文      |
+--------------+
```

---

## 2. 合同传递机制

模块之间通过 `data_contract.yaml`（及各模块的特有 yaml）传递信息。每个模块的执行模式如下：

```
[input contract yaml]                  ← 上游模块写的
        |
        v
+-------------------------+
|  当前模块               |
|  1. 读上游合同          |
|  2. 验证 schema         |
|  3. 执行本阶段操作      |
|  4. 写出新的 artifacts  |
|  5. 写出更新后的合同    |
+-------------------------+
        |
        v
[output contract yaml]                 ← 下游模块要读的
[output artifacts: data, tables, ...]
```

下游模块**不读**上游模块的内部状态，**不依赖**上游模块的代码——只依赖 yaml 合同。这意味着用户也可以手工写一份合同，跳过任何上游模块。

---

## 3. sample_log 跨模块累积

`sample_log` 是合同中**唯一会跨模块累积**的字段。每个模块从上游合同读出 sample_log，把自己的 drop 步骤追加到末尾：

```
intake 输出：
  sample_log:
    - [raw, 12345]
    - [drop_missing_panel_key, 12300]

variable-construction 输出（接续）：
  sample_log:
    - [raw, 12345]
    - [drop_missing_panel_key, 12300]
    - [drop_winsorize_wage_below_p1, 12300]   # winsorize 是替换不是删除，n 不变
    - [drop_log_zero_wage, 12288]              # log(0) 触发删除

baseline-modeling 输出（接续）：
  sample_log:
    - [raw, 12345]
    - [drop_missing_panel_key, 12300]
    - [drop_log_zero_wage, 12288]
    - [drop_singletons_in_FE, 12095]           # reghdfe 自动剔除单例
```

完整 sample_log 直接对应论文 Table footnote 4 的"sample construction"叙述。

---

## 4. unresolved_decisions 跨模块传递

`unresolved_decisions` 是模块间最重要的"软"通信。规则：

- 上游模块发现的开放问题 → 写入 `unresolved_decisions`
- 下游模块**必须读**这些项，并决定：
  - 自己解决 → 写入下游合同时把该项标 `resolved_in: <module-name>`
  - 不解决 → 原样保留，继续传给再下游
- 用户也可以人工解决某项，并在合同里手动标 `resolved_manually_at: <date>`

举例：

```
intake 写入：
  unresolved_decisions:
    - "tenure has 8% missingness, NOT MCAR — use MICE downstream"

variable-construction 接手，跑了 MICE，写入：
  unresolved_decisions:
    - issue: "tenure has 8% missingness, NOT MCAR — use MICE downstream"
      resolved_in: "02-variable-construction"
      resolution: "Applied mice::mice() with m=5 imputations, pooled via Rubin's rules"
```

到了论文写作阶段（09），所有 resolved 项都可以汇总成方法学脚注。

---

## 5. 学科双轨对流程的影响

`discipline` 字段在 intake 模块设定，所有下游模块必须保留同一值（除非用户主动切换）。

### 经济学默认轨

```
intake → variables → table1 → diagnostics → baseline → robustness → mechanism → tables → writing
```

每个模块跑默认逻辑，例如：

- 03-table1：经典 AER 多 panel 平衡表
- 05-baseline：reghdfe / fixest TWFE 主流程
- 06-robustness：替换变量 / 截尾 / 子样本 / 平行检验

### 公共卫生 / 流行病学 Mode A 轨

```
intake (Mode A) → variables (Mode A) → table1 (Mode A) → diagnostics (Mode A)
   → baseline (IPTW/g-formula/TMLE) → robustness (E-value) → ... → writing (STROBE)
```

每个模块跑 Mode A 专属逻辑，例如：

- 01-intake：额外的 epi_checks（index date / time-zero / 删失结构）
- 03-table1：STROBE Table 1（含 Table-S exclusion criteria）
- 05-baseline：IPTW / g-formula / TMLE 三件套（doubly-robust）
- 06-robustness：E-value 敏感性分析
- 09-writing：STROBE / TRIPOD reporting

---

## 6. 用户视角的两种使用模式

### 模式 A：全自动串联

```
用户：把这份原始数据做成一篇论文。

pipeline 自动：
  intake → variables → table1 → diagnostics → baseline → robustness
  → mechanism → tables → writing → (final review)
```

每个模块跑完后写出合同，下一个模块自动接手。中途如果遇到 ASK 类问题，会停下来问用户。

### 模式 B：手动单步

```
用户：先只做 intake。
pipeline：intake 跑完，输出 4 件套，告诉用户接下来该跑什么。

用户：（一周后）现在跑 02-variables，要 winsorize wage 在 1/99。
pipeline：02 跑完，写出新合同。

用户：（再一周后）现在跑 baseline。
pipeline：05 跑完，写出主回归结果。
```

这种模式下用户可以**任意暂停、任意修改中间产物**（比如手动改 cleaned_dataset.xlsx 中的某些值），下一步 pipeline 会读最新的合同 + 数据继续。

---

## 7. 故障与回滚

每个模块写出 artifacts 都使用**写入临时文件 → 原子重命名**的模式，保证：

- 模块在中途崩溃，**已有的合同永远是有效的**（要么是上一次成功运行的，要么没有）
- 不会留下半成品 yaml 被下游误读
- 重跑直接覆盖之前的 artifacts，不需要手动清理

如果某次运行结果有问题，用户可以：

1. 手动删除当前模块的 artifacts 目录
2. 重新运行该模块（pipeline 会从上游合同重新开始）

或者直接版本控制（git）整个项目目录，所有 artifacts 都在 git 里。
