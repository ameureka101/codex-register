# Codex-Register 系统运营手册

> 更新时间：2026-03-20
> 系统版本：v2.0.0
> 部署位置：Google Cloud VM (us-west1-b)
> Web UI：http://34.187.162.3:8000

---

## 一、系统架构总览

```
┌─────────────────────────────────────────────────────────────────────┐
│                        整体工作流                                    │
│                                                                     │
│  邮箱服务                codex-register            Sub2API            │
│  (临时/自建邮箱)         (注册系统)               (账号池/API网关)     │
│                                                                     │
│  ┌──────────┐     ┌──────────────────┐     ┌──────────────────┐    │
│  │ 自动创建  │────→│ 16 步全自动注册   │────→│ 集中管理账号      │    │
│  │ 临时邮箱  │     │ OpenAI 账号       │     │ 统一 API 对外服务  │    │
│  │ 接收验证码│←───│ 获取 access_token │     │ 负载均衡/轮转     │    │
│  └──────────┘     └──────────────────┘     └──────────────────┘    │
│       ↑                    ↑                        ↑               │
│       │                    │                        │               │
│  方案A: Tempmail.lol     GCP VM 美国IP直连       手动导出 JSON       │
│  (公共,有封禁风险)       无需代理                 导入 Sub2API       │
│  方案B: 自建CF Worker                                               │
│  (私有域名×6,推荐)                                                  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 二、Tempmail.lol 临时邮箱工作原理

### 2.1 什么是 Tempmail.lol

Tempmail.lol 是一个 **免费临时邮箱 API 服务**，核心特点：
- **零配置** — 不需要注册账号、不需要提供域名、不需要 API Key
- **一键创建** — 调用 API 即自动分配一个随机临时邮箱地址
- **自动接收** — 通过 token 轮询收件箱获取邮件
- **有效期约 10 分钟** — 足够完成 OpenAI 注册验证

### 2.2 工作流程

```
Step 1: 创建邮箱
────────────────────────────────────────────
POST https://api.tempmail.lol/v2/inbox/create
请求体: {}（空 JSON）

返回:
{
  "address": "abc123@tempmail.lol",     ← 邮箱地址
  "token": "eyJhbG...",                 ← 访问凭证（查收件箱用）
  "expires_in": 600000                  ← 有效期（毫秒，约 10 分钟）
}

Step 2: 查询收件箱（轮询）
────────────────────────────────────────────
GET https://api.tempmail.lol/v2/inbox?token={token}

返回:
{
  "emails": [
    {
      "from": "noreply@openai.com",
      "subject": "Verify your email address",
      "body": "Your verification code is 123456",
      "date": 1726482547000
    }
  ]
}

Step 3: 系统用正则提取 6 位验证码
────────────────────────────────────────────
正则: (?<!\d)(\d{6})(?!\d)
匹配 OpenAI 邮件中的 6 位数字 → "123456"
```

### 2.3 关键参数

| 参数 | 值 |
|------|-----|
| API 基础地址 | `https://api.tempmail.lol/v2` |
| 创建邮箱 | `POST /inbox/create` |
| 查询收件箱 | `GET /inbox?token={token}` |
| 轮询间隔 | 3 秒 |
| 最大等待时间 | 120 秒（40 次轮询） |
| 邮箱有效期 | ~10 分钟 |
| 邮件过滤 | 只处理 sender/body 包含 "openai" 的邮件 |

### 2.4 注意事项

- 邮箱是 **一次性** 的，过期后无法再接收邮件
- 注册完成后的 OpenAI 账号绑定的是临时邮箱，日后如果 OpenAI 要求重新验证邮箱，可能无法通过
- Tempmail.lol 是公共免费服务，高并发注册时可能不稳定
- 大批量注册建议升级为自建邮箱服务（TempMail CF Worker / Freemail）

---

## 三、账号注册流程详解

### 3.1 完整 16 步注册流程

codex-register 系统会自动完成以下全部步骤，**无需人工干预**：

