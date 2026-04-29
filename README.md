# Empirical Research Pipeline · 实证研究全流程 Skill 体系

> 一句话：从原始数据到论文发表的模块化 Claude Code skill 体系，每个模块处理实证研究的一个具体阶段。

[![License: CC BY-SA 4.0](https://img.shields.io/badge/License-CC%20BY--SA%204.0-lightgrey.svg)](LICENSE)
[![Modules](https://img.shields.io/badge/modules-1%2F10-blue.svg)](#3-模块清单)
[![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-skill-orange.svg)](https://claude.com/claude-code)
[![Status](https://img.shields.io/badge/status-active-brightgreen.svg)](#9-版本与计划)

仓库地址：<https://github.com/ChenHaNing/empirical-research-pipeline>

---

## 目录

- [1. 这是什么](#1-这是什么)
- [2. 设计原则](#2-设计原则)
- [3. 模块清单](#3-模块清单)
- [4. 安装与使用](#4-安装与使用)
- [5. 端到端流程图](#5-端到端流程图)
- [6. 模块间的契约](#6-模块间的契约)
- [7. 快速示例](#7-快速示例)
- [8. 贡献新模块](#8-贡献新模块)
- [9. 版本与计划](#9-版本与计划)
- [10. License](#10-license)
- [11. 引用](#11-引用-citation)
- [12. 致谢](#12-致谢)

---

## 1. 这是什么

实证研究的工作流是**阶段化**的：从拿到原始数据，到出版论文，中间要经过清洗、变量构造、描述统计、诊断检验、基线回归、稳健性、异质性、机制分析、制表绘图、写作、修改回复审稿人——每个阶段需要的工具、惯例、容错边界都不一样。

本仓库把这条流程**拆成 10 个模块**，每个模块都是一个独立的 Claude Code skill，处理一个特定阶段。模块之间通过一份机器可读的"数据合同" `data_contract.yaml` 衔接——上一个模块产出合同，下一个模块读合同接手。

每个模块都遵循相同的设计原则（见下文），可以独立安装独立使用，也可以串成完整 pipeline。

---

## 2. 设计原则

每个模块严格遵守下面 5 条：

1. **独立可运行** —— 不依赖其他模块的内部状态；只依赖前一模块写出的合同文件
2. **机械操作 vs 设计判断严格分离** —— 凡是涉及研究设计决策（阈值选择、识别策略、估计方法）都不替用户做，而是显式问用户或写入 `unresolved_decisions` 字段
3. **输出永远包含合同** —— 每个模块写出的 `data_contract.yaml` 是下游模块的唯一接口
4. **不抓取分析数据，但允许信息性查询** —— 模块禁止从网上拿任何会进入数据集或影响估计的内容（保证可复现性）；但允许联网做信息性查询（文献元数据、API 文档、方法学建议），且优先复用本机已装的辅助 skill
5. **学科双轨** —— 默认轨适用于经济学 / 计量 / 金融 / 政治学等社科研究；Mode A 轨适用于公共卫生 / 流行病学 / 临床研究

---

## 3. 模块清单

按研究阶段分组。状态标签：

- **[Released]** —— 已发布、有版本号、可生产使用
- **[In Development]** —— 设计完成，正在实现
- **[Planned]** —— 在路线图上，尚未开始

### 阶段 I：数据准备

| 模块 | 状态 | 说明 |
|---|---|---|
| [01-data-intake](modules/01-data-intake/) | **[Released v0.3]** | 原始数据 → analysis-ready 数据集 + 数据合同 + 路由建议 + 可选文献咨询 |
| [02-variable-construction](modules/02-variable-construction/) | [Planned] | 变量构造与变换：取对数 / winsorize / 一阶差分 / 哑变量 / 交互项 |

### 阶段 II：描述与诊断

| 模块 | 状态 | 说明 |
|---|---|---|
| [03-descriptive-table1](modules/03-descriptive-table1/) | [Planned] | Table 1（描述统计 + 平衡检验），AER 多 Panel 格式输出 |
| [04-diagnostic-tests](modules/04-diagnostic-tests/) | [Planned] | 经典诊断：异方差 / 多重共线性 / 序列相关 / 平稳性 / Hausman |

### 阶段 III：主估计

| 模块 | 状态 | 说明 |
|---|---|---|
| [05-baseline-modeling](modules/05-baseline-modeling/) | [Planned] | 基线回归：OLS / TWFE / IV / DID / RDD / 匹配 / 倾向得分 |

### 阶段 IV：稳健性与机制

| 模块 | 状态 | 说明 |
|---|---|---|
| [06-robustness-battery](modules/06-robustness-battery/) | [Planned] | 稳健性套餐：替换变量 / 截尾 / 子样本 / 平行检验 / 安慰剂 |
| [07-mechanism-heterogeneity](modules/07-mechanism-heterogeneity/) | [Planned] | 机制与异质性：交互项 / 中介 / 调节 / 分组回归 |

### 阶段 V：输出与发表

| 模块 | 状态 | 说明 |
|---|---|---|
| [08-tables-figures](modules/08-tables-figures/) | [Planned] | 论文级制表绘图：esttab / coefplot / event-study figure |
| [09-paper-writing](modules/09-paper-writing/) | [Planned] | 论文写作辅助：引言 / 数据 / 方法 / 结论的结构化生成 |
| [10-rebuttal-revision](modules/10-rebuttal-revision/) | [Planned] | 审稿回复 / 修改稿管理 |

---

## 4. 安装与使用

### 4.1 安装整条 pipeline（推荐）

```bash
git clone https://github.com/ChenHaNing/empirical-research-pipeline.git
cd empirical-research-pipeline
bash install.sh
```

`install.sh` 会把 `modules/` 下每个模块软链接到 `~/.claude/skills/` 目录。重启 Claude Code 即可识别。

### 4.2 只安装某个模块

```bash
git clone https://github.com/ChenHaNing/empirical-research-pipeline.git ~/.claude/skills/_pipeline-source
ln -s ~/.claude/skills/_pipeline-source/modules/01-data-intake ~/.claude/skills/empirical-data-intake
```

### 4.3 触发

在 Claude Code 的对话里直接说话，对应模块就会自动激活。例如：

| 用户说什么 | 触发哪个模块 |
|---|---|
| "我有一份原始数据，从哪开始？" | 01-data-intake |
| "帮我做 Table 1" | 03-descriptive-table1（计划中）|
| "跑一个 TWFE 基线" | 05-baseline-modeling（计划中）|
| "做一组稳健性检验" | 06-robustness-battery（计划中）|
| "输出 AER 风格的回归表" | 08-tables-figures（计划中）|

---

## 5. 端到端流程图

```
原始数据文件
    |
    v
+------------------------+
| 01-data-intake         | 5-slot Q&A → 80% 自动清洗 → 合同
+------------------------+
    |
    v  data_contract.yaml + cleaned_dataset.{dta,parquet,rds,xlsx}
    |
+------------------------+
| 02-variable-construction| 取对数 / winsorize / 滞后 / 交互
+------------------------+
    |
    v  variables_log.yaml
    |
+------------------------+
| 03-descriptive-table1  | Table 1：均值 / 标准差 / 平衡检验
+------------------------+
    |
    v  table1.{rtf,xlsx,tex}
    |
+------------------------+
| 04-diagnostic-tests    | VIF / Breusch-Pagan / Wooldridge / Hausman
+------------------------+
    |
    v  diagnostics_report.yaml
    |
+------------------------+
| 05-baseline-modeling   | OLS / TWFE / IV / DID / RDD
+------------------------+
    |
    v  baseline_results.yaml + 主回归 estimates store
    |
+------------------------+
| 06-robustness-battery  | 替换变量 / 截尾 / 子样本 / 平行检验
+------------------------+
    |
    v  robustness_results.yaml
    |
+------------------------+
| 07-mechanism-heterogeneity | 中介 / 调节 / 异质性
+------------------------+
    |
    v  mechanism_results.yaml
    |
+------------------------+
| 08-tables-figures      | esttab / coefplot / event-study figure
+------------------------+
    |
    v  tables/*.{rtf,tex} + figures/*.png
    |
+------------------------+
| 09-paper-writing       | 引言 / 数据 / 方法 / 结论生成
+------------------------+
    |
    v  paper_draft.tex
    |
+------------------------+
| 10-rebuttal-revision   | 审稿回复 / 修改追踪
+------------------------+
    |
    v
最终论文
```

每个箭头上方标注的文件就是模块间的契约。下游模块只读契约，不读上游模块的内部状态。

---

## 6. 模块间的契约

所有模块共用一份契约规范：[`docs/contract-spec.md`](docs/contract-spec.md)。

核心字段（每个模块都有一份自己的 yaml）：

```yaml
module_version: "0.2"
generated_at: "2026-04-29T..."
input_contract: <path-to-upstream-yaml>     # 上游模块写的合同（首模块为 null）
output_artifacts:                            # 本模块产出的文件清单
  - cleaned_dataset.dta
  - cleaned_dataset.xlsx
  - data_contract.yaml
  - routing_recommendation.md
unresolved_decisions:                        # 留给下游 + 用户的开放问题
  - "..."
sample_log:                                  # 行级筛除日志
  - [raw, 12345]
  - [drop_missing_panel_key, 12300]
routing_recommendation:                      # 下一个该跑哪个模块
  next_module: "02-variable-construction"
  reason: "..."
```

详细的字段语义、各模块特有字段、schema invariants 见 `docs/contract-spec.md`。

---

## 7. 快速示例

### 场景 A：从原始 Excel 到分析就绪数据集（intake 模块独用）

```
用户：我有一份 .xlsx 数据要做面板回归，从哪开始？

skill 自动接管：
  1. 静默读文件，识别格式与结构
  2. 给出一页摘要
  3. 问 5 道选择题（学科 / 设计 / 单位 / 焦点变量 / 软件）
  4. 自动跑 80% 机械清洗
  5. 写出 4 件套到 intake/ 目录
  6. 告诉用户接下来该用什么 pipeline

总耗时：2-4 分钟
```

详见 [`modules/01-data-intake/README.md`](modules/01-data-intake/README.md)。

### 场景 B：完整论文生产（10 个模块串联，未来支持）

```
用户：把这份原始数据做成一篇 AER 风格的论文。

pipeline 自动串联：
  01 intake → 02 variables → 03 table1 → 04 diagnostics →
  05 baseline → 06 robustness → 07 mechanism →
  08 tables/figures → 09 writing → 10 (final review)

输出：完整 LaTeX 论文 + 全套表格图 + 复现代码 + 审计日志
```

阶段 II–V 模块发布后此场景自动支持。

---

## 8. 贡献新模块

详见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

新模块必须满足：

- 遵循 [`docs/contract-spec.md`](docs/contract-spec.md) 定义的契约
- 包含完整的 `SKILL.md`（Claude 指令）+ `README.md`（人读说明）+ `references/`（深度文档）
- 通过端到端测试（在真实数据上跑通并产出有效合同）
- 有清晰的"做什么 / 不做什么"边界声明

---

## 9. 版本与计划

### v0.1 (2026-04-29) — 当前版本

仅含 `01-data-intake` 模块（v0.3）。pipeline 框架（契约规范、安装脚本、文档结构）就位，等待陆续加入 02-10 模块。

`01-data-intake` v0.3 在 v0.2 基础上新增**可选的文献咨询阶段**——遇到 `unresolved_decisions` 时可让 skill 帮你查文献给方法学建议（详见 [`modules/01-data-intake/references/02-literature-consultation.md`](modules/01-data-intake/references/02-literature-consultation.md)）。架构 Principle 4 同步精化：禁止抓取分析数据，但允许信息性查询。

### Roadmap

| 季度 | 计划完成的模块 |
|---|---|
| 2026 Q2 | 02-variable-construction |
| 2026 Q3 | 03-descriptive-table1, 04-diagnostic-tests |
| 2026 Q4 | 05-baseline-modeling |
| 2027 Q1 | 06-robustness-battery, 07-mechanism-heterogeneity |
| 2027 Q2 | 08-tables-figures |
| 2027 Q3 | 09-paper-writing, 10-rebuttal-revision |

---

## 10. License

[CC BY-SA 4.0](LICENSE)。允许商业使用、修改、再分发，但需署名，且衍生作品必须用同样的协议发布。

---

## 11. 引用 (Citation)

学术使用时请在脚注或致谢部分说明：

> The empirical workflow was supported by Empirical Research Pipeline (v0.1, 2026), a modular Claude Code skill suite covering raw-data intake, variable construction, estimation, robustness, and publication-ready output. All study-design decisions and substantive estimation choices were made by the human author.

BibTeX：

```bibtex
@misc{empirical_research_pipeline_2026,
  title  = {Empirical Research Pipeline: A Modular Claude Code Skill Suite for Empirical Research},
  author = {{Chen, Haning}},
  year   = {2026},
  note   = {v0.1, Claude Code skill suite},
  url    = {https://github.com/ChenHaNing/empirical-research-pipeline}
}
```

---

## 12. 致谢

- 数据合同的 yaml 概念跨语言泛化自 [`brycewang-stanford/StatsPAI`](https://github.com/brycewang-stanford/StatsPAI) 的 `data_contract()` 实现
- 8 步实证流程范式参考自 [`Awesome-Agent-Skills-for-Empirical-Research`](https://github.com/brycewang-stanford/Awesome-Agent-Skills-for-Empirical-Research) 中的全流程 skill
- 仓库结构参考自 [`K-Dense-AI/scientific-agent-skills`](https://github.com/K-Dense-AI/scientific-agent-skills)
