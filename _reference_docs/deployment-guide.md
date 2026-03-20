# Codex-Register — OpenAI 自动注册系统 v2 完整部署指南

## 一、项目本质

**codex-register** 是一个 **自动化批量注册 OpenAI/Codex CLI 账号** 的 Web UI 系统。它能够：

1. 自动生成临时邮箱
2. 模拟浏览器指纹向 OpenAI 发起注册请求
3. 自动接收和填写邮箱验证码（OTP）
4. 完成 OAuth 授权流程，获取 access_token / refresh_token
5. 支持批量并发注册、账号管理、Token 刷新、订阅升级

---

## 二、注册流程全链路（16 步）

```
1.  检查 IP 地理位置 (不能是 CN/HK/MO/TW)
2.  创建临时邮箱
3.  初始化 curl_cffi 会话 (模拟 Chrome 浏览器指纹)
4.  生成 OAuth PKCE 授权 URL
5.  访问 auth.openai.com 获取 Device ID (oai-did Cookie)
6.  通过 Sentinel 安全检查获取 token
7.  提交注册表单 (邮箱 + signup 提示)
8.  设置密码 (随机生成 12 位)
9.  触发 OpenAI 发送 OTP 验证码
10. 从临时邮箱轮询获取 6 位验证码
11. 提交验证码校验
12. 创建用户账户 (随机姓名 + 随机生日)
13. 从 JWT 中解析 Workspace ID
14. 选择 Workspace
15. 跟随重定向链找到 OAuth 回调 URL
16. 用 authorization_code 换取 access_token
```

---

## 三、必须满足的前置条件

### 条件 1：海外 IP（最关键！）

系统第一步就会检查 IP 地理位置，**中国大陆 / 香港 / 澳门 / 台湾的 IP 直接被拒绝**。

```python
# 来自 http_client.py
if loc in ["CN", "HK", "MO", "TW"]:
    return False, loc  # 直接失败
```

**需要准备：**

| 方案 | 说明 | 推荐度 |
|------|------|--------|
| **海外代理/VPN** | HTTP/SOCKS5 代理，IP 在美国/日本/新加坡等 | ★★★★★ |
| **动态代理 API** | 每次请求获取不同的海外 IP（防封） | ★★★★★ |
| **海外云服务器** | 直接部署在海外 VPS 上 | ★★★★ |

> 最佳实践：动态代理 > 代理列表 > 固定代理 > 直连。批量注册时每个账号用不同 IP，防止被 OpenAI 批量封禁。

---

### 条件 2：邮箱服务（核心依赖）

系统支持 **6 种邮箱服务**，按照部署难度从低到高排列：

| 邮箱服务 | 配置要求 | 自部署需求 | 推荐度 |
|---------|---------|-----------|--------|
| **① Tempmail.lol** | 零配置 | 不需要 | ★★★ 开箱即用 |
| **② DuckMail** | API 地址 + 域名 + 可选 API Key | 需自建或使用第三方 | ★★★★ |
| **③ MoeMail (自定义域名)** | API 地址 + API 密钥 | 需自建 REST API 邮箱服务 | ★★★★ |
| **④ TempMail (CF Worker)** | Worker 地址 + Admin 密码 + 域名 | 需部署 Cloudflare Worker | ★★★★★ |
| **⑤ Freemail (CF Worker)** | Worker 地址 + Admin Token + 域名 | 需部署 Cloudflare Worker | ★★★★ |
| **⑥ Outlook** | IMAP OAuth + 批量导入账号 | 需要大量 Outlook 账号 | ★★★ |

> 最佳策略：
> - **快速上手：** 用 Tempmail.lol（零配置，但邮箱质量较低）
> - **大批量推荐：** 自部署 TempMail/Freemail CF Worker + 自有域名（稳定、无速率限制）
> - **最稳定：** Outlook 邮箱批量注册（需要准备大量 Outlook 账户）

---

### 条件 3：运行环境

| 需求 | 最低版本 | 说明 |
|------|---------|------|
| **Python** | 3.10+ | 核心运行时 |
| **Docker** (可选) | 最新 | 容器化部署 |
| **curl_cffi** | 0.14+ | 浏览器指纹模拟（核心反检测） |
| **网络** | - | 能访问 `auth.openai.com`, `sentinel.openai.com` |

---

## 四、完整部署步骤

### 方案 A：Docker 一键部署（推荐）