```
Step  1: 🌍 检查 IP 地理位置
         → 确认 VM IP 在美国（GCP us-west1-b 自动满足）
         → 如果是 CN/HK/MO/TW 地区会被拒绝

Step  2: 📧 创建临时邮箱
         → 调用 Tempmail.lol API 创建邮箱
         → 获得 abc123@tempmail.lol + token

Step  3: 🔌 初始化 HTTP 会话
         → 使用 curl_cffi 建立浏览器模拟会话
         → 设置 TLS 指纹伪装

Step  4: 🔐 启动 OAuth 授权
         → 生成 state, code_verifier, code_challenge
         → 构建 OAuth 授权 URL

Step  5: 🎫 获取 Device ID
         → 访问 OAuth 授权页面
         → 从 Cookie 获取 oai-did (设备标识)

Step  6: 🛡️ Sentinel 安全检查
         → 风险控制检查
         → 获取 sentinel token（部分情况可选）

Step  7: 📝 提交注册表单
         → POST 邮箱地址到 OpenAI
         → 判断是新账号还是已存在账号

Step  8: 🔑 设置密码
         → 系统自动生成 12 位随机强密码
         → 包含大小写字母+数字

Step  9: 📮 触发验证码发送
         → 请求 OpenAI 发送 OTP 到临时邮箱
         → 记录发送时间戳

Step 10: 🔍 等待并获取验证码
         → 轮询 Tempmail 收件箱（每 3 秒一次）
         → 找到 OpenAI 邮件 → 提取 6 位验证码
         → 最多等待 120 秒

Step 11: ✅ 验证验证码
         → 提交验证码到 OpenAI
         → 验证通过 → 邮箱确认成功

Step 12: 👤 创建用户账户
         → 提交随机生成的用户信息（姓名、生日）
         → 账户创建成功

Step 13: 🏢 获取 Workspace ID
         → 从 auth Cookie 解析 JWT
         → 提取 workspace_id / organization_id

Step 14: 🎯 选择 Workspace
         → POST 选择 workspace
         → 获取重定向 URL

Step 15: 🔗 跟随重定向链
         → 处理 3xx 重定向
         → 获取最终回调 URL

Step 16: 🎉 完成 OAuth 回调
         → 提取 authorization code
         → 交换获得 access_token + refresh_token
         → 注册完成！✅
```

### 3.2 注册产出物

每次注册成功后，系统存储以下信息到数据库：

| 字段 | 说明 | 示例 |
|------|------|------|
| email | 注册邮箱 | `abc123@tempmail.lol` |
| password | 登录密码 | `O8z98E334zfS` |
| access_token | API 访问令牌 | `eyJhbG...` (JWT) |
| refresh_token | 刷新令牌 | `rt_xxx...` |
| id_token | 身份令牌 | `eyJhbG...` (JWT) |
| client_id | 客户端 ID | `app_EMoamEEZ73f0CkXaXp7hrann` |
| account_id | 账户 ID | `d34c327b-6bec-43c2-...` |
| workspace_id | 工作区 ID | `d34c327b-6bec-43c2-...` |
| status | 账号状态 | `active` |

### 3.3 如何触发注册

**方式 A：Web UI（推荐日常使用）**
1. 浏览器打开 `http://34.187.162.3:8000`
2. 输入密码 `Codex2026!Reg#Secure`
3. 选择邮箱服务 → 填写注册数量 → 开始注册

**方式 B：API 调用**
```bash
# 在 VM 上或通过 SSH
curl -X POST http://localhost:8000/api/register/start \
  -H "Content-Type: application/json" \
  -d '{
    "email_service_id": 1,
    "count": 1
  }'
```

---

## 四、对接 Sub2API 流程

### 4.1 什么是 Sub2API

Sub2API 是一个 **OpenAI 账号池管理平台**：
- 集中管理多个 OpenAI OAuth 账号
- 对外提供统一的 API 接口（兼容 OpenAI API 格式）
- 自动轮转账号、负载均衡
- Token 过期自动暂停

### 4.2 当前配置

| 项目 | 值 |
|------|-----|
| Sub2API 地址 | `https://sub2api.ppthub.shop` |
| Admin API Key | `admin-82e0d2289de27ff69b42321ecf07cfb97f0bd9c1dbfa66d794211ff3af2c936d` |
| 连通性 | ✅ 已验证 |

