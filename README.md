# Commander

<p align="center">
  <img src="Commander/design/icons/svgviewer-output-1024.png" alt="Commander 图标" width="160" height="160">
</p>

<p align="center">
  一个面向 macOS 的菜单栏命令应用，把命令执行、AI 问答、Markdown 阅读、待办和预览能力收进同一个输入框。
</p>

## 这是什么

Commander 是一个原生 macOS 应用。

你可以把它理解成一个长期驻留在菜单栏里的命令入口：

- 输入普通命令，执行 shell 或打开终端进程
- 输入 `ai`、`ask`、`def`、`read`，把 AI、词典和网页阅读整合到同一套体验里
- 输入 `todo`、`note`、`preview`，直接打开待办、记事本和文件预览窗口
- 对 AI 返回的代码块，直接复制、运行或进入内置编辑器继续修改

它不是单纯的终端壳，也不是只会对话的 AI 面板，而是一个偏生产力方向的 macOS 命令工作台。

## 适合做什么

- 快速执行一条命令，不想切换到完整终端
- 临时查资料、读网页 Markdown、问 AI
- 把 AI 生成的 Python / Shell 代码直接运行或编辑
- 维护一份轻量 todo 列表或临时笔记
- 从命令入口直接预览图片、PDF 和常见文件

## 主要功能

- 原生 macOS 菜单栏应用体验
- 单输入框命令路由
- Markdown / 数学公式 / 代码块渲染
- AI 流式输出
- 内置终端进程区与独立窗口
- 代码块复制、运行、编辑
- Todo、Note、文件与图片预览
- Python 插件化命令系统
- 可配置设置与插件开关

## 常用命令

```text
help
ai 解释一下麦克斯韦方程组
read https://example.com/article
run ls -la
terminal
todo 买牛奶
note 灵感
preview ~/Desktop/test.pdf
def impedance
```

## 运行环境

- macOS
- Xcode 与 Command Line Tools
- Python 3.12
- `uv`

## 本地开发

安装 Python 依赖：

```bash
cd /Users/cr/commander/Commander
uv sync
```

本地构建运行：

```bash
cd /Users/cr/commander/Commander
./build_run.sh
```

常用变体：

```bash
./build_run.sh --release --no-open
./build_run.sh --clean --debug
```

## 项目结构

- `Commander/`：应用源码、Python 引擎、资源与脚本
- `Commander.xcodeproj/`：Xcode 工程
- `.github/workflows/`：CI 与 Release 工作流

核心模块：

- Swift UI：窗口、输入、渲染、进程管理
- Python Engine：命令路由、插件、配置、AI 请求参数拼装

## 发布

门禁检查：

```bash
bash Commander/scripts/release_gate.sh
```

测试后自动提交：

```bash
bash Commander/scripts/test_and_commit.sh --message "feat: your change"
```

生成版本说明：

```bash
bash Commander/scripts/release_notes.sh --tag v1.0.3
```

一键发版：

```bash
bash Commander/scripts/release_publish.sh --tag v1.0.3
```

## 补充说明

- 详细脚本文档见 [Commander/SCRIPTS.md](/Users/cr/commander/Commander/SCRIPTS.md)
- 应用内 Python 配置位于 `~/Library/Application Support/Commander/config.json`
- 外部插件目录位于 `~/Library/Application Support/Commander/plugins/`
