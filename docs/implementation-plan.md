# Skill Router 首版实施计划

状态：首版本地可用实现已完成；GitHub 发布准备待后续授权  
依据：[首版产品规格](./product-spec.md)、[领域语言](../CONTEXT.md)、[ADR 目录](./adr/)  
计划日期：2026-07-24

## 1. 实施原则

1. 先实现无 UI 的可测试核心，再接 CLI，最后接 SwiftUI。
2. 原生应用与 CLI 必须调用同一 `SkillRouterCore`，不得复制业务规则。
3. 所有文件系统测试使用临时根目录，禁止触碰真实 `~/.skill-router`。
4. 每个阶段先固定契约和失败语义，再实现成功路径。
5. 中央库事务与项目协调分开实现，不能伪装成跨所有项目的原子事务。
6. “链接结构正确”是首版验收上限，不把结构测试写成 Agent 真实可用。
7. 未经单独授权，不初始化 Git、不提交、不发布 GitHub Release。

## 2. 实施前置条件

### 2.1 必需环境

- 已安装并选中 Xcode 26.3（Build 17C529），许可协议和首次启动设置均已完成。
- 使用 macOS 26.2 SDK，并将部署目标设为 macOS 15。
- 只构建 `arm64`。
- 以当前 Xcode 自带的 Apple Swift 6.2.4 为构建事实源。

### 2.2 首轮技术决策门

以下可替换实现细节已在阶段 0 完成验证，不改变产品契约：

- YAML frontmatter：采用只覆盖首版必需元数据的逐行受限解析器，不把它表述为完整 YAML 实现。
- ZIP：封装系统 `/usr/bin/zip` 与 `/usr/bin/ditto`，解包前检查重复项和路径穿越，解包后逐文件校验。
- Git：封装系统 `/usr/bin/git` 子进程，不引入 libgit2；测试使用本地临时仓库，不依赖公网。
- 文件锁：使用 Darwin `flock`，App 与 CLI 共用同一锁文件并支持约 5 秒超时。
- 原子替换：使用同文件系统暂存、重命名和事务日志；四个提交检查点均有故障注入恢复测试。
- 最终 Bundle Identifier、Developer ID 团队和 GitHub 仓库地址在发布阶段确定。

## 3. 建议代码结构

```text
skill_router/
├── Package.swift
├── Sources/
│   ├── SkillRouterCore/
│   │   ├── Domain/
│   │   ├── Manifest/
│   │   ├── Storage/
│   │   ├── Importing/
│   │   ├── Distribution/
│   │   ├── Projects/
│   │   ├── Updating/
│   │   ├── Exporting/
│   │   └── SystemSkill/
│   └── skill-router/
│       └── main.swift
├── Tests/
│   ├── SkillRouterCoreTests/
│   ├── SkillRouterFileSystemTests/
│   └── SkillRouterCLITests/
├── App/
│   ├── SkillRouter.xcodeproj
│   └── SkillRouter/
│       ├── App/
│       ├── Features/
│       └── AppKitBridges/
├── Resources/
│   └── system-skills/
│       └── skill-router/
│           └── SKILL.md
├── CONTEXT.md
└── docs/
```

目录是实施建议，不是外部文件格式。若 Xcode 工程采用其他布局，仍必须维持 Core、CLI、App 和测试边界。

## 4. 核心模块职责

### 4.1 Domain

定义值类型和不变量：

- `SkillName`
- `SuiteName`
- `ManagedSkill`
- `StandaloneSkill`
- `SkillSuite`
- `LocalSkill` / `SourceSkill`
- `RegisteredProject`
- `DistributionTarget`
- `DesiredSkillAssignment`
- `ReconciliationStatus`
- `UpdateAvailability`

所有名称构造必须立即校验。不得在 UI 或 CLI 各自复制正则和状态转换。

### 4.2 Manifest

负责三类版本化 JSON：

1. 应用状态 `state.json`；
2. 项目清单 `.skill-router.json`；
3. `.skillrouter` 制品清单。

每类格式分别定义 schema 版本、兼容读取、迁移、未知版本拒绝和稳定排序。写出 JSON 时使用确定性字段与数组顺序，便于 Git diff 和测试。

### 4.3 Storage

负责：

- 解析 `SKILL_ROUTER_HOME` 测试覆盖值，生产默认 `~/.skill-router`；
- 创建中央目录结构；
- 排他文件锁和 5 秒超时；
- JSON 原子写；
- 事务日志、暂存、提交和恢复；
- 稳定分发入口创建与修复；
- 受管链接识别，禁止删除不受管路径。

### 4.4 Importing

负责：

- 本地目录一次性导入；
- 公开 Git 默认分支获取；
- 候选递归发现和排除；
- `SKILL.md` frontmatter 解析；
- Skill 名称和全局冲突校验；
- 单候选独立 Skill、多候选套件；
- Git 内部来源区与中央展示区映射；
- 原样保留来源软链接。

### 4.5 Projects 与 Distribution

负责：