### 4.3 对接方式：手动导出 + 导入（推荐）

手动导出更可控、更安全，推荐流程：

```
┌────────────────────────────────────────────────────────────────┐
│ Step 1: 在 codex-register 中注册账号                            │
│   → Web UI 点击注册，或 API 触发                                │
│   → 等待注册完成                                                │
└──────────────────────────┬─────────────────────────────────────┘
                           ↓
┌────────────────────────────────────────────────────────────────┐
│ Step 2: 导出 Sub2API 格式 JSON                                  │
│   → Web UI「账号管理」→ 选择账号 → 导出 → Sub2API 格式          │
│   → 或通过 API 调用导出（见下方命令）                            │
│   → 得到 sub2api_tokens_xxx.json 文件                           │
└──────────────────────────┬─────────────────────────────────────┘
                           ↓
┌────────────────────────────────────────────────────────────────┐
│ Step 3: 导入到 Sub2API                                          │
│   → 登录 Sub2API 管理面板                                       │
│   → 上传/粘贴 JSON 数据                                         │
│   → 或通过 API 导入（见下方命令）                                │
└──────────────────────────┬─────────────────────────────────────┘
                           ↓
┌────────────────────────────────────────────────────────────────┐
│ Step 4: 在 Sub2API 中确认账号状态                                │
│   → 检查账号是否显示 active                                     │
│   → 测试 API 调用是否正常                                       │
└────────────────────────────────────────────────────────────────┘
```

### 4.4 导出命令

**方式 A：通过 Web UI（最简单）**
1. 打开 `http://34.187.162.3:8000`
2. 进入「账号管理」页面
3. 勾选要导出的账号（或全选）
4. 点击「导出」→ 选择「Sub2API 格式」
5. 下载 JSON 文件

**方式 B：通过 API 导出全部活跃账号**
```bash
# SSH 到 VM 后执行
curl -s -X POST http://localhost:8000/api/accounts/export/sub2api \
  -H "Content-Type: application/json" \
  -d '{"select_all": true, "status_filter": "active"}' \
  > ~/sub2api_export.json

# 查看导出结果
cat ~/sub2api_export.json | python3 -m json.tool | head -20
```

**方式 C：从本地 Mac 直接获取**
```bash
# 一条命令：SSH 到 VM 执行导出并下载到本地
gcloud compute ssh codex-register --zone=us-west1-b --command='
  curl -s -X POST http://localhost:8000/api/accounts/export/sub2api \
    -H "Content-Type: application/json" \
    -d "{\"select_all\": true, \"status_filter\": \"active\"}"
' > ~/Desktop/sub2api_export.json
```

### 4.5 导出数据格式

```json
{
  "proxies": [],
  "accounts": [
    {
      "name": "eckardt3c9ba1@q4k.moonairse.com",
      "platform": "openai",
      "type": "oauth",
      "credentials": {
        "access_token": "eyJhbG...",
        "refresh_token": "rt_xxx...",
        "chatgpt_account_id": "d34c327b-...",
        "organization_id": "d34c327b-...",
        "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
        "expires_at": 1774856241,
        "expires_in": 863999,
        "model_mapping": {
          "gpt-5.1": "gpt-5.1",
          "gpt-5.1-codex": "gpt-5.1-codex",
          "gpt-5.1-codex-max": "gpt-5.1-codex-max",
          "gpt-5.1-codex-mini": "gpt-5.1-codex-mini",
          "gpt-5.2": "gpt-5.2",
          "gpt-5.2-codex": "gpt-5.2-codex",
          "gpt-5.3": "gpt-5.3",
          "gpt-5.3-codex": "gpt-5.3-codex",
          "gpt-5.4": "gpt-5.4"
        }
      },
      "extra": {},
      "concurrency": 10,
      "priority": 1,
      "rate_multiplier": 1,
      "auto_pause_on_expired": true
    }
  ]
}
```

### 4.6 导入到 Sub2API

**方式 A：通过 Sub2API 管理面板**
1. 打开 `https://sub2api.ppthub.shop`（管理面板）
2. 进入账号管理 → 导入
3. 粘贴或上传导出的 JSON 文件

