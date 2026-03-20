#!/bin/bash
# 上游同步脚本：cnlimiter/codex-manager → local → ameureka101/codex-register
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

echo ""
echo "✅ 同步完成！本地和 Fork 均已更新"
echo ""
echo "如需同步到 GCP VM，运行:"
echo "  gcloud compute ssh codex-register --zone=us-west1-b --command='cd /opt/codex-register && git pull origin master && sudo systemctl restart codex-register'"