```bash
# 1. 克隆项目
git clone https://github.com/cnlimiter/codex-register.git
cd codex-register

# 2. 配置（可选，有默认值）
cp .env.example .env
# 编辑 .env，修改访问密码等

# 3. 启动
docker-compose up -d

# 4. 访问 Web UI
# http://your-server-ip:8000
# 默认密码: admin123
```

### 方案 B：本地运行

```bash
git clone https://github.com/cnlimiter/codex-register.git
cd codex-register

# 安装依赖
pip install -r requirements.txt
# 或 uv sync

# 启动
python webui.py --host 0.0.0.0 --port 8000 --access-password your_password
```

---

## 五、为了最大化成功率的准备清单

### 第一优先级 — 必须完成

| # | 准备事项 | 原因 | 预计时间 |
|---|---------|------|---------|
| 1 | **准备海外代理** | IP 检查是第一步，不过就直接失败 | 30 分钟 |
| 2 | **部署项目** | Docker 一键启动 | 10 分钟 |
| 3 | **配置至少一个邮箱服务** | 注册需要接收验证码 | 取决于方案 |
| 4 | **修改默认访问密码** | `admin123` 不安全 | 1 分钟 |

### 第二优先级 — 显著提升成功率

| # | 准备事项 | 说明 |
|---|---------|------|
| 5 | **准备动态代理服务** | 每次注册用不同 IP，避免批量封禁。在 Web UI 设置中配置动态代理 API |
| 6 | **自部署 TempMail/Freemail CF Worker** | 不依赖第三方、不限速率，是大批量注册的基础 |
| 7 | **准备自有域名** | 配合 CF Worker 使用自定义邮箱域名，邮箱质量更高 |
| 8 | **调整注册间隔** | 在 Web UI 设置中调整 `sleep_min/sleep_max`（默认 5-30 秒），防止触发限流 |
| 9 | **配置代理列表** | 添加多个代理并设置随机轮换 |

### 第三优先级 — 完善运营

| # | 准备事项 | 说明 |
|---|---------|------|
| 10 | **准备 Outlook 账号池** | 批量导入 Outlook 账号用于接收验证码，最稳定 |
| 11 | **配置 CPA 上传服务** | 注册成功后自动上传账号到 CPA 面板 |
| 12 | **配置 Sub2API 服务** | 账号自动上传到 API 管理平台 |
| 13 | **配置 Team Manager** | 支持自动升级到 Plus/Team 订阅 |
| 14 | **安装 Playwright** | `pip install playwright && playwright install chromium` 支持无痕浏览器打开支付页 |
| 15 | **使用 PostgreSQL** | 生产环境替代 SQLite，避免并发写锁 |
| 16 | **部署到海外 VPS** | 直接部署在美国/新加坡/日本的服务器上，省掉代理成本 |

---

## 六、关键配置参数说明

### 代理配置（Web UI → 设置页面）

| 配置 | 说明 |
|------|------|
| **静态代理** | `http://user:pass@host:port` 或 `socks5://host:port` |
| **动态代理 API** | 填写 API URL，每次注册自动获取新 IP |
| **代理优先级** | 动态代理 → 代理列表(随机/默认) → 直连 |

### 注册参数

| 参数 | 默认值 | 建议 |
|------|-------|------|
| `max_retries` | 3 | 保持默认 |
| `timeout` | 120 秒 | 可适当延长到 180 秒 |
| `password_length` | 12 | 保持默认 |
| `sleep_min` | 5 秒 | 批量时建议 10+ |
| `sleep_max` | 30 秒 | 批量时建议 60+ |
| `max_concurrent` | 1-50 | 建议 3-5，过高易触发限流 |

---

## 七、风险与注意事项

| 风险 | 说明 | 应对 |
|------|------|------|
| **IP 封禁** | 同 IP 注册过多会被 OpenAI 拉黑 | 使用动态代理，每个账号换 IP |
| **Sentinel 反爬** | OpenAI 的安全检测机制 | `curl_cffi` 已模拟 Chrome 指纹，系统自动处理 |
| **验证码超时** | 邮箱服务慢可能收不到 OTP | 超时默认 120 秒，选用稳定邮箱服务 |
| **账号封禁** | 批量注册的账号可能被检测并封禁 | 控制注册速率，使用高质量代理 |
| **TOS 违规** | 批量注册违反 OpenAI 服务条款 | 个人使用需了解风险 |

---

## 八、总结

> **部署本身极其简单（docker-compose up 即可），真正的准备工作是：① 海外 IP 代理 ② 邮箱服务。**
> 如果你能准备好稳定的海外动态代理 + 自部署 CF Worker 临时邮箱，批量注册成功率会很高。
