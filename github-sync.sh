#!/bin/bash
# github-sync.sh
# CNB 开机运行一次即可, 自动完成所有配置
#
# 用法:
#   export GITHUB_TOKEN=ghp_xxxxxxxx
#   bash /workspace/github-sync.sh
#
# 运行后可直接使用:
#   push "更新代码"       -> GitHub (排除敏感文件)
#   push-cnb "更新代码"   -> CNB (包含所有文件)

set -e

GITHUB_TOKEN="${GITHUB_TOKEN:-}"
REPO_NAME="${GITHUB_REPO:-}"
OWNER="${GITHUB_OWNER:-}"
WORKDIR="/workspace"
BRANCH="main"

EXCLUDE_PATTERNS=(
    "backup_jsonl_final/"
    ".codebuddy/"
)

GITIGNORE_MARKER_START="# === github-sync: 以下文件不推送到 GitHub ==="
GITIGNORE_MARKER_END="# === github-sync end ==="

# 从 CNB 环境变量读取仓库名
if [ -z "$REPO_NAME" ]; then
    CNB_SLUG="${CNB_REPO_SLUG:-}"
    if [ -n "$CNB_SLUG" ]; then
        REPO_NAME="${CNB_SLUG#*/}"
    else
        REPO_NAME="mhtml"
    fi
fi

# ============ 检查 token ============
if [ -z "$GITHUB_TOKEN" ]; then
    echo "[ERROR] GITHUB_TOKEN 未设置!"
    echo "请先运行: export GITHUB_TOKEN=ghp_xxxxxxxx"
    exit 1
fi

# ============ 获取 GitHub 用户名 ============
if [ -z "$OWNER" ]; then
    echo "[INFO] 从 token 获取 GitHub 用户名..."
    OWNER=$(curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user | grep '"login"' | head -1 | sed 's/.*"login": *"\([^"]*\)".*/\1/')
fi

if [ -z "$OWNER" ]; then
    echo "[ERROR] 无法获取 GitHub 用户名, 请设置 GITHUB_OWNER"
    exit 1
fi

echo "[INFO] GitHub 用户: $OWNER"
echo "[INFO] 目标仓库: $OWNER/$REPO_NAME"

# ============ 检查/创建 GitHub 仓库 ============
echo "[INFO] 检查 GitHub 仓库..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$OWNER/$REPO_NAME")

if [ "$HTTP_CODE" = "200" ]; then
    echo "[OK] 仓库 $OWNER/$REPO_NAME 已存在"
elif [ "$HTTP_CODE" = "404" ]; then
    echo "[INFO] 创建公开仓库 $OWNER/$REPO_NAME ..."
    RESPONSE=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
        https://api.github.com/user/repos \
        -d "{\"name\":\"$REPO_NAME\",\"visibility\":\"public\",\"auto_init\":false}")
    NEW_URL=$(echo "$RESPONSE" | grep '"html_url"' | head -1 | sed 's/.*"html_url": *"\([^"]*\)".*/\1/')
    if [ -n "$NEW_URL" ]; then
        echo "[OK] 仓库创建成功: $NEW_URL"
    else
        echo "[ERROR] 创建仓库失败:"
        echo "$RESPONSE"
        exit 1
    fi
else
    echo "[ERROR] 检查仓库失败, HTTP: $HTTP_CODE"
    exit 1
fi

# ============ 配置 git remote ============
cd "$WORKDIR"
GITHUB_URL="https://${GITHUB_TOKEN}@github.com/${OWNER}/${REPO_NAME}.git"

# 先保存当前 origin 的 URL (CNB), 再改 origin
CNB_URL="https://cnb.cool/${CNB_REPO_SLUG}.git"

if git remote | grep -q '^cnb$'; then
    git remote set-url cnb "$CNB_URL"
else
    git remote add cnb "$CNB_URL"
fi

git remote set-url origin "$GITHUB_URL"
echo "[OK] origin -> GitHub ($GITHUB_URL)"
echo "[OK] cnb    -> CNB ($CNB_URL)"

# ============ 配置 .gitignore ============
GITIGNORE="$WORKDIR/.gitignore"
[ ! -f "$GITIGNORE" ] && touch "$GITIGNORE"
if ! grep -qF "$GITIGNORE_MARKER_START" "$GITIGNORE" 2>/dev/null; then
    {
        echo ""
        echo "$GITIGNORE_MARKER_START"
        for pattern in "${EXCLUDE_PATTERNS[@]}"; do echo "$pattern"; done
        echo "$GITIGNORE_MARKER_END"
    } >> "$GITIGNORE"
    echo "[OK] .gitignore 已配置"