**方式 B：通过 Sub2API API 导入**
```bash
# 将导出的 JSON 包装后上传
EXPORT_DATA=$(cat ~/sub2api_export.json)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

curl -X POST https://sub2api.ppthub.shop/api/v1/admin/accounts/data \
  -H "Content-Type: application/json" \
  -H "x-api-key: admin-82e0d2289de27ff69b42321ecf07cfb97f0bd9c1dbfa66d794211ff3af2c936d" \
  -H "Idempotency-Key: import-${TIMESTAMP}" \
  -d "{
    \"data\": {
      \"type\": \"sub2api-data\",
      \"version\": 1,
      \"exported_at\": \"${TIMESTAMP}\",
      \"proxies\": [],
      \"accounts\": $(echo $EXPORT_DATA | python3 -c 'import sys,json; print(json.dumps(json.load(sys.stdin)["accounts"]))')
    },
    \"skip_default_group_bind\": true
  }"
```

### 4.7 字段映射关系

codex-register 数据库字段如何映射到 Sub2API：

```
codex-register (数据库)              Sub2API (导入格式)
─────────────────────────────────────────────────────────
Account.email                  →    name
"openai"                       →    platform
"oauth"                        →    type
Account.access_token           →    credentials.access_token
Account.refresh_token          →    credentials.refresh_token
Account.account_id             →    credentials.chatgpt_account_id
Account.workspace_id           →    credentials.organization_id
Account.client_id              →    credentials.client_id
Account.expires_at (转时间戳)   →    credentials.expires_at
固定 863999                    →    credentials.expires_in (~10天)
固定模型列表                    →    credentials.model_mapping
```

---

## 五、其他导出格式

系统支持 4 种导出格式，按需选用：

| 格式 | API 端点 | 用途 | 文件名 |
|------|---------|------|--------|
| **Sub2API** | `POST /api/accounts/export/sub2api` | 导入 Sub2API 平台 | `sub2api_tokens_xxx.json` |
| **JSON** | `POST /api/accounts/export/json` | 通用 JSON 备份 | `accounts_xxx.json` |
| **CSV** | `POST /api/accounts/export/csv` | Excel/表格查看 | `accounts_xxx.csv` |
| **CPA** | `POST /api/accounts/export/cpa` | CPA 平台导入 | `{email}.json` 或 `.zip` |

**通用请求参数（所有导出端点共用）：**
```json
{
  "ids": [1, 2, 3],                    // 指定账号 ID
  "select_all": true,                  // 或全选
  "status_filter": "active",           // 按状态筛选
  "email_service_filter": "tempmail",  // 按邮箱服务筛选
  "search_filter": "keyword"           // 关键词搜索
}
```

---

## 六、日常运营操作速查

### 6.1 注册新账号

```bash
# Web UI 操作最方便：浏览器打开 → 选邮箱服务 → 填数量 → 开始

# 或 SSH 到 VM 后 API 调用
gcloud compute ssh codex-register --zone=us-west1-b
curl -X POST http://localhost:8000/api/register/start \
  -H "Content-Type: application/json" \
  -d '{"email_service_id": 1, "count": 5}'
```

### 6.2 查看已注册账号

```bash
# Web UI: 浏览器 → 账号管理页面

# API:
curl -s http://localhost:8000/api/accounts | python3 -m json.tool

# 数据库直查:
sqlite3 ~/codex-register/data/database.db \
  "SELECT id, email, password, status, registered_at FROM accounts"
```

### 6.3 导出并导入 Sub2API（完整手动流程）

```bash
# 1. SSH 到 VM
gcloud compute ssh codex-register --zone=us-west1-b

# 2. 导出
curl -s -X POST http://localhost:8000/api/accounts/export/sub2api \
  -H "Content-Type: application/json" \
  -d '{"select_all": true, "status_filter": "active"}' \
  > ~/sub2api_export.json

# 3. 查看导出内容
cat ~/sub2api_export.json | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(f'共导出 {len(data[\"accounts\"])} 个账号:')
for a in data['accounts']:
    print(f'  - {a[\"name\"]}')
"

# 4. 上传到 Sub2API（API 方式）
curl -X POST https://sub2api.ppthub.shop/api/v1/admin/accounts/data \
  -H "Content-Type: application/json" \
  -H "x-api-key: admin-82e0d2289de27ff69b42321ecf07cfb97f0bd9c1dbfa66d794211ff3af2c936d" \
  -d "{
    \"data\": $(cat ~/sub2api_export.json),
    \"skip_default_group_bind\": true
  }"
```

