# 文献咨询 · Literature Consultation

> **作用域**：当 intake 模块跑完 80% 机械清洗、检测到 `unresolved_decisions` 非空时，可选择启用此功能，为每个未决问题提供"前人怎么处理"的方法学建议。
>
> **关键约束**：本功能**只产出 markdown 建议报告**，不修改任何数据字段。所有数据决策仍由用户做出后通过手动改 `cleaned_dataset.xlsx` 或重跑 intake 实现。

---

## 1. 为什么需要这个

`unresolved_decisions` 是 intake 的核心输出之一，但 v0.1 里这个字段只是文字描述："tenure has 8% missingness, NOT MCAR — use MI in flagship Step 1.5"。

研究者看到这条会问：
- MI 怎么做？哪个软件、哪个包？
- 别人在我这种数据上是怎么处理的？
- 论文里要怎么写脚注？引用谁？
- 经济学顶刊和国内 C 刊的惯例一样吗？

如果让用户自己 Google 这些问题，要花 1-2 小时；而 intake 已经知道**确切的问题描述**（MCAR 检验、变量名、缺失率），可以直接帮用户做精准检索。

文献咨询阶段就是把这一步**嵌进 intake 工作流**，但不替用户做决策——只产生**建议清单 + 引用模板**。

---

## 2. 核心设计：三层 fallback + 一轮研究方向沟通

```
intake 跑完机械清洗
  ↓
unresolved_decisions 非空?  否 → 跳过文献咨询
  ↓ 是
[对话] "要查文献给建议吗?"  否 → 跳过
  ↓ 是
[对话] 研究方向 4 问 (用户回答用于精准化查询)
  ↓
=== 三层 fallback 查询 ===
Layer 1: 扫描本机已装 skill, 优先复用
Layer 2: 调外部 MCP / WebSearch
Layer 3: Claude 内置知识
  ↓
合成 literature_recommendations.md
合同 yaml 增加 literature_consultation 审计字段
```

每一层只在**前一层不够用**时才触发，避免重复查询。

---

## 3. 研究方向 4 问

文献查询的精准度完全取决于查询字符串的具体性。不问研究方向，查出来全是泛泛文献；问了，可以精准到方法学层面。

### 4 题模板

```
为了让文献检索精准, 我需要先了解你的研究:

1. 你这个研究的核心命题是?（一句话）
   示例: "数字经济发展对城市绿色全要素生产率的影响"
        "二甲双胍是否降低 2 型糖尿病患者心梗风险"

2. 主识别策略是?
   [A] TWFE 双向固定效应
   [B] DID 双重差分（含 staggered）
   [C] IV 工具变量
   [D] RDD 断点回归
   [E] PSM 倾向得分匹配
   [F] target trial emulation (epi)
   [G] 其他 / 描述性

3. 你已读过的关键文献?（可选, 1-5 篇）
   skill 会用它们的引用网络扩展查询

4. 期刊定位?
   [A] 顶刊 (AER / QJE / JPE / Lancet / JAMA)
   [B] 主流期刊 / 国内 C 刊
   [C] 不确定
```

### 设计权衡

- **第 1 题不能跳过** —— 否则查询是"missing data imputation"这种泛泛搜索，10000+ 结果，用户筛不动
- **第 2、4 题用多选** —— 降低用户输入成本
- **第 3 题可选但强烈推荐** —— 关键文献是研究坐标的最强信号；如果用户列了 3 篇 paper，skill 能直接用它们的引用网络扩展，质量提升 10 倍

回答完写入合同 `research_context` 字段，下游模块可读这个字段重用研究方向（不用每个模块重新问）。

---

## 4. Layer 1：复用本机已装 skill

intake 在文献咨询阶段**首先扫描** `~/.claude/skills/` 看有没有以下 skill。如果有，直接 invoke：

