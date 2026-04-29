# 架构 · Architecture

本文档解释 Empirical Research Pipeline 的设计原则、模块边界、以及为什么按这种方式拆分。

## 1. 为什么拆成 10 个模块

实证研究的工作流是**阶段化**的。从原始数据到出版论文，研究者会顺序经历下面这些阶段：

1. 拿到原始数据，检查并清洗
2. 构造分析变量（取对数、winsorize、滞后、交互）
3. 写 Table 1 描述统计 + 平衡检验
4. 跑诊断检验（VIF / 异方差 / 序列相关 / Hausman）
5. 跑基线回归（OLS / TWFE / IV / DID / RDD）
6. 跑稳健性套餐（替换变量 / 截尾 / 子样本 / 平行检验 / 安慰剂）
7. 跑机制 / 异质性分析（中介 / 调节 / 分组）
8. 输出论文级表格与图
9. 撰写论文文本（引言 / 数据 / 方法 / 结论）
10. 回复审稿人 / 修改稿管理

把这 10 个阶段糊成一个大 skill 会有几个问题：

- **每个阶段的最佳工具不一样** —— 清洗用 pandas / janitor 最方便；TWFE 估计用 `reghdfe` / `fixest` 最好；制表用 `esttab` / `modelsummary`；写作辅助用专门的 LLM prompt。一个大 skill 没法对每个阶段都做到最好。
- **每个阶段的容错边界不一样** —— 清洗错了改回来容易，估计阶段研究设计错了整篇文章作废。把它们放一起会让 skill 在错误成本最高的阶段也只敢做"通用"操作。
- **学者的工作节奏是分阶段的** —— 研究者一般不会一口气跑完整流程，而是清洗完先放着、过几天写 Table 1、过几周做稳健性。模块化更贴近真实工作流。
- **模块独立演化** —— 清洗模块可以频繁更新（v0.2 → v0.3 → v0.4）而不影响估计模块的稳定性。

---

## 2. 设计原则

每个模块严格遵守下面 5 条：

### 原则 1：独立可运行

每个模块只依赖**前一模块写出的合同文件**，不依赖任何模块内部状态。这意味着：

- 用户可以跳过某些模块（比如只用 intake，不用整条 pipeline）
- 用户可以在不同模块间手动操作（比如 intake 跑完之后手动改两列再继续）
- 模块测试可以用模拟合同 yaml 作为输入，不需要实跑上游

### 原则 2：机械操作 vs 设计判断严格分离

每个模块只做**纯机械的、可以自动化的、不涉及研究设计判断的**操作。需要研究者决策的事情（阈值、识别策略、估计方法、变量选择）通过两种方式之一处理：

- **显式问** —— 在用户启动模块时通过 Q&A 收集，记录在合同的 `slot_answers` 字段
- **不做并写入 unresolved_decisions** —— 把决策推给下游模块或留给用户后续处理

举例：
- intake 模块**做**：列名规范化、dtype 强转、主键校验、缺失率清单、异常值标记（仅 flag）
- intake 模块**不做**：多重插补（方法选择是研究决策）、winsorize（阈值是研究决策）、merge 辅助数据（数据来源是研究决策）

### 原则 3：输出永远包含合同

每个模块**必须**写出至少一份 `*.yaml` 文件，描述：

- 本模块读入了什么（input contract reference）
- 本模块产出了什么（output artifacts list）
- 哪些字段被验证过（contract invariants checked）
- 留给下游 / 用户的待决问题（unresolved_decisions）
- 推荐的下一个模块（routing_recommendation）

合同 schema 详见 [`contract-spec.md`](contract-spec.md)。

### 原则 4：不抓取分析数据，但允许信息性查询

这是 v0.1 → v0.2 中被精化过的原则。

**禁止**：模块自主从网上获取会进入数据集、影响估计结果、或写入数据合同数据字段的内容（数据值、回归输入、模型参数、缺失值的外部插补值）。原因：

- **可复现性** —— 同一份原始数据 + 同一组用户回答必须永远产生同一份输出。从网上拿数据会让今天跑和明年跑结果不一样
- **可引用性** —— 论文脚注里写的数据来源必须是稳定可引的（文件号、文献年份），不能是某个 API 在某个时间点返回的值
- **离线运行** —— 研究者经常在本地 / 私网环境工作，模块必须能离线跑核心流程

**允许**：联网获取**纯信息性资源**——只要这些内容不会回流到 yaml 合同的数据字段或影响估计：

- 文献元数据查询（OpenAlex / arXiv / PubMed / Google Scholar）
- API 文档、方法学论文检索
- BibTeX / 引用元数据
- 用户在 unresolved_decisions 上想看"前人怎么处理"的方法论咨询