### 6.4 VM 管理

```bash
# 从本地 Mac 操作
gcloud compute ssh codex-register --zone=us-west1-b     # SSH 到 VM
gcloud compute instances stop codex-register --zone=us-west1-b   # 停止（省钱）
gcloud compute instances start codex-register --zone=us-west1-b  # 启动

# VM 内服务管理
sudo systemctl status codex-register        # 查看状态
sudo systemctl restart codex-register       # 重启服务
sudo journalctl -u codex-register -f        # 实时日志
```

---

## 七、常见问题 & 排查

| 问题 | 原因 | 解决 |
|------|------|------|
| 注册时 IP 检查失败 | GCP IP 被误判 | 极少见，换可用区重建 VM |
| 创建邮箱失败 | Tempmail.lol API 不稳定 | 重试；或使用自建邮箱服务（第九章） |
| 验证码等待超时 | 邮件延迟/邮箱过期 | 重试注册 |
| 注册表单 429 | 同 IP 请求太频繁 | 等 5 分钟重试 |
| 注册表单 403 | GCP IP 段被 OpenAI 封 | 换区域重建 VM |
| access_token 过期 | Token 默认 ~10 天有效 | 用 refresh_token 刷新 |
| Sub2API 导入失败 | JSON 格式不对 | 确认用 export/sub2api 端点导出 |
| Web UI 打不开 | 防火墙/服务未启动 | 检查 allow-codex-web 规则 + systemctl status |

### GCP IP 被封应急

```bash
# 在本地 Mac 执行
# 删除旧 VM
gcloud compute instances delete codex-register --zone=us-west1-b --quiet

# 换可用区重建（获得新 IP 段）
gcloud compute instances create codex-register \
  --zone=us-central1-a \
  --machine-type=e2-small \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=20GB \
  --boot-disk-type=pd-balanced \
  --tags=codex-web \
  --metadata=enable-oslogin=FALSE

# 然后重新执行 Phase 2 的 Step 4-7
```

---

## 八、费用 & 资源

| 资源 | 规格 | 月费用 |
|------|------|--------|
| VM (e2-small) | 2 vCPU + 2GB RAM | ~$13 |
| 磁盘 (pd-balanced) | 20GB | ~$2 |
| 网络出站 | <1GB | 免费 |
| Tempmail.lol | 免费公共 API | $0 |
| Cloudflare Worker × 6 | 自建邮箱 | $0 |
| Cloudflare D1 × 6 | 邮件存储 | $0 |
| Cloudflare Email Routing × 6 | 收信转发 | $0 |
| **合计** | | **~$15/月** |

> 自建邮箱新增费用 = $0（仅域名年费，已支付）

---

## 九、自建邮箱服务（cloudflare_temp_email）

### 9.1 架构总览

```
┌─────────────────────────────────────────────────────────────────────┐
│                     自建邮箱架构                                      │
│                                                                     │
│  发件方 (OpenAI)                                                    │
│     │                                                               │
│     ▼                                                               │
│  Cloudflare Email Routing (Catch-all)                               │
│     │  任何前缀@域名 都能收                                          │
│     ▼                                                               │
│  Cloudflare Worker (cloudflare_temp_email)                          │
│     │  解析邮件 → 存入 D1 数据库                                     │
│     │  提供 Admin API (x-admin-auth 认证)                            │
│     ▼                                                               │
│  codex-register (temp_mail 类型)                                    │
│     │  创建随机邮箱 → 轮询收件 → 提取验证码                          │
│     ▼                                                               │
│  OpenAI 注册完成                                                    │
│                                                                     │
│  × 6 个域名，分散在 3 个 Cloudflare 账号                            │
│  codex-register 按 priority 自动轮转使用                             │
└─────────────────────────────────────────────────────────────────────┘
```

