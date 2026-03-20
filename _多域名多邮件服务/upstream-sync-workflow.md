# 上游同步工作流（Upstream Sync Workflow）

> 将 cnlimiter/codex-manager 的更新合并到本地，再推送到 ameureka101/codex-register

## 仓库关系

```
上游源（只读）                      本地仓库                         你的 Fork
cnlimiter/codex-manager  ──fetch──▶  ~/Desktop/codex-register  ──push──▶  ameureka101/codex-register
       (upstream)                         (local)                            (origin)
```

## Remote 配置（首次设置，已完成）

```bash
cd ~/Desktop/codex-register
git remote add upstream https://github.com/cnlimiter/codex-manager.git
# origin 已指向 git@github.com:ameureka101/codex-register.git
git remote -v   # 验证
```

## 每次同步操作步骤

### Step 1: 确保本地干净

```bash
cd ~/Desktop/codex-register
git status
# 如果有未提交更改，先 commit 或 stash
git stash  # 可选
```

### Step 2: 拉取上游最新代码

```bash
git fetch upstream
```

### Step 3: 查看上游有哪些新提交

```bash
# 查看上游比本地多了什么
git log master..upstream/master --oneline

# 查看具体改了什么文件
git diff master..upstream/master --stat
```

### Step 4: 合并上游代码

```bash
git merge upstream/master
```

**如果无冲突** → 自动完成（Fast-forward 或 Merge commit）

**如果有冲突** → 手动解决：

```bash
# 查看冲突文件
git diff --name-only --diff-filter=U

# 编辑每个冲突文件，解决冲突标记 (<<<<<<<, =======, >>>>>>>)
# 保留我们的自定义修改（如 temp_mail.py 的 JWT 降级逻辑）

# 解决完毕后
git add <冲突文件>
git commit  # 自动生成 merge commit message
```

### Step 5: 恢复本地修改（如果 Step 1 做了 stash）

```bash
git stash pop
# 如有冲突，同 Step 4 解决
git add .
git commit -m "chore: reapply local changes after upstream merge"
```

### Step 6: 推送到你的 Fork

```bash
git push origin master
```

### Step 7: 同步到 GCP VM（可选）

```bash
# 方式一：SSH 进去 git pull
gcloud compute ssh codex-register --zone=us-west1-b --command='
  cd /opt/codex-register && git pull origin master && sudo systemctl restart codex-register
'

# 方式二：直接重新部署
gcloud compute ssh codex-register --zone=us-west1-b --command='
  cd /opt/codex-register && git fetch origin && git reset --hard origin/master && pip install -e . && sudo systemctl restart codex-register
'
```

## 一键同步脚本

```bash
#!/bin/bash
# 文件: scripts/sync-upstream.sh
# 用法: bash scripts/sync-upstream.sh

set -e
cd "$(git rev-parse --show-toplevel)"

echo "=== Step 1: 检查工作区状态 ==="
if [ -n "$(git status --porcelain)" ]; then
    echo "⚠️  工作区有未提交更改，先 stash"
    git stash save "auto-stash-before-upstream-sync-$(date +%Y%m%d%H%M%S)"
    STASHED=1
else
    STASHED=0
fi

echo "=== Step 2: 拉取上游 ==="
git fetch upstream

echo "=== Step 3: 查看新提交 ==="
NEW_COMMITS=$(git log master..upstream/master --oneline 2>/dev/null | wc -l | tr -d ' ')
echo "上游有 $NEW_COMMITS 个新提交"

if [ "$NEW_COMMITS" -eq 0 ]; then
    echo "✅ 已是最新，无需合并"
    [ "$STASHED" -eq 1 ] && git stash pop
    exit 0
fi

git log master..upstream/master --oneline

echo "=== Step 4: 合并上游 ==="
if ! git merge upstream/master; then
    echo "❌ 合并有冲突，请手动解决后执行:"
    echo "   git add <冲突文件>"
    echo "   git commit"
    echo "   git push origin master"
    exit 1
fi

echo "=== Step 5: 恢复 stash ==="
if [ "$STASHED" -eq 1 ]; then
    if ! git stash pop; then
        echo "⚠️  stash pop 有冲突，请手动解决"
        exit 1
    fi
fi

echo "=== Step 6: 推送到 Fork ==="
git push origin master

echo "✅ 同步完成！本地和 Fork 均已更新"
echo ""
echo "如需同步到 GCP VM，运行:"
echo "  gcloud compute ssh codex-register --zone=us-west1-b --command='cd /opt/codex-register && git pull origin master && sudo systemctl restart codex-register'"
```

## 我们的自定义修改（合并时需注意保留）

| 文件 | 修改内容 | 说明 |
|------|---------|------|
| `src/services/temp_mail.py` | JWT 自动降级到 admin API | 上游注释掉了 JWT 路径，我们做了更优雅的降级处理 |
| `src/core/register.py` | Workspace ID 5 次重试机制 | 解决 OpenAI 服务端竞态条件 |
| `_多域名多邮件服务/` | 部署文档和脚本 | 仅本地存在，上游无此目录，不会冲突 |
| `scripts/deploy-cf-email.sh` | 邮箱部署脚本 | 仅本地存在 |
| `scripts/register-email-service.sh` | 服务注册脚本 | 仅本地存在 |

## 常见问题

**Q: 合并后 temp_mail.py 冲突怎么办？**
A: 保留我们的 JWT 降级逻辑（`use_jwt` 变量 + `try/except EmailServiceError` 降级块），不要用上游的简单注释方案。

**Q: 上游新增了文件怎么办？**
A: 直接接受，不会与我们的修改冲突。

**Q: 推送被拒绝（non-fast-forward）怎么办？**
A: 说明 Fork 上有人直接修改了。先 `git pull origin master` 合并 Fork 的变更，再推送。

## 历史同步记录

| 日期 | 上游版本 | 新提交数 | 冲突 | 备注 |
|------|---------|---------|------|------|
| 2026-03-20 | v1.0.9 (62c983b) | 14 | temp_mail.py (已解决) | 首次合并，含 JWT 降级修复 |
