# Commander 脚本文档

本文件汇总当前项目中可直接运行的脚本与自动化流程。

## 运行前提

- 工作目录：`/Users/cr/commander/Commander`
- macOS + Xcode CLI（`xcodebuild` 可用）
- Python 版本由 `.python-version` 指定（当前是 `3.12`）
- 使用 `uv` 管理 Python 依赖
- 音乐插件依赖：
  - `mpv`（或你在设置里指定的播放器）
  - `yt-dlp`

## 1) 本地构建与运行

文件：`build_run.sh`

作用：
- 构建 Commander（Debug/Release）
- 可选清理构建产物
- 可选杀掉旧进程并打开新构建的 App

用法：

```bash
./build_run.sh [options]
```

参数：
- `--release`：Release 构建
- `--debug`：Debug 构建（默认）
- `--clean`：先 clean 再 build
- `--no-open`：只构建，不打开 App
- `--kill`：打开前先 kill 旧 Commander 进程（默认开启）
- `--no-kill`：不 kill 旧进程
- `-h, --help`：查看帮助

常用示例：

```bash
./build_run.sh
./build_run.sh --release --no-open
./build_run.sh --clean --debug
```

## 2) 发布门禁检查（Release Gate）

文件：`scripts/release_gate.sh`

作用：
- Debug 构建检查
- Python 引擎编译检查（`py_compile`）
- 路由冒烟测试（`help` / `plugins`）

用法：

```bash
bash scripts/release_gate.sh [options]
```

参数：
- `-h, --help`：查看帮助

常用示例：

```bash
bash scripts/release_gate.sh
```

说明：
- 这个脚本不会创建 tag，也不会推送代码
- 它只负责“发版前是否通过”的本地质量门禁
- GitHub Action 的 `ci.yml` / `release.yml` 也会复用这套检查逻辑

## 3) 一键发布到 GitHub Release

文件：`scripts/release_publish.sh`

作用：
- 本地执行 `release_gate`（默认开启）
- 推送当前分支（默认 `main`）
- 创建并推送 tag（触发 GitHub Release workflow）

用法：

```bash
./scripts/release_publish.sh --tag <version> [options]
```

参数：
- `--tag <version>`：版本号，支持 `v0.3.0` 或 `0.3.0`
- `--message <text>`：tag 注释
- `--remote <name>`：远端名（默认 `origin`）
- `--branch <name>`：发布分支（默认 `main`）
- `--no-gate`：跳过门禁检查
- `--allow-dirty`：允许工作区未提交
- `--dry-run`：仅打印命令，不执行
- `-h, --help`：查看帮助

常用示例：

```bash
./scripts/release_publish.sh --tag v0.3.0
./scripts/release_publish.sh --tag 0.3.1 --message "Release v0.3.1"
./scripts/release_publish.sh --tag v0.3.2 --dry-run
```

## 4) Push 后一键编译当前提交

文件：`scripts/build_after_push.sh`

作用：
- 检查当前 `HEAD` 是否已同步到上游分支（已 push）
- 通过后调用 `build_run.sh` 编译当前这次提交

用法：

```bash
./scripts/build_after_push.sh [options]
```

参数：
- `--release`：Release 构建（默认）
- `--debug`：Debug 构建
- `--open`：构建后打开 App
- `--no-open`：只构建（默认）
- `--clean`：先 clean 再 build
- `--kill`：打开前先 kill 旧进程
- `--no-kill`：不 kill 旧进程（默认）
- `--skip-push-check`：跳过“是否已 push”检查
- `-h, --help`：查看帮助

常用示例：

```bash
./scripts/build_after_push.sh
./scripts/build_after_push.sh --release --open --kill
./scripts/build_after_push.sh --skip-push-check
```

## 5) 音乐脚本 / 音乐插件

文件：`python/command_engine/plugins/p.py`

作用：
- 作为 `music` 插件后端（别名 `p`）
- 支持本地列表、下载音频、单曲/循环播放、URL/BV 快速播放

CLI 用法：

```bash
python python/command_engine/plugins/p.py [help|ls|add|single|loop|<id>|<url|BV>]
```

命令说明：
- 无参数：随机播放本地歌单
- `ls`：列出音乐目录与 ID
- `add <url|BV> [more ...]`：下载音频到音乐目录
- `single [id]`：随机或按 ID 播放单曲
- `loop <id>`：循环播放指定 ID
- `<id>`：等价于 `loop <id>`
- `<url|BV>`：下载并直接播放

环境变量/设置：
- `MUSIC_PLAYER`：播放器命令（默认 `mpv`）
- `musicDirectory`：音乐目录设置（默认 `/Users/cr/scripts/music`）
- `musicPlayer`：播放器设置

## 6) GitHub Actions 自动化

> 以下文件在仓库根目录（不是 `Commander/` 子目录）：
> - `.github/workflows/ci.yml`
> - `.github/workflows/release.yml`

### `ci.yml`（CI Gate）

触发：
- `pull_request`
- `push` 到 `main`

执行内容：
- 安装 Python + uv
- 缓存 SwiftPM 依赖
- 运行 `Commander/scripts/release_gate.sh`

### `release.yml`（Build And Release）

触发：
- push tag `v*`（例如 `v0.3.0`）
- 手动 `workflow_dispatch`

执行内容：
- 先跑 gate
- 构建 Release 版本 App
- 打包 zip + 生成 sha256
- 上传 artifact
- 当 tag 为 `v*` 时自动发布 GitHub Release

## 推荐流程

### 日常开发

```bash
./build_run.sh
```

### 提交并推送后，确认构建的是已推送版本

```bash
./scripts/build_after_push.sh --release --no-open
```

### 发版前本地门禁

```bash
bash scripts/release_gate.sh
```

### 正式发版

```bash
./scripts/release_publish.sh --tag v0.3.0
```