| 已知可复用 skill | 用途 | 适合查的内容 |
|---|---|---|
| `arxiv-database` | arXiv 检索 | 经济学 / ML / 统计的方法学论文（DID 新方法、staggered DID、causal forest 等） |
| `biorxiv-database` | bioRxiv 检索 | Mode A 公卫 / 流病的预印本 |
| `pyzotero` | Zotero 集成 | 自动把找到的文献入用户的 Zotero 库 |
| `citation-management` / `academic-citation-manager` | 引用管理 | 生成可粘贴的 BibTeX |
| `perplexity-search` | AI 网络搜索 | 综合性查询（含中文文献、博客、教程）|
| `research-lookup` | 研究查询 | Parallel Chat API 综合搜索 |
| `parallel-web` | Parallel API 搜索 | 高质量综合检索 |
| `web-access` | Browser 自动化 | 抓取需要登录或动态渲染的页面（如知网）|
| `systematic-literature-review` | 系统综述 | 多源检索 + AI 评分 + 分主题 |
| `pubmed-database` (in `biopython`) | PubMed | Mode A 必备 |

### 调用顺序

```
对每个 unresolved_decision item:
  1. 构造一个查询字符串
       (issue 描述 + research_context.research_question + identification_strategy)
  2. 优先使用顺序:
     (a) systematic-literature-review  — 最综合
     (b) perplexity-search             — 学术 + 网络综合
     (c) arxiv-database / biorxiv      — 单源专业
     (d) research-lookup / parallel-web — 通用兜底
  3. 用 citation-management 把结果整理成 BibTeX
  4. 用 pyzotero 入库（仅当用户允许）
```

如果用户没装这些 skill，跳到 Layer 2。

### 检测逻辑

```python
import os
skills_dir = os.path.expanduser("~/.claude/skills/")
available_skills = set(os.listdir(skills_dir)) if os.path.exists(skills_dir) else set()

priority_chain = [
    "systematic-literature-review",
    "perplexity-search",
    "arxiv-database",
    "research-lookup",
    "parallel-web",
]
to_use = [s for s in priority_chain if s in available_skills]
```

把 `to_use` 写入合同的 `literature_consultation.layers_used[0].skills_invoked` 字段。

---

## 5. Layer 2：外部 MCP / Claude Code 内置工具

如果 Layer 1 无 skill 可用（比如用户只装了 empirical-research-pipeline，没装其他），fallback 到：

| 工具 | 来源 | 用法 |
|---|---|---|
| **OpenAlex MCP** | 跨学科最大开放学术图谱 | 查 240M+ 文献的元数据、引用网络、合作图 |
| **arXiv MCP** | arXiv 官方 MCP | 经济学 / 统计 / ML 预印本 |
| **WebSearch (内置)** | Claude Code 内置 | 通用网络搜索兜底 |
| **WebFetch (内置)** | Claude Code 内置 | 抓特定 URL 的元数据 |

调用规则：

- 优先级：OpenAlex > arXiv > WebSearch
- 每个查询限制最多 30 条结果（防止泛滥）
- 必须记录到合同 `literature_consultation.layers_used[1]`

---

## 6. Layer 3：Claude 内置训练知识

如果 Layer 1+2 都不可用（无网络环境、无任何辅助 skill），最后兜底：

直接让 Claude 用训练时积累的方法学知识给建议——但**必须**：

- 在 yaml 标 `confidence: medium` 或 `low`
- 在输出 markdown 顶部加显式 disclaimer："以下建议来自 LLM 训练知识, 没有实时文献检索, 请你自行核实文献存在性"
- **不**给具体引用文号（如 "国发 [2013] 45 号"）—— 防止幻觉
- 只给方法学描述 + 建议查的方向

---

## 7. 输出格式：`intake/literature_recommendations.md`

文献咨询的产物是一份 markdown 报告。固定结构：

```markdown
# 文献咨询报告

**生成时间**：YYYY-MM-DD HH:MM:SS UTC
**研究主题**：<用户在第 1 问的回答>
**识别策略**：<第 2 问>
**期刊定位**：<第 4 问>
**查询源**：Layer 1 (skills: ...) + Layer 2 (sources: ...) + Layer 3 (confidence: ...)
**总文献筛选**：<n> 篇 → **入选**：<m> 篇

---

## Issue 1: <issue 描述, 来自 unresolved_decisions[0]>

### 推荐 1（high relevance）
- **来源**：作者 (年), 期刊, 卷(期): 起-止页
- **做法**：……（一段简短描述, 50-100 字）
- **为什么适合你**：……（说明 relevance, 50 字以内）
- **下游模块如何用**：……（具体到哪个 module 的哪一步, 调哪个函数）
- **citation_template_for_paper**：可粘贴的中英文脚注

### 推荐 2（medium relevance）
...

### 推荐 3（low relevance, 但代表另一种思路）
...

---

## Issue 2: <issue 描述, 来自 unresolved_decisions[1]>
...

---

## 文献咨询审计

总查询数: 4
- Layer 1 query 1: "Chinese city panel data missing not at random imputation"
- Layer 1 query 2: "TWFE missing covariates 经济研究"
- Layer 2 query 1: ...

调用的 skill: arxiv-database (n=2), perplexity-search (n=1)
调用的 MCP / 内置: OpenAlex MCP (n=1)

筛选阈值: 标题 + 摘要相关度 > 0.7
人工标注: 无

---

**Disclaimer**：本报告基于联网检索 + LLM 综合, 是给你的**建议清单**, 不是研究决策。
- 引用前请核实文献是否真实存在（Layer 3 推断的部分尤其需要核实）
- 选哪种方法是你的研究判断, intake 不替你做
- 采纳建议后, 在 论文脚注 / acknowledgments 部分引用相应文献
```

