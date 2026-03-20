# Cloudflare 自建邮箱部署实战手册

> 基于 ppthub.shop 实际部署经验整理（2026-03-20）
> 可直接照搬用于任意新域名 + 任意 Cloudflare 账号

---

## 一、准备阶段：需要哪些密钥

### 1.1 需要两种不同的 Cloudflare 凭证（这是最大的坑）

**坑：一个 Token 不够用！**

| 操作 | 需要的凭证 | 原因 |
|------|-----------|------|
| 部署 Worker | API Token (`cfut_` 开头) | Workers API |
| 创建 D1 数据库 | API Token (`cfut_` 开头) | D1 API |
| 配置 Email Routing | **Global API Key + 邮箱** | Email Routing API 不支持受限 Token |
| 添加 DNS 记录 | **Global API Key + 邮箱** | 同上 |

**如果你只有 API Token，Email Routing 会返回 `Authentication error (10000)`，这不是 Token 内容的问题，而是 Email Routing API 本身的限制。**

---

### 1.2 获取 API Token（用于 Workers + D1）

1. 打开 https://dash.cloudflare.com/profile/api-tokens
2. **Create Token** → 选择 **Edit Cloudflare Workers** 模板
3. 确认权限包含：
   - Account → **Workers Scripts: Edit**
   - Account → **D1: Edit**
4. Account Resources → 选择你的账号
5. **不需要** Zone 权限（Email Routing 用 Global Key 做）
6. Create Token → 复制保存

格式：`cfut_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`

---

### 1.3 获取 Global API Key（用于 Email Routing + DNS）

1. 打开 https://dash.cloudflare.com/profile/api-tokens
2. 滚动到最底部 → **Global API Key** → **View**
3. 输入密码确认 → 复制 Key

格式：`xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`（40 位十六进制）

同时记录你的 **Cloudflare 登录邮箱**（两者配套使用）

---

### 1.4 获取 Account ID

运行以下命令（用 API Token）：
```bash
CLOUDFLARE_API_TOKEN="cfut_你的token" npx wrangler whoami
```
输出中会显示 Account ID（32 位十六进制）。

---

### 1.5 获取 Zone ID

```bash
curl -s "https://api.cloudflare.com/client/v4/zones?name=你的域名.com" \
  -H "X-Auth-Key: 你的GlobalAPIKey" \
  -H "X-Auth-Email: 你的CF登录邮箱" | python3 -c "
import sys,json
d=json.load(sys.stdin)
z=d['result'][0]
print('Zone ID:', z['id'])
print('Status:', z['status'])
"
```

域名必须是 **status: active** 才能继续。

---

## 二、信息清单（每个域名填一份）

```
域名:              _______________
短名称(用于命名):   _______________   # 如 ppthub、mysite
Cloudflare 账号:   _______________
Account ID:        _______________
Zone ID:           _______________
API Token:         cfut____________
Global API Key:    _______________
CF 登录邮箱:       _______________

# 部署后生成：
Worker 名称:       temp-email-_______________
D1 数据库名:       temp-email-_______________
D1 数据库 ID:      _______________
Admin 密码:        _______________   # 自己生成
JWT Secret:        _______________   # 自己生成
Worker URL:        https://gomail._______________
codex-register 服务ID: ___
```

---

## 三、Step-by-Step 部署命令

> ⚠️ 关键提示：每个 Bash 命令都**硬编码**变量，不要跨命令复用 shell 变量。

### Step 1：生成随机密码

```bash
python3 -c "import secrets; print('Admin密码:', secrets.token_urlsafe(16))"
python3 -c "import secrets; print('JWT Secret:', secrets.token_urlsafe(32))"
```

记录这两个值，后续填入 wrangler.toml。

---

### Step 2：创建 D1 数据库

```bash
curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/【ACCOUNT_ID】/d1/database" \
  -H "Authorization: Bearer 【API_TOKEN】" \
  -H "Content-Type: application/json" \
  -d '{"name": "temp-email-【短名称】"}'
```

从返回 JSON 中复制 `uuid` 字段 → 即 D1 数据库 ID。

**坑：** 直接用 shell 变量拼 URL 时，环境变量会在某些工具调用间被清空，导致 URL 变成 `/accounts/d1/database`（ID 消失），返回 `code 7003`。解决方法：直接硬编码。

---

### Step 3：克隆项目

