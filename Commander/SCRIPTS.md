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

从上一个可达 tag 到目标 ref 生成发版素材上下文，供手工或让 Codex 整理成正式更新日志。

示例：

```bash
./scripts/release_notes.sh --tag v1.0.3
./scripts/release_notes.sh --tag v1.0.3 --from v1.0.2 --to HEAD --output /tmp/release-notes.md
```

## `scripts/release_publish.sh`

完整发版脚本：

1. 可选执行 `release_gate.sh`
2. 校验显式提供的 release notes 文件
3. push 当前分支
4. 创建带注释的 tag
5. push tag 触发 GitHub Release workflow

示例：

```bash
./scripts/release_publish.sh --tag v1.0.3 --notes-file /tmp/release-notes.md
```

推荐流程：

```bash
./scripts/release_notes.sh --tag v1.0.3
# 根据输出整理正式说明，写入 /tmp/release-notes.md
./scripts/release_publish.sh --tag v1.0.3 --notes-file /tmp/release-notes.md
```
