#!/usr/bin/env bash
#
# register-email-service.sh — 将已部署的 CF Email Worker 注册到 codex-register
#
# 用法:
#   ./scripts/register-email-service.sh \
#     --domain example.com \
#     --short-name example \
#     --worker-url "https://temp-email-example.xxx.workers.dev" \
#     --admin-password "MySecurePass123" \
#     --priority 0
#
# 前置条件:
#   1. Worker 已部署且 Email Routing 已配置
#   2. codex-register VM 正在运行
#

set -euo pipefail

# ============================================================
# 参数
# ============================================================
DOMAIN=""
SHORT_NAME=""
WORKER_URL=""
ADMIN_PASSWORD=""
PRIORITY="0"
VM_NAME="codex-register"
VM_ZONE="us-west1-b"
ENABLE_PREFIX="true"
LOCAL_MODE=""

usage() {
    cat <<'EOF'
用法: register-email-service.sh [选项]

必需参数:
  --domain          域名 (例: example.com)
  --short-name      域名简称 (例: example)
  --worker-url      Worker 完整 URL (例: https://temp-email-example.xxx.workers.dev)
  --admin-password  Admin API 密码

可选参数:
  --priority        优先级，0 最高 (默认: 0)
  --vm-name         GCP VM 实例名 (默认: codex-register)
  --vm-zone         GCP VM 区域 (默认: us-west1-b)
  --local           直接调用 localhost (在 VM 内执行时使用)
  -h, --help        显示帮助

示例:
  # 从本地 Mac 通过 SSH 执行
  ./scripts/register-email-service.sh \
    --domain mysite.com \
    --short-name mysite \
    --worker-url "https://temp-email-mysite.xxx.workers.dev" \
    --admin-password "SuperSecret123" \
    --priority 0

  # 在 VM 内直接执行
  ./scripts/register-email-service.sh \
    --domain mysite.com \
    --short-name mysite \
    --worker-url "https://temp-email-mysite.xxx.workers.dev" \
    --admin-password "SuperSecret123" \
    --priority 0 \
    --local
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain)         DOMAIN="$2";         shift 2 ;;
        --short-name)     SHORT_NAME="$2";     shift 2 ;;
        --worker-url)     WORKER_URL="$2";     shift 2 ;;
        --admin-password) ADMIN_PASSWORD="$2"; shift 2 ;;
        --priority)       PRIORITY="$2";       shift 2 ;;
        --vm-name)        VM_NAME="$2";        shift 2 ;;
        --vm-zone)        VM_ZONE="$2";        shift 2 ;;
        --local)          LOCAL_MODE="true";   shift ;;
        -h|--help)        usage ;;
        *)                echo "未知参数: $1"; usage ;;
    esac
done

for var_name in DOMAIN SHORT_NAME WORKER_URL ADMIN_PASSWORD; do
    if [[ -z "${!var_name}" ]]; then
        echo "错误: 缺少参数 --$(echo "$var_name" | tr '_' '-' | tr '[:upper:]' '[:lower:]')"
        exit 1
    fi
done

SERVICE_NAME="自建邮箱-${SHORT_NAME}"

echo "========================================"
echo "注册邮箱服务到 codex-register"
echo "========================================"
echo "服务名:     ${SERVICE_NAME}"
echo "域名:       ${DOMAIN}"
echo "Worker URL: ${WORKER_URL}"
echo "优先级:     ${PRIORITY}"
echo "========================================"
echo ""

# ============================================================
# 构造 API 请求
# ============================================================
API_PAYLOAD=$(cat <<JSON
{
  "service_type": "temp_mail",
  "name": "${SERVICE_NAME}",
  "config": {
    "base_url": "${WORKER_URL}",
    "admin_password": "${ADMIN_PASSWORD}",
    "domain": "${DOMAIN}",
    "enable_prefix": ${ENABLE_PREFIX}
  },
  "enabled": true,
  "priority": ${PRIORITY}
}
JSON
)

API_CMD="curl -s -X POST http://localhost:8000/api/email-services \
  -H 'Content-Type: application/json' \
  -d '$(echo "${API_PAYLOAD}" | tr -d '\n')'"

echo "[1/3] 添加邮箱服务..."

if [[ -n "${LOCAL_MODE}" ]]; then
    # 在 VM 内直接执行
    RESULT=$(eval "${API_CMD}")
else
    # 通过 SSH 执行
    RESULT=$(gcloud compute ssh "${VM_NAME}" --zone="${VM_ZONE}" --command="${API_CMD}")
fi

echo "  API 响应: ${RESULT}"
echo ""

# 提取服务 ID
SERVICE_ID=$(echo "${RESULT}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('id', data.get('service_id', '')))
except:
    print('')
" 2>/dev/null || echo "")

if [[ -z "${SERVICE_ID}" ]]; then
    echo "警告: 无法提取服务 ID，请手动检查"
    echo "跳过连通性测试"
    exit 1
fi

echo "  服务 ID: ${SERVICE_ID}"
echo ""

# ============================================================
# 测试连通性
# ============================================================
echo "[2/3] 测试连通性..."

TEST_CMD="curl -s -X POST http://localhost:8000/api/email-services/${SERVICE_ID}/test"

if [[ -n "${LOCAL_MODE}" ]]; then
    TEST_RESULT=$(eval "${TEST_CMD}")
else
    TEST_RESULT=$(gcloud compute ssh "${VM_NAME}" --zone="${VM_ZONE}" --command="${TEST_CMD}")
fi

echo "  测试结果: ${TEST_RESULT}"
echo ""

# ============================================================
# 验证 Worker 直接可访问
# ============================================================
echo "[3/3] 验证 Worker Admin API..."

HEALTH_RESULT=$(curl -s "${WORKER_URL}/admin/mails?limit=1" \
    -H "x-admin-auth: ${ADMIN_PASSWORD}" \
    -H "Accept: application/json" \
    -w "\nHTTP_STATUS:%{http_code}" 2>/dev/null || echo "连接失败")

echo "  Worker 响应: ${HEALTH_RESULT}"
echo ""

# ============================================================
# 完成
# ============================================================
echo "========================================"
echo "邮箱服务注册完成!"
echo "========================================"
echo ""
echo "服务 ID:    ${SERVICE_ID}"
echo "服务名:     ${SERVICE_NAME}"
echo "域名:       ${DOMAIN}"
echo "Worker URL: ${WORKER_URL}"
echo "优先级:     ${PRIORITY}"
echo ""
echo "下一步: 使用此邮箱服务注册 1 个 OpenAI 账号进行验证"
echo "  Web UI: http://34.187.162.3:8000 → 选择 '${SERVICE_NAME}' → 注册 1 个"
echo "========================================"