```bash
git clone https://github.com/dreamhunter2333/cloudflare_temp_email.git ~/cloudflare_temp_email
```

---

### Step 4：编写 wrangler.toml

文件位置：`~/cloudflare_temp_email/worker/wrangler.toml`

```toml
name = "temp-email-【短名称】"
main = "src/worker.ts"
compatibility_date = "2025-04-01"
compatibility_flags = ["nodejs_compat"]
keep_vars = true
account_id = "【ACCOUNT_ID】"
routes = [
    { pattern = "gomail.【域名】", custom_domain = true },
]

[vars]
TITLE = "Temp Email"
PREFIX = ""
MIN_ADDRESS_LEN = 1
MAX_ADDRESS_LEN = 30
DEFAULT_DOMAINS = ["【域名】"]
DOMAINS = ["【域名】"]
ADMIN_PASSWORDS = ["【Admin密码】"]
JWT_SECRET = "【JWT_Secret】"
BLACK_LIST = ""
ENABLE_USER_CREATE_EMAIL = true
ENABLE_USER_DELETE_EMAIL = true
ENABLE_AUTO_REPLY = false
ENABLE_WEBHOOK = false

[[d1_databases]]
binding = "DB"
database_name = "temp-email-【短名称】"
database_id = "【D1数据库ID】"
```

**关键配置说明：**
- `account_id` 必须写在 toml 里 —— 否则 wrangler 会调用 `/memberships` API，这个接口需要额外权限，部署会失败报 `Authentication error [code: 10000]`
- `routes` 配置自定义域名后，`workers.dev` 子域名会自动禁用（这是预期行为）
- 不需要配置 RESEND（我们只收邮件，不发邮件）

---

### Step 5：安装依赖

```bash
cd ~/cloudflare_temp_email/worker
pnpm install
```

**坑：** 项目要求 `pnpm`（`package.json` 里有 `packageManager: pnpm@10.10.0`），用 `npm install` 会有警告但通常也能用。建议统一用 `pnpm`：
```bash
which pnpm || npm install -g pnpm
```

---

### Step 6：部署 Worker

```bash
cd ~/cloudflare_temp_email/worker
CLOUDFLARE_API_TOKEN="【API_TOKEN】" npx wrangler deploy
```

成功输出示例：
```
Uploaded temp-email-ppthub (11.49 sec)
Deployed temp-email-ppthub triggers (1.91 sec)
  gomail.ppthub.shop (custom domain)
Current Version ID: xxxx-xxxx-xxxx
```

**坑：** 如果看到 `WARNING: workers_dev will be disabled`，这是正常的，因为我们配置了 custom_domain。

---

### Step 7：初始化 D1 数据库

```bash
cd ~/cloudflare_temp_email/worker
CLOUDFLARE_API_TOKEN="【API_TOKEN】" npx wrangler d1 execute temp-email-【短名称】 \
  --file=../db/schema.sql --remote
```

**坑：** 必须加 `--remote` 参数，否则只初始化本地开发数据库，远程 D1 不会有表。

成功输出：`🌀 Processed 27 queries.` + `"num_tables": 10`

---

### Step 8：添加 DNS 记录（Email Routing 需要）

以下 5 条全部用 **Global API Key + 邮箱** 执行：

```bash
ZONE_ID="【ZONE_ID】"
AUTH_KEY="【Global_API_Key】"
AUTH_EMAIL="【CF_登录邮箱】"

# MX 记录 1
curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "X-Auth-Key: $AUTH_KEY" -H "X-Auth-Email: $AUTH_EMAIL" \
  -H "Content-Type: application/json" \
  -d '{"type":"MX","name":"【域名】","content":"route1.mx.cloudflare.net","priority":91,"ttl":1}'

# MX 记录 2
curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "X-Auth-Key: $AUTH_KEY" -H "X-Auth-Email: $AUTH_EMAIL" \
  -H "Content-Type: application/json" \
  -d '{"type":"MX","name":"【域名】","content":"route2.mx.cloudflare.net","priority":16,"ttl":1}'

# MX 记录 3
curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "X-Auth-Key: $AUTH_KEY" -H "X-Auth-Email: $AUTH_EMAIL" \
  -H "Content-Type: application/json" \
  -d '{"type":"MX","name":"【域名】","content":"route3.mx.cloudflare.net","priority":32,"ttl":1}'

# SPF TXT 记录
curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "X-Auth-Key: $AUTH_KEY" -H "X-Auth-Email: $AUTH_EMAIL" \
  -H "Content-Type: application/json" \
  -d '{"type":"TXT","name":"【域名】","content":"v=spf1 include:_spf.mx.cloudflare.net ~all","ttl":1}'
```