**复用优先**：联网查询时**优先调用本机已安装的辅助 skill**（如 `arxiv-database`、`perplexity-search`、`citation-management`、`pyzotero`、`systematic-literature-review`），而不是自己实现网络访问。原因：

- skill ecosystem 的本意就是工具复用
- 已有 skill 通常比临时实现的更好（处理认证 / 限流 / 异常）
- 减少代码维护负担

如果本机没有合适的辅助 skill，再 fallback 到外部 MCP（OpenAlex / arXiv MCP）或 Claude Code 内置 WebSearch / WebFetch，最后才是 Claude 自带训练知识。

**审计要求**：任何联网查询必须：

- 经用户显式同意（不能默认开启）
- 在合同 yaml 的 `literature_consultation` 字段记录：时间戳、查询字符串、调用了哪些 skill / MCP、返回了多少条结果
- 不修改任何数据字段；只产生 markdown 报告作为给用户参考的"建议清单"

详细落地见 `modules/01-data-intake/references/02-literature-consultation.md`。

### 原则 5：学科双轨

每个模块都默认支持两条轨道：

- **默认轨** —— 适用于经济学 / 计量 / 金融 / 政治学 / 社会学等社科研究
- **Mode A 轨** —— 适用于公共卫生 / 流行病学 / 临床研究

两条轨道在大多数模块里共享 80% 的逻辑，剩余 20% 是学科专属内容（如 epi 的 index date、time-zero、删失结构）。

---

## 3. 模块边界 vs 现有 flagship pipeline

仓库 [`Awesome-Agent-Skills-for-Empirical-Research`](https://github.com/brycewang-stanford/Awesome-Agent-Skills-for-Empirical-Research) 中有 4 个全流程 flagship pipeline（StatsPAI / Python / Stata / R）。它们和本 pipeline 的关系是：

| 维度 | flagship pipeline | 本 pipeline |
|---|---|---|
| 切分方式 | 横向：1 个 skill = 1 个语言生态的全流程 | 纵向：1 个 skill = 1 个研究阶段（语言无关） |
| 用户选择粒度 | 选语言（一旦选定，所有阶段都在同一 skill 内） | 选模块（每个阶段独立选择工具） |
| 适合场景 | 想一站式跑完整篇论文 | 想在不同阶段用最合适的工具 |
| 互操作性 | 各自封闭 | 通过 yaml 合同互通 |

两套体系不冲突：用户可以用本 pipeline 的 intake 把数据清干净，然后交给 flagship StatsPAI 的 Step 2-8 跑完估计与制表。本 pipeline 的 intake 模块的 `routing_recommendation.md` 就是这么设计的。

---

## 4. 模块依赖图

```
                          [01-data-intake]
                                |
                                v
                  [02-variable-construction]
                                |
                                v
        +-----------+-----------+-----------+
        |                       |
        v                       v
[03-descriptive-table1]  [04-diagnostic-tests]
        |                       |
        +-----------+-----------+
                    |
                    v
          [05-baseline-modeling]
                    |
        +-----------+-----------+
        |                       |
        v                       v
[06-robustness-battery]  [07-mechanism-heterogeneity]
        |                       |
        +-----------+-----------+
                    |
                    v
            [08-tables-figures]
                    |
                    v
            [09-paper-writing]
                    |
                    v
          [10-rebuttal-revision]
```

虚线（菱形分叉）表示该步骤可以并行：诊断检验和 Table 1 可以同时做，稳健性和机制分析也可以同时做。

---

## 5. 不变量

整条 pipeline 必须保证下列性质：

1. **同一份原始数据 + 同一组用户回答 → 同一份输出**（可复现性）
2. **任何模块停在中间，已写出的 artifacts 都是有效的**（崩溃安全）
3. **下游模块只读上游的合同 yaml，不读上游的内部状态**（解耦）
4. **`sample_log` 跨模块累积**（每个模块的 sample_log 字段把上游的复制下来再追加自己的）
5. **`unresolved_decisions` 跨模块传递**（除非显式标记为 resolved）
6. **没有"魔法默认值"**——任何研究决策要么由用户回答，要么留 unresolved，绝不静默

---

## 6. 不在本 pipeline 范围内的事

明确**不**做：

- 数据获取 / 抓取（用户自己解决）
- 定量预测（forecasting / 机器学习预测） —— 本 pipeline 是为**因果推断和描述统计**设计的，不是为预测建模
- 定性研究（访谈编码、扎根理论） —— 完全不同的方法论
- 文献综述（用专门的文献综述 skill）
- 期刊投稿系统操作 —— 这是行政流程，不是研究方法

如果你的研究流程需要这些步骤，请用其他工具，本 pipeline 不会替代。
