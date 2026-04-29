# 贡献指南 · Contributing

欢迎为 Empirical Research Pipeline 贡献新模块或改进现有模块。

## 提交前请先读

1. [`README.md`](README.md) —— 整体架构与模块清单
2. [`docs/contract-spec.md`](docs/contract-spec.md) —— 模块间契约规范
3. [`docs/architecture.md`](docs/architecture.md) —— 设计原则与边界
4. 现有模块 [`modules/01-data-intake/`](modules/01-data-intake/) 作为参考实现

不读这三份文档直接提 PR 会被退回。

---

## 新模块贡献流程

### 1. 在 issue 里先讨论

提 PR 之前先开一个 issue 描述你想做的模块：

- 模块编号与名称（参考现有阶段划分，避免重复）
- 上游模块（读哪份合同）
- 下游模块（写哪份合同）
- 预计的 80% 机械操作 vs 20% 留给用户的研究决策
- 适用学科（默认轨 / Mode A / 两者）

维护者会就模块边界给反馈，避免你做完才发现越界。

### 2. 实现

新模块目录必须包含：

```
modules/NN-module-name/
├── SKILL.md                      Claude Code 主指令（必需）
├── README.md                     人读说明（必需）
├── references/                   深度文档（必需，至少一份）
│   └── 01-...md
└── audit-...md                   设计前的审计报告（强烈建议）
```

`SKILL.md` 的 frontmatter 必须包含：

```yaml
---
name: <ascii-snake-case-skill-name>
description: <长描述，含触发关键词，方便 Claude Code 自动激活>
license: CC BY-SA 4.0
---
```

### 3. 契约合规

模块产出的 yaml 文件必须遵循 [`docs/contract-spec.md`](docs/contract-spec.md) 中列出的字段约定。schema 偏差需要在 PR 描述中说明并征求维护者意见。

如果你的模块需要新增契约字段，先在 PR 中修改 `docs/contract-spec.md` 并解释理由。

### 4. 端到端测试

PR 必须证明在至少一份**真实公开数据集**上端到端跑通。建议数据源：

- Lalonde NSW (training data, classic econ benchmark)
- Card 1995 returns to schooling
- NHANES (公卫示例)
- 任何 [openICPSR](https://www.openicpsr.org/) 上的 replication package

提供：

- 测试数据下载链接（或仓库内 fixture）
- 完整运行日志
- 产出的合同 yaml 与所有 artifact 文件清单

### 5. 文档要求

`SKILL.md` 必须包含：

- Frontmatter（name, description, license）
- "When to use" / "When NOT to use" 段落
- 输入合同字段引用
- 输出 artifacts 清单
- 与现有 flagship pipelines 的边界声明
- "做什么 / 不做什么" 表格
- 不变量列表

`README.md` 必须以**具体使用场景**开头，不能以抽象设计论证开头。参考 `modules/01-data-intake/README.md` 的开篇。

### 6. PR 描述模板

```markdown
## 模块名称
modules/NN-module-name

## 阶段
[阶段 X 数据准备 / 阶段 Y 估计 / ...]

## 上游 → 下游
读 <upstream>.yaml → 写 <output>.yaml

## 这个模块做什么（80% 机械操作）
- ...

## 这个模块不做什么（留给用户 / 下游）
- ...

## 端到端测试数据
- 数据源: ...
- 数据下载链接: ...
- 完整日志: <gist 或 PR 评论>

## 契约变更
- [ ] 没有引入新字段
- [ ] 引入了新字段（已更新 docs/contract-spec.md）
```

---

## 改进现有模块

小改动（typo / 文档优化 / bug 修复）可以直接提 PR，不必先开 issue。

涉及契约变更或 SKILL.md 行为改动的，请先开 issue 讨论。

---

## 风格约定

- README.md 用中文为主，技术术语保留英文
- SKILL.md 用英文为主（Claude Code 主要在英文上下文运行）
- 不使用装饰性 emoji（status badge 除外）
- 引用具体文件路径时用反引号包裹
- 流程图用 ASCII（不依赖渲染插件）

---

## 行为准则

- 尊重审稿意见，不质疑维护者关于"边界"的判断（除非有明确技术理由）
- 不在 PR 中夹带与模块无关的改动
- 测试覆盖不到的代码请显式说明

---

## 报告 issue

如果你发现 bug 或想提建议，请打开 issue 并说明：

- 用的哪个模块、哪个版本
- 输入数据的形态（行列数、缺失情况、关键列名）
- 预期行为 vs 实际行为
- 复现步骤（最小化的一段代码）