DKIM 记录比较特殊——**每个域名的 DKIM 公钥都不同**，需要先查询再添加：

```bash
# Step A：查询该域名专属的 DKIM 公钥
curl -s "https://api.cloudflare.com/client/v4/zones/【ZONE_ID】/email/routing" \
  -H "X-Auth-Key: 【Global_API_Key】" \
  -H "X-Auth-Email: 【CF_登录邮箱】"
# 在返回的 errors 列表里找 "code":"dkim.missing"，复制其中的 content 值

# Step B：添加 DKIM 记录（content 替换为上面查到的值）
curl -s -X POST "https://api.cloudflare.com/client/v4/zones/【ZONE_ID】/dns_records" \
  -H "X-Auth-Key: 【Global_API_Key】" \
  -H "X-Auth-Email: 【CF_登录邮箱】" \
  -H "Content-Type: application/json" \
  -d '{"type":"TXT","name":"cf2024-1._domainkey.【域名】","content":"【DKIM_内容】","ttl":1}'
```

**坑：** DKIM 的 `p=` 公钥是 Cloudflare 为每个域名单独生成的，不能复制其他域名的！

---

### Step 9：启用 Email Routing

```bash
# 先检查状态（添加 DNS 后应该从 unconfigured → unlocked）
curl -s "https://api.cloudflare.com/client/v4/zones/【ZONE_ID】/email/routing" \
  -H "X-Auth-Key: 【Global_API_Key】" \
  -H "X-Auth-Email: 【CF_登录邮箱】"

# 启用（必须用 POST /enable，不是 PUT enabled:true）
curl -s -X POST "https://api.cloudflare.com/client/v4/zones/【ZONE_ID】/email/routing/enable" \
  -H "X-Auth-Key: 【Global_API_Key】" \
  -H "X-Auth-Email: 【CF_登录邮箱】" \
  -H "Content-Type: application/json"
```

成功后返回：`"enabled": true, "status": "ready"`

**坑：** 用 `PUT {"enabled":true}` 不会报错但实际上不生效（`enabled` 仍是 false）。
必须用 `POST /enable` 这个专用端点。

Email Routing 状态流转：
```
unconfigured → (添加 MX/SPF/DKIM 后) → unlocked → (POST /enable) → ready ✅
```

---

### Step 10：配置 Catch-all 规则

```bash
# 先查询现有的 catch-all 规则 ID
curl -s "https://api.cloudflare.com/client/v4/zones/【ZONE_ID】/email/routing/rules" \
  -H "X-Auth-Key: 【Global_API_Key】" \
  -H "X-Auth-Email: 【CF_登录邮箱】"
# 找到 type: "all" 的那条规则

# 更新 catch-all 规则（必须用 /rules/catch_all 端点，不能用规则 ID）
curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/【ZONE_ID】/email/routing/rules/catch_all" \
  -H "X-Auth-Key: 【Global_API_Key】" \
  -H "X-Auth-Email: 【CF_登录邮箱】" \
  -H "Content-Type: application/json" \
  -d '{
    "matchers": [{"type": "all"}],
    "actions": [{"type": "worker", "value": ["temp-email-【短名称】"]}],
    "enabled": true,
    "name": "Catch-all to temp-email-【短名称】"
  }'
```

成功后返回：`"enabled": true, "actions": [{"type": "worker", ...}]`

**坑：** 用规则 ID（如 `/rules/c93298e6...`）执行 PUT 会报 `Invalid rule operation (2020)`。
Catch-all 规则必须通过 `/rules/catch_all` 这个固定路径修改。

---

### Step 11：注册到 codex-register

在 GCP VM 上执行：
```bash
gcloud compute ssh codex-register --zone=us-west1-b --command='
curl -s -X POST http://localhost:8000/api/email-services \
  -H "Content-Type: application/json" \
  -d "{
    \"service_type\": \"temp_mail\",
    \"name\": \"自建邮箱-【短名称】\",
    \"config\": {
      \"base_url\": \"https://gomail.【域名】\",
      \"admin_password\": \"【Admin密码】\",
      \"domain\": \"【域名】\",
      \"enable_prefix\": true
    },
    \"enabled\": true,
    \"priority\": 【0-5，按顺序递增】
  }"
'
```

