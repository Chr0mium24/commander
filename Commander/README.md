# Commander

<p align="center">
  <img src="design/icons/svgviewer-output-1024.png" alt="Commander 图标" width="160" height="160">
</p>

<p align="center">
  一个面向 macOS 的菜单栏命令应用，把命令执行、AI、阅读、待办和预览能力放进同一个入口。
</p>

## 简介

Commander 是一个原生 macOS 应用，不是单纯的终端，也不是只做对话的 AI 面板。

它把命令输入、AI 问答、Markdown 渲染、终端进程、代码运行、待办和预览整合成一套更轻的工作流，适合日常开发和信息处理。

## 主要功能

- 菜单栏常驻，随时呼出
- 单输入框路由命令
- Markdown / 数学公式 / 代码块渲染
- AI 流式输出
- Shell 命令执行与终端进程管理
- 代码块复制、运行、内置编辑
- Todo、Note、图片和文件预览
- Python 插件机制与动态设置

## 典型使用

- `help`：查看当前可用命令
- `ai xxx`：直接进入 AI 模式
- `read <url>`：读取网页并转成 Markdown
- `run <cmd>`：运行 shell 命令
- `terminal`：打开独立终端
- `todo 买牛奶`：直接追加一条待办
- `note 灵感`：打开记事窗口
- `preview ~/Desktop/test.pdf`：预览文件

## 环境要求

- macOS
- Xcode 与 Command Line Tools
- Python 3.12
- `uv`

## 本地开发

安装依赖：

```bash
cd /Users/cr/commander/Commander
uv sync
```

启动应用：

```bash
./build_run.sh
```

常用变体：

```bash
./build_run.sh --release --no-open
./build_run.sh --clean --debug
```

## 发布相关

门禁检查：

```bash
bash scripts/release_gate.sh
```

测试后自动提交：

```bash
bash scripts/test_and_commit.sh --message "feat: your change"
```

生成发版素材：

```bash
bash scripts/release_notes.sh --tag v1.0.3
```

一键发版：

```bash
bash scripts/release_publish.sh --tag v1.0.3 --notes-file /tmp/release-notes.md
```

## 目录说明

- `Commander/`：Swift 源码、Python 引擎、资源、脚本
- `python/command_engine/`：命令路由、插件、配置
- `scripts/`：构建、门禁、提交、发版脚本
- `design/icons/`：图标资源

详细脚本说明见 [SCRIPTS.md](/Users/cr/commander/Commander/SCRIPTS.md)。
