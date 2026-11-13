# Agent Notes

这里只放一种设计文档。**Agent Note** 记录一项影响本仓库的决定或提议——代码与文档装不下的那部分：为什么这么定、放弃了什么。本文件规定 Agent Note 放在哪、什么时候写、以及[文件格式](#文件格式)。

## 布局与命名

每个 Agent Note 有两个维度，都编码在路径里——`{lifecycle}/{class}/yyyy-mm-dd-topic-title.md`：

- **生命周期**（顶层目录）就是它的状态，状态变了文件跟着换目录：
  - **`proposed/`**——实施前评审的提议，尚未建成（或只建成一部分）。
  - **`implemented/`**——决定已交付。文件记录定了什么、否掉了什么，并**跟实际交付保持同步**：代码后来挪了文件、改了包名、换了默认值，note 在同一次改动里跟着改（只改事实——路径、名字、结构，不改决定本身）。规矩见 [implemented/AGENTS.md](implemented/AGENTS.md)。
  - **`rejected/`**——提议考虑过并被否。只在它的理由还能挡住一个诱人的错误时保留，否则连文件一起删。
- **分类**（嵌套目录）是决定的种类，见下面[分类](#分类)。

文件名里的日期是这个话题**首次提出**的日期。note 之间互相引用用相对 Markdown 链接，不写裸编号或散文描述，这样链接可被机械检查，文件换目录也不会断。

现行树就是工作清单：浏览 lifecycle/class 目录或在仓库里搜。**不要建 `INDEX.md`**：它重复路径里已有的元数据，还让互不相干的改动争抢同一个文件。有历史价值但不再指导未来的 `implemented/` note 移进独立的冻结归档树 [`archived/`](archived/AGENTS.md)，规则见下文。

## 分类

每个 note 属于 `scripts/agent-note-tree.ts` 里那个闭集中的一个类，分类门禁拒绝其它目录名。增加一个类要同时改那份清单与本节。

| 类 | 覆盖什么 |
|---|---|
| `feature` | 新的、用户可见或模型可见的能力。 |
| `bug-fix` | 修正缺陷，或补上某个复盘暴露的缺口。 |
| `simplification` | 删代码、删行为、删接触面，不新增能力。 |
| `architecture` | 关于**已交付源码**的结构决定——补丁之间怎么分工、运行时与打包的词汇是什么。 |
| `process` | 围绕代码的工具、策略与流程——门禁、包管理器、hooks、发版流程，不是运行时行为。 |
| `testing` | 测试基础设施与测试策略。 |

`architecture` 与 `process` 的分界：**architecture** 管我们交付的源码，**process** 管围绕它的工具与流程。`refactor` 故意缺席——它与 `simplification` 重叠，后者的判据"可观察行为变了吗"已经盖住它。

## 归档与删除

只描述小幅 UI 调整或纯机械改动的 `implemented/` note 直接删；实现小不构成删除理由——局部缺陷修复、性能改动、新能力、实质行为决定都不算。其余 note 只有同时满足三条才归档：决定已完结、理由不太会指导未来工作、记录仍有历史决策价值。它的备选方案、归属边界、负向保证、持久或线上语义、安全规则、重新引入的条件仍有用时，就留在现行树里。**`proposed/` 永不归档**：过时的提议直接 reject。`rejected/` 只在还能挡住一个可信的错误时保留，否则删。

归档路径是 `archived/{class}/yyyy-mm-dd-topic-title.md`；其中故意没有 `implemented`，因为只有已交付的 note 能进。归档动作：把文件整体移过去、保留 `Status: implemented`、在 status 行下紧接一行 `Archived: YYYY-MM-DD`、修好或删掉所有指向它的链接。这是归档期间唯一允许的正文改动。

封存之后永久冻结：不改、不重排、不翻译、不修、不删、不移动，也不把它当作现行行为的权威。文档门禁跳过归档件，包括它指向外面的链接；现行正文可以有意链接进归档以引用历史。`verify-archived-agent-notes` 校验关闭的类目录树、归档日期、以及只增不改的内容清单。

## 什么时候写

只有代码、测试与现有文档都装不下的持久决策理由，才需要新建或更新 Agent Note，且与改动同一个 PR。重大未来工作的提议从 `proposed/` 开始；已经作出的决定从 `implemented/` 开始。更新已经拥有该决定的 note 就算满足这条规则，不要再建重复的一份。

机械改动与局部改动（含局部 UI 表现与交互调整）豁免。Agent Note 不会被编辑成**另一个决定**：用新 note 取代，两条互相链接，除非旧 note 之后按下面的规则被完全合并。编辑 `implemented/` note 让它跟着决定现在住在哪，是要求而不是禁止。

被完全取代的 `implemented/` note 可以并入现任 note 后删除。删除前，现任 note 必须保留旧 note 里每一条独有理由、备选、后果、必需验证与具名覆盖缺口，修好每一条入向链接；合并不得把旧文件改写成它的反面，也不得让 git 历史成为理由的唯一副本。部分取代不算：两条都留着并互相链接，把仍然成立的事实更新好。

## 文件格式

每个现行 note 遵循同一种格式，由 `pnpm run verify-agent-note-format` 执行。归档件保持它被封存时的格式，另加归档日期行。

### 头部三行

每个 note 的前三行固定，之后空一行：

```markdown
# Agent Note: <标题>

Status: <状态>
```

`Status:` 只有三种形式，且必须与所在目录一致——门禁交叉校验：

- `Status: proposed`
- `Status: implemented`
- `Status: rejected — <一句话理由>`

状态不带日期、不带括号补充：文件名持首次提出日期，其余交给 git；"以修正后的形式通过"属于正文——在陈述决定的地方写明修正。拒绝理由是唯一带内容的状态，因为否掉它是读者来这里的唯一目的。

正文标题行是中文，但 `# Agent Note: ` 前缀与 `Status:` 行保持上面这个字面形态，门禁按它们定位。

### 正文骨架

每份 note 的正文以 `## Problem` 开头——动机，要能脱离解决方案独立成立。之后按生命周期不同；复现出现的章节只许用下面这些名字，真正专属的技术章节（补丁拓扑、rpm 契约、退出码表）在必需章节之间自由发挥。

#### `proposed/`

```markdown
## Problem
## Proposal
…专属章节…
## Alternatives considered
## Acceptance criteria
## Risks
```

`## Proposal` 是打算做的改动，可以正当地用将来时：计划、迁移步骤、未解问题都属于这里。`## Acceptance criteria` 说清可观察的什么状态算做完。`## Risks` 同时覆盖可能出错的地方与这次改动明知放弃的东西。

#### `implemented/`

```markdown
## Problem
## Decision
…专属章节…
## Alternatives considered
## Consequences
```

`## Decision` 用现在时描述已交付的现实，整个文件跟着它保持同步。`## Consequences` 记录这笔取舍付出了什么、又买到了什么。提议期的标题在这里是假设式表述，门禁拒绝：`## Proposal`、`## Plan`、`## Migration plan`、`## Acceptance criteria` 不得出现在 implemented note 里。`## Testing`、`## Deferred`、`## Related` 只要陈述现在时事实就可以用。

#### `rejected/`

被否的 note 是冻结的提议：保留它提议期的章节（含 `## Acceptance criteria` 或 `## Plan`），裁定写在 `Status:` 行。只要求头部三行、`## Problem` 开头、`## Proposal` 一节，以及下面强制的备选章节。

### 备选方案：强制

每份 note 都带 `## Alternatives considered`：每个真实备选一段，加粗开头，说明它为什么输了；争议大的备选用 `### 为什么不是 <X>？` 小节。不带"它打败了什么"的决定会招致重开争论——那正是 Agent Note 要防的失败。

备选是记录下来的，不是编出来的。确实无法从记录重建的早期 note 用这一行精确注释代替，门禁只接受这种形态：

```markdown
<!-- agent-note-format: alternatives-not-recorded (pre-format Agent Note) -->
```

### 在生命周期之间移动

换目录意味着同一次改动里更新 `Status:` 行并重新满足新目录的骨架，否则门禁失败。`proposed/` → `implemented/` 要把 `## Proposal` 改写成现在时的 `## Decision`，把 `## Acceptance criteria` 与 `## Risks` 折进 `## Consequences`（或用现在时的 `## Testing`/`## Verification` 说明什么在钉住该行为），并丢掉计划、只留已交付的东西。`proposed/` → `rejected/` 只往 `Status:` 行加理由并冻结文件。