记录返回的 `id` 字段，然后测试：
```bash
gcloud compute ssh codex-register --zone=us-west1-b --command='
curl -s -X POST http://localhost:8000/api/email-services/【服务ID】/test
'
# 期望返回: {"success":true,"message":"服务连接正常"}
```

---

### Step 12：端到端验证

从 GCP VM 发请求（不要从本地 Mac 测 workers 域名，本地 LibreSSL 太旧会 TLS 报错）：

```bash
gcloud compute ssh codex-register --zone=us-west1-b --command='
# 健康检查
curl -s "https://gomail.【域名】/admin/mails?limit=1&offset=0" \
  -H "x-admin-auth: 【Admin密码】"
# 期望: {"results":[],"count":0}

# 创建测试邮箱
curl -s -X POST "https://gomail.【域名】/admin/new_address" \
  -H "x-admin-auth: 【Admin密码】" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"test001\",\"domain\":\"【域名】\",\"enablePrefix\":true}"
# 期望: {"address":"test001@【域名】","jwt":"eyJ..."}
'
```

---

## 四、已知坑点汇总

| # | 坑 | 现象 | 解决方法 |
|---|---|------|---------|
| 1 | API Token 无法操作 Email Routing | `Authentication error (10000)` | 换用 Global API Key + 邮箱 |
| 2 | Shell 变量跨命令消失 | URL 变成 `/accounts/d1/database`，报 `code 7003` | 每条命令硬编码所有值 |
| 3 | wrangler 缺少 `account_id` | `Authentication error [code: 10000] /memberships` | 在 wrangler.toml 里加 `account_id = "xxx"` |
| 4 | `PUT enabled:true` 不生效 | Email Routing 仍是 disabled | 改用 `POST /zones/.../email/routing/enable` |
| 5 | 用规则 ID 更新 catch-all | `Invalid rule operation (2020)` | 改用 `/rules/catch_all` 固定端点 |
| 6 | D1 初始化缺 `--remote` | 表创建在本地，生产数据库空表 | 命令加 `--remote` 参数 |
| 7 | 本地 Mac curl TLS 报错 | `LibreSSL error: tlsv1 alert protocol version` | 改用 GCP VM（或 `node`）验证 |
| 8 | DKIM 公钥每域名不同 | 复制其他域名的 DKIM 导致签名失败 | 先 GET `/email/routing` 查询该域名专属公钥 |
| 9 | pnpm 版本锁定 | npm 警告或安装失败 | `npm install -g pnpm` 后用 pnpm |
| 10 | workers.dev 被禁用警告 | wrangler 输出 WARNING | 正常，加了 custom_domain 后 workers.dev 自动禁用 |
| 11 | **验证码获取超时（最致命的坑）** | 注册走到第10步"等待验证码"后 120 秒超时，但 Worker 里其实已收到邮件 | **必须修复代码**，见下方详细说明 |
| 12 | **Workspace ID 间歇性获取失败** | Step 13 `授权 Cookie 里没有 workspace 信息`，间歇性出现 | **必须修复代码**，加重试机制，见下方详细说明 |

### 坑 #11 详解：JWT 无 exp 字段导致验证码获取永久失败

**现象**：
- 注册流程 Step 1-9 全部成功（邮箱创建、表单提交、OTP 发送）
- Step 10 "等待验证码" 120 秒后超时
- 手动查 Worker Admin API 发现邮件其实已收到，验证码就在 Subject 里

**根因**：
`src/services/temp_mail.py` 的 `get_verification_code()` 方法有一段逻辑：
```python
# 优先使用用户级 JWT，回退到 admin API
cached = self._email_cache.get(email, {})
jwt = cached.get("jwt")
if jwt:
    response = self._make_request("GET", "/user_api/mails", ...)
```

问题在于：
1. `create_email()` 通过 admin API (`POST /admin/new_address`) 创建地址，返回的 JWT **没有 `exp` 字段**
2. JWT payload 只有 `{"address": "xxx@domain.com", "address_id": 5}`，无 `exp`
3. Worker 的 `/user_api/*` 中间件验证 JWT 时，检查 `if (!payload.exp)` → 直接返回 **401 "Your token has expired"**
4. 代码中 `_make_request` 收到 401 抛出 `EmailServiceError`
5. 外层 `except` 吞掉异常，`sleep(3)` 后重试 → 每次都 401 → 循环到 120 秒超时