---

## 8. 合同集成

文献咨询完成后，intake 写出的 `data_contract.yaml` 增加两个字段。

### `research_context`（用户回答的 4 问）

```yaml
research_context:
  research_question: "数字普惠金融发展对城市经济增长的影响"
  identification_strategy: TWFE
  key_references_known:
    - "郭峰 et al. (2020), 经济学(季刊)"
    - "Manyika et al. (2016), MGI Report"
  target_journal_tier: mainstream
```

下游模块可读此字段，**不用再重复问研究方向**。

### `literature_consultation`（审计日志）

```yaml
literature_consultation:
  performed: true
  performed_at: "2026-04-29T15:32:00Z"
  user_consented: true
  layers_used:
    - layer: 1
      strategy: "reuse local skills"
      skills_invoked:
        - {name: arxiv-database, n_queries: 2, n_results: 18}
        - {name: perplexity-search, n_queries: 1, n_results: 5}
  total_queries: 3
  total_papers_screened: 23
  output_file: "intake/literature_recommendations.md"
  papers_recommended: 9
```

---

## 9. 用户工作流

```
intake 完成 80% 清洗
  ↓
intake: "我发现 5 个待决问题. 要查文献给建议吗? [Y/N]"
  ↓ Y
intake: 研究方向 4 问 (用户回答)
  ↓
intake 内部:
  scan ~/.claude/skills/
  detect: arxiv-database, perplexity-search
  Layer 1 invoke
  生成 literature_recommendations.md
  ↓
intake: "已生成 intake/literature_recommendations.md (9 篇推荐). 请阅读后决定是否采纳."
  ↓
[用户读完报告, 决定]
  - 直接采纳推荐 1: 改 cleaned_dataset.xlsx 然后重跑 intake (这次跳过文献咨询)
  - 不采纳: 留 unresolved 给下游模块
  - 部分采纳: 改某些列, 留某些 unresolved
```

---

## 10. 不变量

文献咨询模块必须保证：

1. **永远不修改数据字段** —— 只产生 markdown 报告
2. **永远经用户同意才联网** —— 默认关闭
3. **永远完整审计** —— 所有查询、调用的 skill、返回数 / 入选数都写合同
4. **Layer 3 必须显式标 confidence** —— 防止幻觉被当事实
5. **不直接修改 unresolved_decisions** —— 只在合同里加 `consulted_sources` 子字段
6. **可复现性优先** —— 同一份原始数据 + 同一组 4 问回答 = 同一组 query string；具体返回结果会因网络资源更新而变, 但 query 本身可复现

---

## 11. 何时 **不** 启用文献咨询

下列情况建议跳过：

- **离线环境** —— 无网络 / 私网, 直接 N
- **熟练用户** —— 已经清楚知道 unresolved_decisions 该怎么处理, 不需要建议
- **数据是高度敏感的** —— 即使 query 也可能泄露研究主题, 用户不希望联网
- **快速测试 intake 行为** —— 第 N 次跑 intake 调试时, 跳过节省时间

intake 的 4 问之前会先问 [Y/N], 用户随时可以选 N 跳过整个咨询阶段。

---

## 12. 版本

- **v0.3** (2026-04-29) — 初版, 与 intake v0.3 同步发布。三层 fallback 策略 + 4 问研究方向 + 完整审计字段
- 未来 v0.4 计划: 把 4 问研究方向上推到 intake 主流程的 Slot 6（让所有 unresolved 决策都受益）