### 9.2 核心组件

| 组件 | 说明 |
|------|------|
| **cloudflare_temp_email** | [开源项目](https://github.com/dreamhunter2333/cloudflare_temp_email)，⭐7000，MIT，活跃维护 |
| **Cloudflare Worker** | 运行邮箱服务的 Serverless 函数 |
| **Cloudflare D1** | SQLite 数据库，存储邮件数据 |
| **Cloudflare Email Routing** | 域名收信 → Catch-all → 转发到 Worker |
| **codex-register temp_mail** | `src/services/temp_mail.py`，已内置完全兼容的客户端 |

### 9.3 部署新域名（完整流程）

#### Phase A: DNS 托管到 Cloudflare

> 如果域名已在 Cloudflare 注册/托管，跳过此步。

1. Cloudflare Dashboard → **Add site** → 输入域名
2. 选择 **Free** 计划
3. Cloudflare 给出 2 个 NS 地址（如 `diana.ns.cloudflare.com`）
4. 去域名注册商修改 NS 记录：
   - **阿里云**: 域名管理 → DNS 修改 → 修改 DNS 服务器
   - **GoDaddy**: My Domains → DNS → Nameservers → Change
5. 等待生效（几分钟 ~ 24 小时）
6. 完成标志：Cloudflare Dashboard 域名显示 **Active** ✅

#### Phase B: 部署 Worker

**方式一：使用脚本（推荐）**

```bash
# 前置：安装 Node.js >= 18，登录 wrangler
npx wrangler login

# 先在 Cloudflare Dashboard 创建 D1 数据库:
# Workers & Pages → D1 → Create database → 命名: temp-email-{简称}
# 复制 database_id

# 执行部署脚本
./scripts/deploy-cf-email.sh \
  --domain example.com \
  --short-name example \
  --admin-password "YourSecurePass123" \
  --d1-id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

**方式二：手动部署**

```bash
# Step B1: 克隆项目
git clone https://github.com/dreamhunter2333/cloudflare_temp_email.git
cd cloudflare_temp_email/worker

# Step B2: 编辑 wrangler.toml
#   name = "temp-email-{简称}"
#   [vars] ADMIN_PASSWORDS, DOMAINS
#   [[d1_databases]] binding, database_name, database_id

# Step B3: 部署
npm install
npx wrangler deploy

# Step B4: 初始化数据库
npx wrangler d1 execute temp-email-{简称} --file=../db/schema.sql --remote
```

#### Phase B5: 配置 Email Routing（必须手动！）

1. Cloudflare Dashboard → 选择域名 → **Email** → **Email Routing**
2. 点击 **Enable Email Routing**（首次需验证域名所有权）
3. **Routing rules** → **Catch-all address**:
   - Action: **Send to a Worker**
   - Destination: 选择 `temp-email-{简称}`
4. 完成标志：Email Routing 显示 **Active**，Catch-all 指向 Worker

#### Phase B6: 验证收件

```bash
# 从任意邮箱发邮件到 test@你的域名.com

# 检查是否收到（替换实际的 Worker URL 和密码）
curl -s 'https://temp-email-xxx.yyy.workers.dev/admin/mails?limit=5' \
  -H 'x-admin-auth: YourSecurePass123' | python3 -m json.tool
```

#### Phase C: 注册到 codex-register

**方式一：使用脚本（推荐）**

```bash
./scripts/register-email-service.sh \
  --domain example.com \
  --short-name example \
  --worker-url "https://temp-email-example.xxx.workers.dev" \
  --admin-password "YourSecurePass123" \
  --priority 0
```

**方式二：手动 API 调用**

```bash
gcloud compute ssh codex-register --zone=us-west1-b --command='
curl -s -X POST http://localhost:8000/api/email-services \
  -H "Content-Type: application/json" \
  -d "{
    \"service_type\": \"temp_mail\",
    \"name\": \"自建邮箱-example\",
    \"config\": {
      \"base_url\": \"https://temp-email-example.xxx.workers.dev\",
      \"admin_password\": \"YourSecurePass123\",
      \"domain\": \"example.com\",
      \"enable_prefix\": true
    },
    \"enabled\": true,
    \"priority\": 0
  }"