**修复**（已应用到 `src/services/temp_mail.py`）：

```python
# 修复前：
if jwt:
    response = self._make_request("GET", "/user_api/mails", ...)
else:
    response = self._make_request("GET", "/admin/mails", ...)

# 修复后：
use_jwt = bool(jwt)
while time.time() - start_time < timeout:
    try:
        if use_jwt:
            try:
                response = self._make_request("GET", "/user_api/mails", ...)
            except EmailServiceError as jwt_err:
                # JWT 无 exp 或已过期 → 降级到 admin API，不再重试 JWT
                logger.info(f"JWT 请求失败 ({jwt_err})，降级到 admin API")
                use_jwt = False
                response = self._make_request("GET", "/admin/mails", ...)
        else:
            response = self._make_request("GET", "/admin/mails", ...)
```

关键改动：
- `use_jwt` 变量代替直接用 `jwt`（可变状态）
- JWT 失败时 **一次降级、永久走 admin API**，不会反复尝试
- 降级后在同一次循环内立即用 admin API 查询，不浪费 3 秒

**修复后效果**：验证码 4 秒内获取成功（之前 120 秒超时）

**部署修复到 VM**：
```bash
# 从本地复制修复后的文件到 VM
gcloud compute scp src/services/temp_mail.py codex-register:~/codex-register/src/services/temp_mail.py --zone=us-west1-b

# 重启服务
gcloud compute ssh codex-register --zone=us-west1-b --command='
sudo systemctl restart codex-register
'
```

> ⚠️ **这个修复是必须的！** 不修复的话，自建邮箱的验证码获取永远会超时。
> 修复文件：`src/services/temp_mail.py`，`get_verification_code()` 方法。

### 坑 #12 详解：Workspace ID 获取间歇性失败

**现象**：
- 注册流程 Step 1-12 全部成功（邮箱、表单、验证码、创建账户）
- Step 13 "获取 Workspace ID" 失败：`授权 Cookie 里没有 workspace 信息`
- **间歇性**：同一套代码有时成功有时失败

**根因**：
OpenAI 服务端竞态——`create_account` 返回 200 后，`oai-client-auth-session` cookie 里的 `workspaces` 数组有时还没被填充。

**修复**（已应用到 `src/core/register.py`）：

```python
# 修复前：只读一次 cookie，没有 workspace 就直接失败
auth_cookie = self.session.cookies.get("oai-client-auth-session")
workspaces = auth_json.get("workspaces") or []
if not workspaces:
    self._log("授权 Cookie 里没有 workspace 信息", "error")
    return None

# 修复后：最多重试 5 次，每次间隔 2 秒，重试时刷新 cookie
max_retries = 5
retry_delay = 2
for attempt in range(max_retries):
    if attempt > 0:
        time.sleep(retry_delay)
        self.session.get("https://auth.openai.com/about-you", ...)  # 刷新 cookie
    # 遍历 JWT 所有 segments 寻找 workspaces
    for seg in auth_cookie.split("."):
        seg_json = decode(seg)
        workspaces = seg_json.get("workspaces") or []
        if workspaces:
            return workspaces[0]["id"]
```

**部署修复到 VM**：
```bash
gcloud compute scp src/core/register.py codex-register:~/codex-register/src/core/register.py --zone=us-west1-b
gcloud compute ssh codex-register --zone=us-west1-b --command='sudo systemctl restart codex-register'
```

> ⚠️ 此修复提高成功率但无法保证 100%（OpenAI 服务端行为不可控）。极少数情况下仍可能失败，重新提交任务即可。

---

## 五、已部署实例参考

### ppthub.shop（2026-03-20）