- 本机规范化路径与文件书签；
- 内置和自定义目标；
- 项目清单读写；
- 绝对项目链接到稳定分发入口；
- 冲突、警告、错误、待协调和偏差计算；
- 注册、取消注册、安装、卸载、卸载全部、协调；
- Git 忽略项建议，但不自动修改 `.gitignore`。

### 4.6 Updating

负责：

- 应用运行时的 24 小时检查节流；
- 按 Git 默认分支最新提交判断有无更新；
- 用户确认后的来源刷新；
- 新候选发现；
- 上游删除和改名；
- 中央先提交、项目尽力级联；
- 项目清理失败后的派生偏差。

### 4.7 Exporting

负责：

- 选择全部或部分中央内容；
- 生成版本化制品清单；
- ZIP 打包和逐文件完整性值；
- 导入前路径、schema 和校验值验证；
- 同名 Skill 逐项替换/跳过；
- 同名异源套件重命名/跳过；
- 不导出机器和项目状态。

### 4.8 SystemSkill

负责：

- 安装内置 `skill-router` Skill 内容；
- 安装 `~/.skill-router/bin/skill-router`；
- 自动建立 Codex 与 Claude Code 全局入口；
- 检查、停用和修复入口；
- 保证系统 Skill 只调用 CLI，不直接编辑项目文件。

## 5. 分阶段实施

### 阶段 0：工程与技术验证（已完成）

交付：

- Swift Package、CLI target、macOS App target 和测试 target；
- `SkillRouterCore` 可同时被 CLI 与 App 引用；
- 临时根目录测试夹具；
- YAML、ZIP、Git、文件锁和原子替换的最小验证结果。

门禁：

- `swift test` 可运行；
- `xcodebuild test` 可构建最小 App target；
- 测试不会创建真实 `~/.skill-router`。

### 阶段 1：领域模型与 JSON 契约（已完成）

交付：

- 名称、套件、项目、目标和状态值类型；
- 三类 JSON schema v1；
- 确定性编码与迁移框架；
- 中文错误分类。

测试：

- 合法/非法名称边界；
- 重复字段、缺字段、未知 schema 和损坏 JSON；
- 项目多目标、多 Skill 映射往返；
- 状态迁移幂等。

### 阶段 2：中央存储、锁与恢复（已完成）

交付：

- `~/.skill-router` 布局；
- App/CLI 共用锁；
- JSON 原子替换；
- 事务日志与暂存目录；
- 启动恢复器。

测试：

- 两进程竞争和 5 秒忙碌失败；
- 每个提交点前后注入失败；
- 恢复重复执行不破坏已完成状态；
- 不可恢复损坏停止写入。

### 阶段 3：发现与本地导入（已完成）

交付：

- 候选递归发现；
- 本地单 Skill 导入；
- 本地多 Skill 选择与套件导入；
- 全局名称冲突的替换/跳过；
- 稳定分发入口。

测试：

- 隐藏目录、依赖目录、构建目录排除；
- 来源目录名与 `name` 不同；
- 软链接、断链和越界链接原样保留；
- 单候选与多候选边界；
- 替换保持稳定入口。

### 阶段 4：项目清单与分发（已完成）

交付：

- 项目注册和取消注册；
- Codex、Claude Code、自定义目标；
- 绝对双层软链接；
- 安装、卸载、卸载全部和协调；
- 冲突与待协调状态；
- Git 忽略项建议。

测试：

- 完整链接链路解析到正确 `SKILL.md`；
- 不允许复制替代链接；
- 不受管文件/目录/链接永不覆盖；
- 批量请求缺失名称只跳过缺失项；
- 目标冲突保留有效意图；
- 项目移动、重复注册和不同 worktree。

### 阶段 5：正式 CLI 与系统 Skill（已完成）

交付：

- 项目侧稳定命令；
- 中文文本与 `--json`；
- stdout/stderr 分离和退出码；
- `skill-router` 系统 Skill；
- 首次启动自动安装 CLI 和两个全局入口。

测试：

- CLI 黑盒执行；
- JSON 输出 schema；
- 部分完成非零；
- App 不运行时注册和安装；
- 系统 Skill 内容只调用固定 CLI 路径；
- 修复损坏全局入口。

### 阶段 6：公开 Git 来源与更新（已完成）

交付：

- 公开 URL 和默认分支；
- 单仓一次获取；
- Git 来源内部区；
- 更新检查、徽标和用户确认；
- 新增、删除和改名处理；
- 尽力项目级联与偏差扫描。

测试：

- 使用本地临时 Git 远端模拟默认分支；
- 新提交产生更新通知但不改中央库；
- 用户确认后刷新；
- 上游删除立即删除中央内容；
- 一个项目不可写不回滚中央更新；
- 再次扫描能派生项目偏差。

### 阶段 7：导出与导入制品（已完成）

交付：

- `.skillrouter` 导出；
- schema 与完整性值；
- 全量/选择导出；
- 安全解包；
- 冲突处理和来源关系恢复。

测试：

- 制品确定性；
- 单文件损坏、路径穿越、重复路径和未知 schema；
- 不含项目路径、书签、链接或 Git 缓存；
- 同名逐项替换/跳过；
- 同名异源套件重命名/跳过。

