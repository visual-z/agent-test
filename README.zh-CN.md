# agent-test

由 AI 编程助手驱动的自主 UI agent 测试工具。装进 **Claude Code** 或 **OpenCode**，它会自动发现所有路由、点击每个按钮、截图每个状态变化，最后输出一份 bug 报告。启动之后人就可以走开了。

![Version](https://img.shields.io/badge/version-0.1.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Claude%20Code%20%7C%20OpenCode-purple)

**[English](README.md)** | 如果你是 AI Agent，请阅读 **[AGENTS.md](AGENTS.md)**

---

## 这是什么？

agent-test 是一个 skill + plugin 的组合包，把 AI 编程助手变成自主 QA 测试员。它会：

1. **发现** Web 应用中所有可导航的路由
2. **测试** 每个路由——用深度优先"全部点一遍"算法
3. **截图** 每一次状态变化
4. **审查** 所有截图，找出 bug（视觉、功能、UX）
5. **生成** 按严重等级排列的结构化 bug 报告

初始命令之后整个流水线无人值守运行。外部 **Ralph Loop** 驱动器（Geoffrey Huntley 提出的社区模式）通过读取状态文件并注入续行提示词来驱动 agent 完成各个阶段——agent 自己从不控制循环。

## 工作原理

```
阶段 1: 初始化      路由发现 → 用户选择测试范围 → 创建状态文件
阶段 2: 测试执行    分批路由 → 派发子 agent → DFS 全点击 → 截图 + 报告
阶段 3: Bug 审查    分批审查 → 检查截图 → 生成每个路由的 bug 报告
阶段 4: 汇总报告    汇总所有 bug 报告 → FINAL-REPORT.md → 完成
```

Ralph Loop 驱动器（Claude Code 的 hook 或 OpenCode 的 plugin）在 agent 空闲时读取 `.monkey-test-state.json`，决定下一步动作：

| 状态条件 | 动作 |
|---|---|
| `pending > 0` | 继续测试 |
| `pending == 0`, `review_pending > 0` | 继续审查 |
| 全部审查完，没有 `FINAL-REPORT.md` | 生成最终报告 |
| `FINAL-REPORT.md` 已存在 | 完成——agent 停止 |
| 状态连续 3 轮不变 | 检测到停滞——agent 停止 |

状态文件是唯一的真相来源。agent 不需要输出特殊标记，也不需要自己控制循环。

## 快速开始

### 前置条件

- **jq** — JSON 解析工具（macOS: `brew install jq`, Linux: `apt install jq`）
- **Agent Browser** — 测试子 agent 使用的无头浏览器。安装方式：`npm install -g agent-browser`（详见 [agent-browser GitHub](https://github.com/vercel-labs/agent-browser)）
- **Claude Code** 或 **OpenCode** — 需支持 plugin/hook

### Claude Code

**一键安装（在 agent-test 仓库根目录执行）：**

```bash
bash install/install-claude-code.sh --project
```

将 plugin、skills、prompts 和 reference 文档复制到当前项目的 `.claude/` 目录。

**其他安装方式：**

```bash
# 交互式（提示选择项目级还是全局）
bash install/install-claude-code.sh

# 全局安装（对所有项目生效）
bash install/install-claude-code.sh --global

# 通过 npm 脚本
npm run install:claude-code
npm run install:claude-code:project
npm run install:claude-code:global

# 开发模式：直接加载不复制
claude --plugin-dir ./plugins/claude-code
```

然后打开 Claude Code 说：**"Run agent test on this project"**

### OpenCode

**一键安装（在 agent-test 仓库根目录执行）：**

```bash
bash install/install-opencode.sh --project
```

将 plugin、skills、prompts 和 reference 文档复制到当前项目的 `.opencode/` 目录。

**其他安装方式：**

```bash
# 交互式（提示选择项目级还是全局）
bash install/install-opencode.sh

# 全局安装（对所有项目生效）
bash install/install-opencode.sh --global

# 通过 npm 脚本
npm run install:opencode
npm run install:opencode:project
npm run install:opencode:global
```

然后打开 OpenCode 说：**"Run agent test on this project"**

### 手动安装

如果不想用安装脚本：

**Claude Code：**
```bash
# Plugin（官方插件格式）
mkdir -p .claude/plugins/monkey-test/{.claude-plugin,hooks,scripts}
cp plugins/claude-code/.claude-plugin/plugin.json .claude/plugins/monkey-test/.claude-plugin/
cp plugins/claude-code/hooks/hooks.json .claude/plugins/monkey-test/hooks/
cp plugins/claude-code/scripts/ralph-loop.sh .claude/plugins/monkey-test/scripts/
chmod +x .claude/plugins/monkey-test/scripts/ralph-loop.sh

# Skills、prompts、reference 文档
mkdir -p .claude/skills/monkey-test
cp SKILL.md .claude/skills/monkey-test/
cp -R skills/ .claude/skills/monkey-test/skills/
cp -R prompts/ .claude/skills/monkey-test/prompts/
cp -R reference/ .claude/skills/monkey-test/reference/
```

**OpenCode：**
```bash
# Plugin
mkdir -p .opencode/plugins
cp plugins/opencode/index.ts .opencode/plugins/monkey-test-loop.ts

# Skills、prompts、reference 文档
mkdir -p .opencode/skills/monkey-test
cp SKILL.md .opencode/skills/monkey-test/
cp -R skills/ .opencode/skills/monkey-test/skills/
cp -R prompts/ .opencode/skills/monkey-test/prompts/
cp -R reference/ .opencode/skills/monkey-test/reference/
```

## 配置

启动时 agent 会询问以下配置：

| 配置项 | 默认值 | 说明 |
|---|---|---|
| `base_url` | *（必填）* | 应用 URL（如 `http://localhost:3000`） |
| `credentials` | *（可选）* | 需要登录时提供用户名/密码 |
| `batch_size` | `3` | 每轮测试的路由数 |
| `review_batch_size` | `5` | 每轮审查的路由数 |
| `safe_to_mutate` | `false` | 是否允许破坏性操作（创建、删除、提交表单） |
| `max_iterations` | `100` | Ralph Loop 最大迭代次数 |

### 环境变量

启动 agent 前在 shell 或 `.env` 中设置：

```bash
MONKEY_TEST_BASE_URL="http://localhost:3000"
MONKEY_TEST_USERNAME="admin"
MONKEY_TEST_PASSWORD="password"
MONKEY_TEST_BATCH_SIZE=5
MONKEY_TEST_SAFE_TO_MUTATE=false
```

### Ralph Loop 安全限制

驱动器强制执行安全限制，防止失控：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `MONKEY_TEST_MAX_ITERATIONS_PER_SESSION` | `10` | 单会话迭代上限（防止上下文溢出）。达到后开新会话继续。 |
| `MONKEY_TEST_MAX_TOTAL_ITERATIONS` | `100` | 跨会话的绝对上限。 |

## 监控进度

### 实时状态

```bash
jq '.meta' .monkey-test-state.json
```

### 循环状态

```bash
jq '.' .monkey-test-loop-state.json
```

### 断点续测

如果会话中途结束，开一个新会话说 **"resume agent test"**，agent 会读取状态文件从断点继续。

## 停止循环

| 方式 | 操作 |
|---|---|
| **等它跑完** | `FINAL-REPORT.md` 生成后循环自动停止 |
| **暂停** | `mv .monkey-test-state.json .monkey-test-state.json.paused` — 改回名字即可恢复 |
| **重置计数** | `rm .monkey-test-loop-state.json` — 重置迭代计数器 |
| **卸载** | `bash install/install-claude-code.sh --uninstall` 或 `bash install/install-opencode.sh --uninstall` |

## 输出

完整测试后项目目录结构：

```
project-root/
├── ROUTE_MAP.md                          # 所有发现的路由
├── .monkey-test-state.json               # 进度追踪
├── monkey-test-screenshots/
│   ├── settings_general/
│   │   ├── 00-login-success.png
│   │   ├── 01-table-page.png
│   │   ├── 02-toolbar-create.png
│   │   └── ...
│   └── products_inventory/
│       └── ...
└── monkey-test-reports/
    ├── settings_general.json                # 测试报告（结构化操作树）
    ├── settings_general-bugs.md             # Bug 分析（审查员输出）
    ├── products_inventory.json
    ├── products_inventory-bugs.md
    └── FINAL-REPORT.md                   # 汇总报告
```

## 项目结构

```
agent-test/
├── SKILL.md                              # 主编排 skill
├── AGENTS.md                             # AI agent 指令
├── README.md                             # 英文文档
├── README.zh-CN.md                       # 中文文档（本文件）
├── package.json
├── skills/
│   ├── page-testing/SKILL.md             # DFS 全点击算法
│   ├── route-discovery/SKILL.md          # 路由发现策略
│   ├── screenshot-protocol/SKILL.md      # 截图时机与命名
│   └── state-management/SKILL.md         # 状态文件操作
├── prompts/
│   ├── page-tester-agent.md              # 测试子 agent 模板
│   ├── report-reviewer-agent.md          # 审查子 agent 模板
│   └── ralph-loop-harness.md             # 续行提示词模板
├── reference/
│   ├── state-schema.md                   # 状态文件 JSON schema
│   ├── report-format.md                  # 测试报告 JSON schema
│   ├── bug-report-format.md              # Bug 报告 Markdown schema
│   └── testing-reference.md              # 结果分类指南
├── plugins/
│   ├── claude-code/                      # Claude Code Stop hook 插件
│   │   ├── .claude-plugin/plugin.json
│   │   ├── hooks/hooks.json
│   │   ├── scripts/ralph-loop.sh
│   │   └── README.md
│   └── opencode/                         # OpenCode 事件插件
│       ├── index.ts
│       ├── package.json
│       └── README.md
└── install/
    ├── install-claude-code.sh            # Claude Code 一键安装脚本
    └── install-opencode.sh               # OpenCode 一键安装脚本
```

## 常见问题

**会修改我的应用吗？**
只有设置 `safe_to_mutate=true` 才会。默认情况下 agent 不执行创建/删除/提交操作。它仍然会点开对话框和表单，但不会确认破坏性操作。

**完整测试要多久？**
取决于路由数量和复杂度。一个 50 路由的应用通常需要 20-40 轮迭代（batch size 3），每轮 2-5 分钟。总计：1-3 小时无人值守。

**用什么浏览器？**
Agent Browser (`agent-browser`)——由 Vercel 开发的面向 AI agent 的无头浏览器。通过 `npm install -g agent-browser` 安装（详见 [GitHub](https://github.com/vercel-labs/agent-browser)）。不需要 Playwright、Puppeteer 或 Selenium。

**能只测特定页面吗？**
可以。初始化时 agent 会展示发现的路由并让你选择：全部、按分类、或选择具体页面。

**应用需要登录怎么办？**
初始化时提供账号密码。每个子 agent 会在测试开始时独立登录。

**支持哪些 Web 框架？**
全部。路由发现支持 React Router、Vue Router、Angular、Next.js、Nuxt 及通用路由文件。基于浏览器的测试对任何 Web 应用都有效。

**能断点续测吗？**
可以。状态文件追踪进度。开一个新会话说"resume agent test"即可。

## 贡献

1. Fork 仓库
2. 创建 feature 分支：`git checkout -b feature/my-improvement`
3. 修改——skills、prompts、reference 文档保持 Markdown 格式
4. 修改安装脚本时请在两个平台上测试
5. 提交 Pull Request

**准则：**
- Skills 必须**平台无关**——在任何支持子 agent 派发的 AI agent 上都能运行
- Plugins 是**平台特定的**——每个支持的环境一个
- Ralph Loop 约定（状态文件 + 续行提示词 + 阶段检测）是集成边界

## License

MIT