| 项目 | 值 |
|------|-----|
| Cloudflare 账号邮箱 | ameureka@webmail.spobcollege.edu |
| Account ID | e08ccf48bda30edaeb5b89a399bb41cf |
| Zone ID | a3132bfec0c821e9aa59309f06928369 |
| Worker 名称 | temp-email-ppthub |
| D1 数据库 ID | e8f8bf56-3f61-4d39-824b-65664a59dc1b |
| 自定义域名 | gomail.ppthub.shop |
| Admin 密码 | _lRwMnoL3vO6_INfMPZVFQ |
| JWT Secret | UYqk1ECrqSSVp99CkBt8X2f_SrsqKesLxkgQiu5v9Wk |
| codex-register 服务 ID | 2 |
| 优先级 | 0 |
| wrangler.toml 路径 | ~/cloudflare_temp_email/worker/wrangler.toml |
| **注册测试** | ✅ 成功 — `nldqm73z@ppthub.shop`，13 秒完成全流程，验证码 4 秒到达 |

---

## 六、下一个域名快速部署脚本

将以下信息填好后一次性运行：

```bash
#!/usr/bin/env bash
# ============ 修改这里 ============
DOMAIN="新域名.com"
SHORT="新域名简称"
ZONE_ID="新Zone_ID"
ACCOUNT_ID="新Account_ID"
API_TOKEN="cfut_新API_Token"
GLOBAL_KEY="新Global_API_Key"
CF_EMAIL="新CF登录邮箱"
PRIORITY=1                        # 0已用于ppthub，这里填1
ADMIN_PASS=$(python3 -c "import secrets; print(secrets.token_urlsafe(16))")
JWT_SEC=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
# ===================================

echo "Admin 密码: $ADMIN_PASS"
echo "JWT Secret: $JWT_SEC"
echo "请保存以上两个值！"
echo ""

# 1. 创建 D1
echo "[1/8] 创建 D1 数据库..."
D1_RESULT=$(curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/d1/database" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"temp-email-${SHORT}\"}")
D1_ID=$(echo "$D1_RESULT" | python3 -c "import sys,json;print(json.load(sys.stdin)['result']['uuid'])")
echo "D1 ID: $D1_ID"

# 2. 写 wrangler.toml
echo "[2/8] 生成 wrangler.toml..."
cat > ~/cloudflare_temp_email/worker/wrangler.toml <<TOML
name = "temp-email-${SHORT}"
main = "src/worker.ts"
compatibility_date = "2025-04-01"
compatibility_flags = ["nodejs_compat"]
keep_vars = true
account_id = "${ACCOUNT_ID}"
routes = [
    { pattern = "gomail.${DOMAIN}", custom_domain = true },
]

[vars]
TITLE = "Temp Email"
PREFIX = ""
MIN_ADDRESS_LEN = 1
MAX_ADDRESS_LEN = 30
DEFAULT_DOMAINS = ["${DOMAIN}"]
DOMAINS = ["${DOMAIN}"]
ADMIN_PASSWORDS = ["${ADMIN_PASS}"]
JWT_SECRET = "${JWT_SEC}"
BLACK_LIST = ""
ENABLE_USER_CREATE_EMAIL = true
ENABLE_USER_DELETE_EMAIL = true
ENABLE_AUTO_REPLY = false
ENABLE_WEBHOOK = false

[[d1_databases]]
binding = "DB"
database_name = "temp-email-${SHORT}"
database_id = "${D1_ID}"
TOML

# 3. 部署 Worker
echo "[3/8] 部署 Worker..."
cd ~/cloudflare_temp_email/worker
CLOUDFLARE_API_TOKEN="$API_TOKEN" npx wrangler deploy

# 4. 初始化 DB
echo "[4/8] 初始化数据库..."
CLOUDFLARE_API_TOKEN="$API_TOKEN" npx wrangler d1 execute "temp-email-${SHORT}" \
  --file=../db/schema.sql --remote

# 5. 查询 DKIM
echo "[5/8] 查询 DKIM 公钥..."
DKIM_CONTENT=$(curl -s "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/email/routing" \
  -H "X-Auth-Key: ${GLOBAL_KEY}" -H "X-Auth-Email: ${CF_EMAIL}" | \
  python3 -c "
import sys,json
d=json.load(sys.stdin)
for e in d['result'].get('errors',[]):
    if e.get('code')=='dkim.missing':
        print(e['missing']['content'])
")
echo "DKIM: $DKIM_CONTENT"

# 6. 添加 DNS 记录
echo "[6/8] 添加 DNS 记录..."
for record in \
  "{\"type\":\"MX\",\"name\":\"${DOMAIN}\",\"content\":\"route1.mx.cloudflare.net\",\"priority\":91,\"ttl\":1}" \
  "{\"type\":\"MX\",\"name\":\"${DOMAIN}\",\"content\":\"route2.mx.cloudflare.net\",\"priority\":16,\"ttl\":1}" \
  "{\"type\":\"MX\",\"name\":\"${DOMAIN}\",\"content\":\"route3.mx.cloudflare.net\",\"priority\":32,\"ttl\":1}" \
  "{\"type\":\"TXT\",\"name\":\"${DOMAIN}\",\"content\":\"v=spf1 include:_spf.mx.cloudflare.net ~all\",\"ttl\":1}"; do
  curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
    -H "X-Auth-Key: ${GLOBAL_KEY}" -H "X-Auth-Email: ${CF_EMAIL}" \
    -H "Content-Type: application/json" -d "$record" | \
    python3 -c "import sys,json;d=json.load(sys.stdin);print('  DNS:', d.get('success'), d.get('errors',''))"
done
# DKIM
curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
  -H "X-Auth-Key: ${GLOBAL_KEY}" -H "X-Auth-Email: ${CF_EMAIL}" \
  -H "Content-Type: application/json" \
  -d "{\"type\":\"TXT\",\"name\":\"cf2024-1._domainkey.${DOMAIN}\",\"content\":${DKIM_CONTENT},\"ttl\":1}" | \
  python3 -c "import sys,json;d=json.load(sys.stdin);print('  DKIM:', d.get('success'), d.get('errors',''))"

# 7. 启用 Email Routing + Catch-all
echo "[7/8] 启用 Email Routing..."
curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/email/routing/enable" \
  -H "X-Auth-Key: ${GLOBAL_KEY}" -H "X-Auth-Email: ${CF_EMAIL}" \
  -H "Content-Type: application/json" | \
  python3 -c "import sys,json;d=json.load(sys.stdin);print('  Enable:', d.get('success'), d['result'].get('status',''))"

curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/email/routing/rules/catch_all" \
  -H "X-Auth-Key: ${GLOBAL_KEY}" -H "X-Auth-Email: ${CF_EMAIL}" \
  -H "Content-Type: application/json" \
  -d "{\"matchers\":[{\"type\":\"all\"}],\"actions\":[{\"type\":\"worker\",\"value\":[\"temp-email-${SHORT}\"]}],\"enabled\":true,\"name\":\"Catch-all\"}" | \
  python3 -c "import sys,json;d=json.load(sys.stdin);print('  Catch-all:', d.get('success'))"

# 8. 注册到 codex-register
echo "[8/8] 注册到 codex-register..."
SVC_RESULT=$(gcloud compute ssh codex-register --zone=us-west1-b --command="
curl -s -X POST http://localhost:8000/api/email-services \
  -H 'Content-Type: application/json' \
  -d '{
    \"service_type\": \"temp_mail\",
    \"name\": \"自建邮箱-${SHORT}\",
    \"config\": {
      \"base_url\": \"https://gomail.${DOMAIN}\",
      \"admin_password\": \"${ADMIN_PASS}\",
      \"domain\": \"${DOMAIN}\",
      \"enable_prefix\": true
    },
    \"enabled\": true,
    \"priority\": ${PRIORITY}
  }'
")
SVC_ID=$(echo "$SVC_RESULT" | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")
echo "服务 ID: $SVC_ID"

# 测试
gcloud compute ssh codex-register --zone=us-west1-b --command="
curl -s -X POST http://localhost:8000/api/email-services/${SVC_ID}/test
"

echo ""
echo "========================================"
echo "✅ 部署完成！"
echo "域名:      gomail.${DOMAIN}"
echo "Admin密码: ${ADMIN_PASS}"
echo "服务 ID:   ${SVC_ID}"
echo "========================================"
```

使用方式：
```bash
# 填好顶部变量后执行
chmod +x 上面的脚本.sh && ./上面的脚本.sh
```

---

## 七、验证清单

每个域名完成后逐项打勾：

- [ ] `curl /admin/mails` 返回 `{"results":[],"count":0}`
- [ ] `POST /admin/new_address` 返回包含 `address` 和 `jwt` 的 JSON
- [ ] codex-register `/test` 返回 `{"success":true}`
- [ ] 从任意邮箱发邮件到 `test@域名`，几秒后能在 Admin API 查到
- [ ] 用此服务注册 1 个 OpenAI 账号，验证码在 120 秒内收到