### 阶段 8：SwiftUI 原生界面（已完成）

交付：

- Skills、项目、更新、系统 Skill、设置五个一级页面；
- 本地/Git 导入流程；
- 列表—详情和反向引用；
- 项目加入、目标确认、协调和卸载；
- 更新确认、删除确认、导入/导出；
- Finder 打开入口；
- 应用内更新徽标。

测试：

- ViewModel 单元测试；
- 关键 UI Test 使用临时中央根和临时项目；
- UI 不直接实现文件系统规则；
- 错误、部分完成和项目偏差均可见。

### 阶段 9：稳定化与本地可用（已完成）

交付：

- 全量自动测试；
- 首次启动迁移和恢复演练；
- 中文帮助和错误文案；
- 本地 Release 构建；
- 手工操作清单。

门禁：

- 所有结构测试通过；
- 真实用户目录保持未被测试污染；
- 失败日志包含真实退出码；
- 不声称 Codex 或 Claude Code 已真实加载。

### 阶段 10：GitHub 发布准备（后续）

本阶段不属于首个本地可用版本的阻塞项。

交付：

- Developer ID 签名；
- Hardened Runtime；
- Apple 公证与 ticket stapling；
- GitHub Release 制品和校验值；
- 安装/替换说明；
- 不含应用内升级机制。

## 6. 自动测试组织

建议测试命令：

```text
swift test
xcodebuild test -scheme SkillRouter-Package -destination 'platform=macOS,arch=arm64'
```

所有文件系统测试必须显式设置临时根，例如：

```text
SKILL_ROUTER_HOME=/private/tmp/<unique-test-root>
```

测试夹具必须提供：

- 合法和非法 `SKILL.md`；
- 单 Skill 与多 Skill 目录；
- 含内部、越界和断开软链接的 Skill；
- 临时 Git 远端及多个提交；
- 可写、只读和消失的项目目录；
- 不受管同名文件、目录和链接；
- 损坏 JSON、未知 schema、未完成事务；
- 合法、损坏和恶意路径的 `.skillrouter` 制品。

禁止在默认自动测试中运行 `codex` 或 `claude`。

## 7. CLI 错误分类建议

首个公开版本前冻结具体数字。至少区分：

- 完全成功；
- 使用方式错误；
- 输入或 schema 校验失败；
- 名称不存在；
- 不受管路径冲突；
- 部分完成；
- 中央状态忙碌；
- I/O 或权限失败；
- 状态损坏或事务无法恢复；
- 未预期内部错误。

文本与 JSON 必须映射到同一内部错误类型，不能靠解析中文判断。

## 8. 实施中的审查点

每个阶段完成后至少检查：

1. 是否只修改当前阶段范围；
2. 是否有真实失败分支测试；
3. 是否把不受管用户文件误判成受管文件；
4. 是否在错误路径仍返回成功退出码；
5. 是否把结构验证写成 Agent 真实验收；
6. 是否引入未记录的版本、同步、市场、分类或编辑功能；
7. 是否破坏现有 ADR 或领域术语。

## 9. 完成定义

首版本地可用必须同时满足：

- 原生应用能启动并完成首次初始化；
- 本地目录和公开 Git URL 可以导入；
- 独立 Skill 与套件结构正确；
- 项目可以从界面和 CLI 注册；
- Codex、Claude Code 与自定义目标可以形成正确双层软链接；
- `skill-router` 系统 Skill 和 CLI 安装正确；
- 更新、删除、项目偏差和恢复流程可操作；
- `.skillrouter` 可以完整导出和导入；
- 自动测试覆盖冻结规格中的结构与失败边界；
- 文档明确声明未验证 Agent 真实加载；
- 所有用户可见文案为中文。

## 10. 当前阻塞与非阻塞项

### 阻塞实施

- 当前没有阻塞本地实施的开发环境项。

### 不阻塞核心设计

- 尚未初始化 Git 仓库；待用户单独授权后再处理。
- Developer ID、Bundle Identifier 和 GitHub Release 仓库尚未确定；只阻塞对外发布，不阻塞本地版本。
- 当前没有本地运行阻塞项。

## 11. 实施结果

- 工程采用 Swift Package，同时提供 `SkillRouterCore`、正式 CLI 和 SwiftUI App 可执行目标。
- 本地启动入口为仓库根目录的 `./scripts/run-local.sh`。
- 中央库、项目清单、双层绝对软链接、公开 Git 更新、系统 Skill 和 `.skillrouter` 制品流程均已接入同一核心库。
- 项目书签可尽量恢复同目录移动或改名；自定义目标不会再静默回退到 Codex。
- App 界面采用 macOS 系统控件、系统字体和 SF Symbols，保留五个冻结一级页面，并显示加载、错误和部分完成状态。
- 自动验收只证明 Skill 文件系统目录和链接结构正确；没有启动 Codex 或 Claude Code，也不声称 Agent 已真实发现或加载 Skill。
- Developer ID 签名、公证、独立 `.app` 发布制品和 GitHub Release 属于阶段 10，未在本地首版中实施。
