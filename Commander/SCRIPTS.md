# Scripts

## `scripts/build_run.sh`

本地构建并可选启动应用。

“确认当前提交已 push 再构建”的能力已经并入这个脚本，不再需要单独的 `build_after_push.sh`。

示例：

```bash
./scripts/build_run.sh
./scripts/build_run.sh --release --no-open
./scripts/build_run.sh --require-pushed --release --no-open
```

## `scripts/release_gate.sh`

本地发版门禁：

- Debug 构建
- Python `py_compile`
- `help` / `plugins` 冒烟测试

示例：

```bash
bash scripts/release_gate.sh
```

## `scripts/test_and_commit.sh`

先跑门禁，再自动暂存并提交当前改动。

示例：

```bash
./scripts/test_and_commit.sh --message "fix(markdown): support inline block math"
```

可选：

```bash
./scripts/test_and_commit.sh --message "chore: checkpoint" --no-gate
```

## `scripts/release_status.sh`

检查 GitHub Actions 的 `Build And Release` 是否成功，也可以等待直到完成。

示例：

```bash
./scripts/release_status.sh
./scripts/release_status.sh --tag v1.0.3
./scripts/release_status.sh --tag v1.0.3 --wait
```

退出码：

- `0`：成功
- `1`：失败 / 取消 / 未找到
- `2`：还在运行

## `scripts/release_publish.sh`

完整发版脚本：

1. 可选执行 `release_gate.sh`
2. 输出本次范围内的全部 commit 上下文
3. 让你在终端直接输入发版内容，或读取 `--notes-file`
4. push 当前分支
5. 创建带注释的 tag
6. push tag 触发 GitHub Release workflow

示例：

```bash
./scripts/release_publish.sh --tag v1.0.3
./scripts/release_publish.sh --tag v1.0.3 --notes-file /tmp/release-notes.md
```

推荐流程：

```bash
./scripts/release_publish.sh --tag v1.0.3
./scripts/release_status.sh --tag v1.0.3 --wait
```