'
```

**测试连通性：**

```bash
# 替换 {id} 为实际服务 ID
gcloud compute ssh codex-register --zone=us-west1-b --command='
curl -s -X POST http://localhost:8000/api/email-services/{id}/test
'
```

**单次注册验证：**
- Web UI (`http://34.187.162.3:8000`) → 选择自建邮箱服务 → 注册 1 个
- 确认验证码在 120 秒内收到

### 9.4 Admin API 速查

所有请求需要 `x-admin-auth` header。

| 操作 | 请求 |
|------|------|
| 查看邮件列表 | `GET /admin/mails?limit=20&offset=0` |
| 按地址查邮件 | `GET /admin/mails?address=test@domain.com` |
| 创建邮箱地址 | `POST /admin/new_address` body: `{"name":"test","domain":"domain.com","enablePrefix":true}` |
| 健康检查 | `GET /admin/mails?limit=1` (200 = 正常) |

```bash
# 示例：查看最近 5 封邮件
curl -s 'https://temp-email-xxx.workers.dev/admin/mails?limit=5' \
  -H 'x-admin-auth: YOUR_PASSWORD' | python3 -m json.tool

# 示例：创建邮箱
curl -s -X POST 'https://temp-email-xxx.workers.dev/admin/new_address' \
  -H 'x-admin-auth: YOUR_PASSWORD' \
  -H 'Content-Type: application/json' \
  -d '{"name":"test123","domain":"example.com","enablePrefix":true}'
```

### 9.5 自建邮箱 vs Tempmail.lol 对比

| 维度 | Tempmail.lol | 自建邮箱 (CF Worker) |
|------|-------------|---------------------|
| 域名 | 公共共享域名 | 自有私有域名 |
| 封禁风险 | **高** — 公共域名易被 OpenAI 封 | **低** — 私有域名不易被发现 |
| 费用 | $0 | $0 (域名年费已付) |
| 邮箱有效期 | ~10 分钟 | 永久（存在 D1 数据库） |
| 可控性 | 无 | 完全可控 |
| 稳定性 | 依赖第三方 | 自有基础设施 |
| 多域名 | 不支持 | ✅ 6 个域名自动轮转 |
| 代码改动 | - | 无需改动 (`temp_mail` 类型兼容) |

### 9.6 排查自建邮箱问题

| 问题 | 排查步骤 |
|------|---------|
| Worker 返回 401 | 检查 Admin 密码是否正确，注意 JSON 转义 |
| Worker 返回 404 | 确认 Worker 名称和 URL 正确 |
| 发邮件后 Worker 没收到 | 检查 Email Routing 是否 Active，Catch-all 是否指向正确 Worker |
| codex-register 连接超时 | 确认 Worker URL 可从 GCP VM 访问（`curl` 测试） |
| 验证码提取失败 | 检查邮件内容是否包含 "openai" 关键词（过滤条件） |
| D1 数据库错误 | 确认已执行 schema.sql 初始化 |

### 9.7 批量管理

```bash
# 查看所有邮箱服务状态
gcloud compute ssh codex-register --zone=us-west1-b --command='
curl -s http://localhost:8000/api/email-services | python3 -m json.tool
'

# 禁用某个邮箱服务（如域名被封）
gcloud compute ssh codex-register --zone=us-west1-b --command='
curl -s -X PUT http://localhost:8000/api/email-services/{id} \
  -H "Content-Type: application/json" \
  -d "{\"enabled\": false}"
'

# 调整优先级
gcloud compute ssh codex-register --zone=us-west1-b --command='
curl -s -X PUT http://localhost:8000/api/email-services/{id} \
  -H "Content-Type: application/json" \
  -d "{\"priority\": 10}"
'
```

### 9.8 迁移计划

```
阶段 1: 部署第 1 个域名 → 验证注册 1 个 OpenAI 账号成功
阶段 2: 批量部署其余 5 个域名
阶段 3: 所有域名验证通过 → 禁用 Tempmail.lol 服务
阶段 4: 日常运营，按需增减域名
```
