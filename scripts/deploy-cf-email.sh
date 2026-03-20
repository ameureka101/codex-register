#!/usr/bin/env bash
#
# deploy-cf-email.sh — 部署 cloudflare_temp_email Worker（每个域名执行一次）
#
# 用法:
#   ./scripts/deploy-cf-email.sh \
#     --domain example.com \
#     --short-name example \
#     --admin-password "MySecurePass123" \
#     --d1-id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
#
# 前置条件:
#   1. 已安装 Node.js >= 18 和 npm
#   2. 已登录 wrangler（运行 npx wrangler login）
#   3. 域名已托管到 Cloudflare 且状态 Active
#   4. 已在 Cloudflare Dashboard 创建 D1 数据库并获取 database_id
#
# 此脚本做的事:
#   1. 克隆 cloudflare_temp_email（如果本地不存在）
#   2. 生成 wrangler.toml
#   3. 安装依赖
#   4. 部署 Worker
#   5. 初始化 D1 数据库表
#
# 部署后还需手动完成:
#   - Cloudflare Dashboard → 域名 → Email → Email Routing → 启用
#   - Catch-all → Send to Worker → 选择对应 Worker
#

set -euo pipefail

# ============================================================
# 参数解析
# ============================================================
DOMAIN=""
SHORT_NAME=""
ADMIN_PASSWORD=""
D1_ID=""
CLONE_DIR="${HOME}/cloudflare_temp_email"

usage() {
    cat <<'EOF'
用法: deploy-cf-email.sh [选项]

必需参数:
  --domain          域名 (例: example.com)
  --short-name      域名简称，用于 Worker 和 D1 命名 (例: example)
  --admin-password  Admin API 密码
  --d1-id           D1 数据库 ID (从 Cloudflare Dashboard 复制)

可选参数:
  --clone-dir       cloudflare_temp_email 克隆目录 (默认: ~/cloudflare_temp_email)
  -h, --help        显示帮助

示例:
  ./scripts/deploy-cf-email.sh \
    --domain mysite.com \
    --short-name mysite \
    --admin-password "SuperSecret123" \
    --d1-id "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain)       DOMAIN="$2";         shift 2 ;;
        --short-name)   SHORT_NAME="$2";     shift 2 ;;
        --admin-password) ADMIN_PASSWORD="$2"; shift 2 ;;
        --d1-id)        D1_ID="$2";          shift 2 ;;
        --clone-dir)    CLONE_DIR="$2";      shift 2 ;;
        -h|--help)      usage ;;
        *)              echo "未知参数: $1"; usage ;;
    esac
done

# 校验必需参数
for var_name in DOMAIN SHORT_NAME ADMIN_PASSWORD D1_ID; do
    if [[ -z "${!var_name}" ]]; then
        echo "错误: 缺少参数 --$(echo "$var_name" | tr '_' '-' | tr '[:upper:]' '[:lower:]')"
        echo "运行 --help 查看用法"
        exit 1
    fi
done

WORKER_NAME="temp-email-${SHORT_NAME}"
DB_NAME="temp-email-${SHORT_NAME}"

echo "========================================"
echo "部署 cloudflare_temp_email"
echo "========================================"
echo "域名:       ${DOMAIN}"
echo "Worker 名:  ${WORKER_NAME}"
echo "D1 数据库:  ${DB_NAME} (${D1_ID})"
echo "克隆目录:   ${CLONE_DIR}"
echo "========================================"
echo ""

# ============================================================
# Step 1: 克隆项目（如果不存在）
# ============================================================
if [[ ! -d "${CLONE_DIR}" ]]; then
    echo "[1/5] 克隆 cloudflare_temp_email..."
    git clone https://github.com/dreamhunter2333/cloudflare_temp_email.git "${CLONE_DIR}"
else
    echo "[1/5] 项目目录已存在，跳过克隆: ${CLONE_DIR}"
