# Scripts

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

## `scripts/release_notes.sh`

从上一个可达 tag 到目标 ref 自动生成 Markdown 发版说明。

示例：

```bash
./scripts/release_notes.sh --tag v1.0.3
./scripts/release_notes.sh --tag v1.0.3 --from v1.0.2 --to HEAD --output /tmp/release-notes.md
```

## `scripts/release_publish.sh`

完整发版脚本：

1. 可选执行 `release_gate.sh`
2. 自动生成 release notes
3. push 当前分支
4. 创建带注释的 tag
5. push tag 触发 GitHub Release workflow

示例：

```bash
./scripts/release_publish.sh --tag v1.0.3
```

指定说明文件：

```bash
./scripts/release_publish.sh --tag v1.0.3 --notes-file /tmp/release-notes.md
```

指定说明范围：

```bash
./scripts/release_publish.sh --tag v1.0.3 --notes-from v1.0.2 --notes-to HEAD
```
