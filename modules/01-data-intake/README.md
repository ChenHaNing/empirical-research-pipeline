# Empirical Data Intake Skill · 实证研究数据入场 Skill

> 一句话：把一份原始数据文件，自动整理成"可以直接拿去跑回归"的状态。

[![License: CC BY-SA 4.0](https://img.shields.io/badge/License-CC%20BY--SA%204.0-lightgrey.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-v0.2-blue.svg)](#9-版本与计划)
[![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-skill-orange.svg)](https://claude.com/claude-code)

仓库地址：<https://github.com/ChenHaNing/empirical-data-intake-skill>

---

## 1. 这个 skill 能帮我做什么

假设你今天刚拿到一份 Excel 数据，你心里有一堆问题：

- 这是面板数据还是截面数据？
- 列名是中文，跑 Stata 会不会报错？
- 几列有缺失值，是随机缺失还是有规律？
- 几个数字看起来异常，是数据错误还是真实极值？
- 接下来该用 Stata、Python、还是 R？

把这个文件交给本 skill，它会替你做下面几件事：

1. **自己先看一遍数据**：行数、列数、缺失情况、是不是面板、主键是哪几列
2. **问你 2 到 5 个选择题**：研究的学科是什么？outcome 是哪一列？想用什么软件？
3. **自动清洗**：列名规范化、类型强转、主键校验、缺失率清单、异常值标记
4. **生成一份说明文档**：清洗后的数据、一个机器可读的"数据合同"、一份给你下一步用的指引

整个过程**2 到 4 分钟**，你只需要回答几道选择题。

---

## 2. 什么时候应该用这个 skill

**适合用的场景**：

- 刚拿到原始数据，不知道从哪开始
- 不确定该用 Stata / Python / R / StatsPAI 中的哪一个
- 数据是公共卫生或流行病学的队列研究（队列研究有专门检查模块）
- 数据明显有问题但你没诊断清楚（缺失、重复、类型混乱）

**不适合用的场景**：

- 数据已经很干净了，直接想跑回归 → 直接打开 Stata / Python / R
- 只想做一个很具体的操作（如"帮我 winsorize 一下"）→ 直接问 Claude 或查文档
- 只想做描述性统计 → 不需要走清洗流程

---

## 3. 安装与使用

### 3.1 安装

```bash
cd ~/.claude/skills/
git clone https://github.com/ChenHaNing/empirical-data-intake-skill.git
```

重启 Claude Code 即可。

### 3.2 触发

在 Claude Code 的对话里，随便说下面任何一句话都会触发：

- "我有一份原始数据，从哪开始？"
- "这个 .xlsx 该怎么清洗？"
- "我不知道用哪个 pipeline 处理这份数据"
- "帮我看看这个面板数据"
- "raw data, where do I start?"
- "我有一份 cohort 数据要做"

skill 自动接管，先静默地读一遍数据，然后开始问你问题。

---

## 4. 它会问我什么问题

总共 5 道题。**但你不一定每道都被问到**——skill 能从数据里直接看出来的就不问，强烈猜得出的只让你确认一下，真的猜不到的才让你选。

| 题号 | 问什么 | 大概什么时候真的会问 |
|---|---|---|
| 1 | 你研究的是经济学还是公共卫生 / 流行病学？ | **永远问**（数据本身判断不出来） |
| 2 | 这是面板 / 截面 / 时序 / 队列 / 重复截面 / 描述性？ | 看不出强结构时问；多数情况只让你确认 |
| 3 | 每行代表什么单位（个人 / 公司 / 城市 / 患者...）？ | 列名启发失败时问；多数情况只让你确认 |
| 4 | outcome 是哪一列？treatment 或 exposure 是哪一列？控制变量呢？ | **永远问**，但 skill 会先按列名猜出候选给你选 |
| 5 | 想用 Stata / Python / R / StatsPAI 中的哪个？ | `.dta` 文件自动走 Stata；其他文件让你选 |

**熟练用户**通常被问 2 到 3 题，**新手用户**最多被问 5 到 6 题。

第 4 题是认知负担最重的——你必须对自己的研究有清晰认识。其他题基本是"是 / 否"或"A / B / C / D"。

---

## 5. 它会输出什么

跑完会在你数据所在的项目目录下生成一个 `intake/` 子文件夹，里面有 **4 个文件**：

| 文件 | 这是什么 | 谁来看它 |
|---|---|---|
| `cleaned_dataset.dta`（或 `.parquet` / `.rds`） | 清洗后的数据，格式跟你选的软件匹配 | 你的 Stata / Python / R 脚本 |
| `cleaned_dataset.xlsx` | **同样的数据 + 详细说明分 7 张表**：主数据、异常值标记、列名映射、缺失清单、异常值汇总、未决问题、合同概览 | **你自己用 Excel 目视核对**——这是最好用的一份 |
| `data_contract.yaml` | 一份机器可读的"数据合同"：行数、列数、主键、面板结构、缺失模式、异常值数量、清洗日志、还有哪些没解决的问题 | Claude 或下游 skill 读取（你也可以打开看） |
| `routing_recommendation.md` | 你下一步该做什么的明确指引——含可以直接复制粘贴的 Stata / Python / R 代码 | **你自己** |

举个具体的：跑完之后，你打开 `routing_recommendation.md`，里面写"你现在应该打开 Stata，跑下面这段代码"，把代码粘到 Stata 里就能直接开始回归。

---

## 6. 它做什么 / 不做什么

### 它**自动做**的（你不需要决定）

- **列名规范化**：去中文、转小写、加下划线、确保 Stata 能识别
- **类型强转**：看起来是数字的字符串变数字、日期字符串变日期
- **空白和编码清理**：去首尾空格、修复乱码
- **重复检测**：报告完全重复行和主键重复
- **主键唯一性硬校验**：如果主键不唯一，立刻停止报错
- **面板结构推断**：算 N（单位数）、T（年数）、覆盖率、有没有断档
- **缺失率清单**：每列缺多少
- **MCAR 提示**：outcome 列的缺失看起来是不是随机的（如果不是，提示后续要用多重插补）
- **异常值标记**：用 z-score 和 IQR 两种方法，**只标记不删除**

### 它**不做**的（留给你 / 留给下一个 skill）

- **多重插补**（MICE / `mi` / `mice`）—— 留给下游 pipeline 的 Step 1.5
- **Winsorize / 截尾** —— 留给下游 pipeline 的 Step 2
- **Heckman 选择模型 / IPW** —— 留给下游 pipeline 的 Step 5
- **跟其他数据集合并（merge）** —— 留给下游 pipeline 的 Step 1.7
- **Event-study 时间对齐** —— 留给下游 pipeline 的 Step 2
- **应用调查权重** —— 你需要在下游主动声明
- **跑回归** —— 这是下游 pipeline 的事

**为什么不做？** 因为这些决策跟"研究设计"绑在一起，**只有你才知道怎么做对**。skill 只做能机械执行的部分，不替你做研究判断。

---

## 7. 公共卫生 / 流行病学的额外检查

如果你在第 1 题选了"公卫 / 流病"，skill 会**额外**跑下面 7 项检查。这些内容是其他 4 个清洗 skill **完全没覆盖**的：

| 检查 | 它在防什么 |
|---|---|
| Index date 解析与硬校验 | t0（每个个体的入组日）必须存在且可解析；t0 错，全文错 |
| Time-zero 对齐检测 | 防止 immortal time bias（暴露前的时间被错误归到暴露组） |
| 删失（censoring）vs 缺失（missing）区分 | 把"未发生事件"和"数据丢失"分开，构造统一的 (follow_time, status) |
| Person-time 长格式校验 | (id, start, end) 区间不能重叠或断裂 |
| Washout 期 | 排空既往用户，防止结论被既往用户污染 |
| ICD-10 / CPT / ATC 代码标准化 | 解决去点号、大小写、前导零等编码混乱 |
| 多次入组检测 | 同一患者如果入组多次，必须显式声明并构造复合主键 |

详细规则与代码模板见 [`references/01-mode-a-epi-patterns.md`](references/01-mode-a-epi-patterns.md)。

---

## 8. 完整流程图

```
+------------+
| 用户触发   | 用户在对话里说一句话，或给一个文件路径
+------------+
      |
      v
+------------+
| 静默检查   | skill 自己读文件，算 n_rows / n_cols / 缺失 / 主键候选 / 学科信号
+------------+
      |
      v
+------------+
| 摘要展示   | skill 给你一页可扫的总结表
+------------+
      |
      v
+----------------+
| 5 道题问答      | 第 1 题永远问；其他根据数据情况自动决定问 / 确认 / 跳过
+----------------+
      |
      v
+------------------+
| 自动清洗 9 步    | 改列名 / 转类型 / 清空白 / 校主键 / 算面板 / 算缺失 / MCAR 提示 / 标异常 / 初始化日志
+------------------+
      |
      v
+--------------------+
| 公卫额外 5 步       | (只在第 1 题选公卫时触发) index date / time-zero / 删失 / washout / 代码标准化
+--------------------+
      |
      v
+----------------+
| 写 4 个文件     | cleaned_dataset.{dta/parquet/rds} + cleaned_dataset.xlsx + data_contract.yaml + routing_recommendation.md
+----------------+
      |
      v
+--------------------+
| 给你下一步指引      | "现在打开 Stata，把下面这段代码粘进去"
+--------------------+
```

跟手工做同样质量的清洗 + 文档对比：手工大概 30 到 60 分钟，本 skill **2 到 4 分钟**。

---

## 9. 版本与计划

### v0.2（当前版本，2026-04-29）

经一次真实数据测试后修正过的稳定版。修复了 v0.1 的 5 个会让 skill 在真实数据上立即出错的硬 bug，并新增以下能力：

- **永远写出 `cleaned_dataset.xlsx`** ——之前只写 `.dta`，但研究者习惯先在 Excel 里目视核对。这是最重要的改进
- 复合主键检测——v0.1 会把"碰巧每行都不一样"的连续数值误判为主键
- pandas 2.x 字符串类型兼容——v0.1 在新版 pandas 下会漏检字符串列
- xlsx 多 sheet 警告——v0.1 会静默只读第一张
- Stata 列名硬约束（≤ 32 字符 / 非保留字 / 纯 ASCII）

### v0.1（2026-04-29）

第一版。5 道题问答框架、自动清洗 9 步、公卫专项 7 检查、3 件套输出（v0.2 升级到 4 件套）。

### v0.3 计划

- 把 SKILL.md 里的细节拆出来成独立的 references 文档
- 调查权重的 intake 阶段标记（NHANES / CHARLS / HRS）
- 行业 / 地域代码的格式校验提示（NAICS / FIPS / GB/T 4754）

---

## 10. 它在更大的工具体系里的位置

本仓库是一个更大的实证研究流程工具体系的**第一个模块**，专管"原始数据到 analysis-ready"这一步。后续模块还会有：

```
empirical-data-intake-skill          ← 你在这里（本仓库）
       ↓
empirical-baseline-regression-skill  ← 未来：基线回归
       ↓
empirical-robustness-skill           ← 未来：稳健性
       ↓
empirical-heterogeneity-skill        ← 未来：异质性
       ↓
empirical-tables-figures-skill       ← 未来：制表绘图
```

每个模块独立一个 GitHub 仓库，可以单独安装单独用。后面会再做一个总入口仓库统一索引。

---

## 11. 安装依赖

**必需**（Python 环境）：

- `pandas >= 2.0`
- `numpy`
- `pyyaml`
- `openpyxl`

**条件可选**：

- `pyreadstat` —— 只在你的源文件是 `.sav`（SPSS）或 `.sas7bdat`（SAS）时需要
- `scipy` —— 用于 MCAR 检测的 t 检验；没有也行，自动降级到 numpy 实现
- `pyarrow` —— 只在你想要 `.parquet` 输出时需要

如果缺了必需的，skill 会停下来告诉你装哪个。如果缺了条件可选的，skill 会自己处理或跳过。

---

## 12. 贡献

欢迎提 issue 和 pull request。**贡献前请先读 `audit-flagship-cleaning.md`**——这是设计本 skill 之前对其他 4 个清洗 skill 的审计报告，理解清楚边界后再改，避免好心办坏事。

提 PR 时请说明：

- 该改动属于哪一类：决策层 / 自动执行 / 输出格式 / 公卫专项
- 如果改了输出 schema，附上 yaml 的 before / after 对比
- 如果新增依赖，说明是必需还是可选

---

## 13. License

[CC BY-SA 4.0](LICENSE)。允许商业使用、修改、再分发，但需要署名，且衍生作品必须用同样的协议发布。

---

## 14. 引用 (Citation)

如果你在论文中使用此 skill 进行数据准备，请在脚注或致谢部分说明：

> Data preparation was assisted by the Empirical Data Intake Skill (v0.2, 2026), a Claude Code skill providing structured pre-analysis triage for empirical research. The skill produced a `data_contract.yaml` documenting the verified panel structure, missingness pattern, and outlier flags of the analysis dataset, together with a sample log recording all sample-construction steps. All cleaning decisions and downstream estimation were performed by the human author.

BibTeX：

```bibtex
@misc{empirical_data_intake_skill_2026,
  title  = {Empirical Data Intake Skill: Pre-Analysis Triage for Empirical Research},
  author = {{Chen, Haning}},
  year   = {2026},
  note   = {v0.2, Claude Code skill},
  url    = {https://github.com/ChenHaNing/empirical-data-intake-skill}
}
```

---

## 15. 致谢

- 数据合同的 YAML 概念跨语言泛化自 [`brycewang-stanford/StatsPAI`](https://github.com/brycewang-stanford/StatsPAI) 的 `data_contract()` 实现
- 数据清洗 8 步范式参考自 [`Awesome-Agent-Skills-for-Empirical-Research`](https://github.com/brycewang-stanford/Awesome-Agent-Skills-for-Empirical-Research) 中 4 个全流程 skill 的 `references/01-data-cleaning.md`

---

## 文件结构

```
empirical-data-intake-skill/
├── SKILL.md                            主指令文件（Claude Code 读取）
├── README.md                           本文件（人读）
├── audit-flagship-cleaning.md          设计前对 4 个清洗 skill 的审计报告
├── LICENSE                             CC BY-SA 4.0
├── .gitignore
└── references/
    └── 01-mode-a-epi-patterns.md       公共卫生 / 流行病学专章
```
