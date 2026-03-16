# Commander

Commander 是一个 macOS 菜单栏命令面板：  
Swift 负责窗口/UI/渲染与进程面板，Python 负责命令路由、插件和配置扩展。

## 核心能力

- 命令输入 + 历史记录 + 输出渲染（Markdown / 代码块）
- AI 路由（Gemini / OpenAI 兼容接口）
- Shell 命令执行（同步输出或进入交互 process 面板）
- 插件化命令系统（内置 + 外部插件）
- 可通过命令动态管理设置与插件开关

## 架构概览

- Swift 层
  - 入口/UI：`CommanderApp.swift`、`ContentView.swift`
  - Python 通信：`PythonCommandService.swift`
  - 终端会话：`ShellSessionService.swift`
- Python 层
  - 入口：`python/commander_engine.py`
  - 路由：`python/command_engine/router.py`
  - 插件注册：`python/command_engine/plugin_registry.py`
  - 内置插件：`python/command_engine/plugins/`

执行流程（简化）：
1. Swift 把 `query + settings` 组装成 JSON
2. 调用 Python 引擎得到标准响应 JSON
3. Swift 根据响应字段渲染输出/打开设置/启动 process/发起 AI 请求

## 快速开始

### 1) 环境准备

- macOS + Xcode（命令行工具可用）
- Python 3.12（见 `.python-version`）
- `uv`（Python 依赖管理）

### 2) 安装 Python 依赖

```bash
cd /Users/cr/commander/Commander
uv sync
```

### 3) 本地构建运行

```bash
./build_run.sh
```

常见变体：

```bash
./build_run.sh --release --no-open
./build_run.sh --clean --debug
```

## 常用命令（应用内）

- `help`：显示动态帮助（按当前激活插件）
- `set` / `set list` / `set <key> <value>`：查看或修改设置
- `plugins` / `plugins enable ...` / `plugins disable ...`：管理插件开关
- `run <cmd>`：执行 shell 命令
- `run <cmd> &`：在 process 面板中交互执行
- `terminal [cmd]`：打开终端会话（可为空）
- `ai <prompt>` / `ask <prompt>`：强制 AI 模式
- `def <word>`：词典模式
- `read <url>`：通过 Jina Reader 获取 Markdown
- `music ...`：音乐插件命令（`p` 为别名）

## 插件机制

- 内置插件：`core/shell/music/web/ai/read`
- 外部插件目录：`~/Library/Application Support/Commander/plugins/`
- 配置目录：`~/Library/Application Support/Commander/config.json`

插件开关：

```text
set enabled_plugins ai,read
set disabled_plugins music
plugins reset
```

插件示例见：`python/plugin_samples/PLUGIN_SAMPLES.md`

## 脚本与自动化

详细脚本文档见：
- `SCRIPTS.md`

关键脚本：
- `build_run.sh`：本地构建/启动
- `scripts/release_gate.sh`：发版门禁检查
- `scripts/build_after_push.sh`：仅在已 push 后编译当前提交

## CI / Release

仓库根目录工作流：
- `.github/workflows/ci.yml`：PR / main 分支门禁
- `.github/workflows/release.yml`：tag (`v*`) 自动构建并发布 Release

本地发版前建议：

```bash
bash scripts/release_gate.sh --min-commits-since-tag 3
```

打 tag 触发发布：

```bash
git tag v0.3.0
git push origin v0.3.0
```