fi

# ============ 配置 git 用户 ============
GIT_USERNAME="${CNB_BUILD_USER_NICKNAME:-$OWNER}"
GIT_EMAIL="${GITHUB_EMAIL:-${OWNER}@users.noreply.github.com}"
git config user.name "$GIT_USERNAME"
git config user.email "$GIT_EMAIL"

# ============ 备份对话记录 ============
CODEBUDDY_DIR="$HOME/.codebuddy/projects/workspace"
BACKUP_DIR="$WORKDIR/backup_jsonl_final"
if [ -d "$CODEBUDDY_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    cp -r "$CODEBUDDY_DIR"/* "$BACKUP_DIR/" 2>/dev/null || true
fi

# ============ 拉取 GitHub 最新内容 ============
echo "[INFO] 同步 GitHub 最新内容..."
git fetch origin 2>&1 || true
HAS_REMOTE_MAIN=$(git branch -r 2>/dev/null | grep 'origin/main' || true)
if [ -n "$HAS_REMOTE_MAIN" ]; then
    git merge origin/main --allow-unrelated-histories --no-edit 2>/dev/null && \
        echo "[OK] 已合并" || echo "[WARN] 可能有冲突, 请手动检查"
else
    echo "[INFO] GitHub 仓库为空"
fi

# ============ 安装快捷命令 ============
cat > /usr/local/bin/push << 'EOF'
#!/bin/bash
cd /workspace
MSG="${1:-更新代码}"
git add .
git -c commit.gpgsign=false commit -m "$MSG" || true
git push origin main
echo "[OK] 已推送到 GitHub"
EOF

cat > /usr/local/bin/push-cnb << 'EOF'
#!/bin/bash
cd /workspace
MSG="${1:-更新代码}"

# 记录 push-cnb 前的 commit 数, 用于后续回退
COMMIT_BEFORE=$(git rev-parse HEAD)

# 备份对话记录
CODEBUDDY_DIR="$HOME/.codebuddy/projects/workspace"
BACKUP_DIR="/workspace/backup_jsonl_final"
if [ -d "$CODEBUDDY_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    cp -r "$CODEBUDDY_DIR"/* "$BACKUP_DIR/" 2>/dev/null || true
fi

# 1. 临时移除 .gitignore 排除规则
GITIGNORE="/workspace/.gitignore"
MARKER_START="# === github-sync: 以下文件不推送到 GitHub ==="
MARKER_END="# === github-sync end ==="
[ -f "$GITIGNORE" ] && grep -qF "$MARKER_START" "$GITIGNORE" && \
    sed -i "/$MARKER_START/,/$MARKER_END/d" "$GITIGNORE"

# 2. add 所有文件 (含敏感文件)
git add .
git diff --cached --quiet 2>/dev/null || git -c commit.gpgsign=false commit -m "$MSG" || true

# 3. 推送到 CNB
git push cnb main
echo "[OK] 已推送到 CNB (含所有文件)"

# 4. 回退本地 commit 到 push-cnb 之前 (敏感文件从历史中彻底移除)
git reset --soft "$COMMIT_BEFORE" 2>/dev/null || true

# 5. 恢复 .gitignore 排除规则
{
    echo ""
    echo "$MARKER_START"
    echo "backup_jsonl_final/"
    echo ".codebuddy/"
    echo "$MARKER_END"
} >> "$GITIGNORE"

# 6. 用 .gitignore 生效后重新 add (排除的文件不会进入暂存区)
git reset HEAD -- backup_jsonl_final/ .codebuddy/ 2>/dev/null || true
git add .

echo "[OK] .gitignore 已恢复, 敏感文件已从 git 历史移除"
echo "[OK] 后续 push 不会包含敏感文件"
EOF

chmod +x /usr/local/bin/push /usr/local/bin/push-cnb

echo ""
echo "========================================="
echo "  完成! 直接使用:"
echo ""
echo "    push \"更新代码\"       -> GitHub (排除敏感文件)"
echo "    push-cnb \"更新代码\"   -> CNB (包含所有文件)"
echo "========================================="