fi

WORKER_DIR="${CLONE_DIR}/worker"
if [[ ! -d "${WORKER_DIR}" ]]; then
    echo "错误: worker 目录不存在: ${WORKER_DIR}"
    exit 1
fi

# ============================================================
# Step 2: 生成 wrangler.toml
# ============================================================
echo "[2/5] 生成 wrangler.toml..."

WRANGLER_FILE="${WORKER_DIR}/wrangler.toml"

# 备份现有 wrangler.toml（如果有）
if [[ -f "${WRANGLER_FILE}" ]]; then
    BACKUP="${WRANGLER_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp "${WRANGLER_FILE}" "${BACKUP}"
    echo "  已备份现有配置到: ${BACKUP}"
fi

cat > "${WRANGLER_FILE}" <<TOML
name = "${WORKER_NAME}"
main = "src/worker.ts"
compatibility_date = "2024-09-23"
compatibility_flags = ["nodejs_compat"]
node_compat = true

[vars]
TITLE = "Temp Email - ${SHORT_NAME}"
PREFIX = ""
# 验证码收信，不需要 RESEND
# RESEND_TOKEN = ""
MIN_ADDRESS_LEN = 1
MAX_ADDRESS_LEN = 30
DEFAULT_DOMAINS = '["${DOMAIN}"]'
DOMAINS = '["${DOMAIN}"]'
ADMIN_PASSWORDS = '["${ADMIN_PASSWORD}"]'
ADMIN_CONTACT = ""
COPYRIGHT = ""
ENABLE_USER_CREATE_EMAIL = true
ENABLE_USER_DELETE_EMAIL = true
ENABLE_AUTO_REPLY = false
ENABLE_WEBHOOK = false

[[d1_databases]]
binding = "DB"
database_name = "${DB_NAME}"
database_id = "${D1_ID}"
TOML

echo "  已生成: ${WRANGLER_FILE}"

# ============================================================
# Step 3: 安装依赖
# ============================================================
echo "[3/5] 安装 npm 依赖..."
cd "${WORKER_DIR}"
npm install

# ============================================================
# Step 4: 部署 Worker
# ============================================================
echo "[4/5] 部署 Worker..."
npx wrangler deploy

echo ""
echo "  Worker 已部署!"

# ============================================================
# Step 5: 初始化 D1 数据库
# ============================================================
echo "[5/5] 初始化 D1 数据库..."

DB_DIR="${CLONE_DIR}/db"
if [[ -f "${DB_DIR}/schema.sql" ]]; then
    npx wrangler d1 execute "${DB_NAME}" --file="${DB_DIR}/schema.sql" --remote
    echo "  数据库表已初始化"
else
    echo "  警告: 找不到 schema.sql，请手动初始化数据库"
    echo "  预期路径: ${DB_DIR}/schema.sql"
fi

# ============================================================
# 完成
# ============================================================
echo ""
echo "========================================"
echo "Worker 部署完成!"
echo "========================================"
echo ""
echo "Worker URL: https://${WORKER_NAME}.<your-account>.workers.dev"
echo ""
echo "接下来需要手动完成 2 步:"
echo ""
echo "  1. 配置 Email Routing (Cloudflare Dashboard):"
echo "     → 域名 ${DOMAIN} → Email → Email Routing"
echo "     → 启用 Email Routing"
echo "     → Catch-all 规则 → Send to Worker → 选择 '${WORKER_NAME}'"
echo ""
echo "  2. 验证收件:"
echo "     → 从任意邮箱发邮件到 test@${DOMAIN}"
echo "     → 检查: curl -s 'https://${WORKER_NAME}.<your-account>.workers.dev/admin/mails?limit=5' -H 'x-admin-auth: ${ADMIN_PASSWORD}'"
echo ""
echo "  3. 注册到 codex-register:"
echo "     → 运行 scripts/register-email-service.sh"
echo "========================================"
