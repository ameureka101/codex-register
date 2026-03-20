# Codex-Register 分步实施指南 (Google Cloud 版)

> 部署方案：Google Cloud Compute Engine 全新 VM
> 本地环境：macOS ARM64 (M1) | gcloud CLI 561.0.0
> GCP 项目：project-5080dba5-184b-4c23-925
> GCP 区域：us-west1-b (美国西部，俄勒冈)
> VM 规格：e2-small (2 vCPU + 2GB RAM)
> 创建时间：2026-03-20
> 状态：实施中

---

## 已确认的环境条件

```
本地 (macOS):
  ✅ gcloud CLI 561.0.0    — 已安装已认证
  ✅ 账号已登录             — jamesd267278@gmail.com
  ✅ 项目已配置             — project-5080dba5-184b-4c23-925
  ✅ 区域已配置             — us-west1 / us-west1-b
  ✅ Compute Engine API     — 已启用
  ✅ 计费账号               — 018109-66AECE-3A01E7 (已开通)
  ✅ SSH 密钥               — 已配置 (amerlin@MacBook-Pro-4.lan)
  ✅ 防火墙 SSH(22)         — 已放通

GCP 上需要新建:
  ⬜ VM 实例 codex-register — e2-small, Debian 12, 20GB
  ⬜ 防火墙规则 8000 端口   — allow-codex-web
  ⬜ 项目代码 & 依赖        — 在 VM 上安装
  ⬜ .env 配置              — 在 VM 上创建
```

---

## 总体路线图

```
Phase 1: GCP 基础设施 (本地 gcloud 操作)
  ├── Step 1: 创建 VM 实例
  ├── Step 2: 配置防火墙规则 (开放 8000 端口)
  └── Step 3: SSH 连接并验证 VM 环境

Phase 2: VM 环境初始化 (SSH 到 VM 操作)
  ├── Step 4: 安装系统依赖 (Python, pip, git)
  ├── Step 5: 克隆项目 & 安装 Python 依赖
  ├── Step 6: 创建 .env 配置文件
  └── Step 7: 验证网络连通性 (IP 位置检查)

Phase 3: 启动服务
  ├── Step 8: 首次启动 Web UI
  ├── Step 9: 从本地浏览器访问 Web UI
  └── Step 10: 配置为后台常驻服务 (systemd)

Phase 4: 配置邮箱 & 首次注册测试
  ├── Step 11: 在 Web UI 中配置邮箱服务
  ├── Step 12: 执行单次注册测试 🎯
  └── Step 13: 排查问题 & 调优

Phase 5: 生产加固 & 批量运营 (可选)
  ├── Step 14: 配置动态代理 (批量注册用)
  ├── Step 15: 批量注册调参
  ├── Step 16: 配置 CPA/Sub2API 上传
  └── Step 17: 安全加固 (Nginx + SSL + 备份)
```

---

## Phase 1: GCP 基础设施

### ═══════════════════════════════════════════
### Step 1: 创建 VM 实例
### ═══════════════════════════════════════════

在本地终端执行：

```bash
gcloud compute instances create codex-register \
  --zone=us-west1-b \
  --machine-type=e2-small \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=20GB \
  --boot-disk-type=pd-balanced \
  --tags=codex-web \
  --metadata=enable-oslogin=FALSE \
  --labels=app=codex-register
```

**参数说明：**

| 参数 | 值 | 说明 |
|------|-----|------|
| 实例名 | `codex-register` | 新建，不影响已有的 token101-prod |
| 机型 | `e2-small` | 2 vCPU + 2GB RAM，月费 ~$13 |
| 系统 | Debian 12 (Bookworm) | 稳定、轻量 |
| 磁盘 | 20GB pd-balanced | 充足 |
| 标签 | `codex-web` | 防火墙规则匹配用 |
| 区域 | us-west1-b | 美国西部，IP 为美国 |

**完成标志：**
```bash
gcloud compute instances list
# 应看到 codex-register 状态 RUNNING，有 EXTERNAL_IP
```

**状态：** [ ] 未完成

---

### ═══════════════════════════════════════════
### Step 2: 配置防火墙规则
### ═══════════════════════════════════════════

```bash
gcloud compute firewall-rules create allow-codex-web \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:8000 \
  --target-tags=codex-web \
  --source-ranges=0.0.0.0/0 \
  --description="Allow codex-register Web UI on port 8000"
```

> 安全提示：`0.0.0.0/0` 允许所有 IP 访问。
> 生产环境建议限制为你的公网 IP：`--source-ranges=你的IP/32`
> 查看本地公网 IP：`curl -s ifconfig.me`

**完成标志：**
```bash
gcloud compute firewall-rules list --filter="name=allow-codex-web"
```

**状态：** [ ] 未完成

---

### ═══════════════════════════════════════════
### Step 3: SSH 连接并验证 VM
### ═══════════════════════════════════════════

```bash
# SSH 到 VM
gcloud compute ssh codex-register --zone=us-west1-b

# 也可以获取 IP 后直接 ssh
VM_IP=$(gcloud compute instances describe codex-register \
  --zone=us-west1-b --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
echo "VM External IP: $VM_IP"
```

进入 VM 后验证：
```bash
echo "=== OS ===" && cat /etc/os-release | head -3
echo "=== IP ===" && curl -s https://cloudflare.com/cdn-cgi/trace | grep loc=
echo "=== Memory ===" && free -h | head -2
echo "=== Disk ===" && df -h / | tail -1
echo "=== User ===" && whoami
```

**期望结果：**
```
OS: Debian GNU/Linux 12 (bookworm)
IP: loc=US                      ← 美国 IP，无需代理！
Memory: ~2GB
Disk: ~20GB
User: amerlin 或 jamesd267278_gmail_com
```

**完成标志：** `loc=US` 确认 IP 在美国

**状态：** [ ] 未完成

---

## Phase 2: VM 环境初始化

> 以下所有命令在 VM 内通过 SSH 执行

### ═══════════════════════════════════════════
### Step 4: 安装系统依赖
### ═══════════════════════════════════════════

```bash
# 更新系统
sudo apt-get update && sudo apt-get upgrade -y

# 安装 Python 3 + 构建工具
sudo apt-get install -y \
  python3 \
  python3-pip \
  python3-venv \
  python3-dev \
  git \
  curl \
  build-essential \
  libssl-dev \
  libffi-dev

# 验证
python3 --version   # 期望: 3.11+
pip3 --version
git --version
```

**（推荐）安装 uv 包管理器：**
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env
uv --version
```

**完成标志：** python3、pip3、git 可用

**状态：** [ ] 未完成

---

### ═══════════════════════════════════════════
### Step 5: 克隆项目 & 安装 Python 依赖
### ═══════════════════════════════════════════

```bash
cd ~
git clone https://github.com/cnlimiter/codex-register.git
cd codex-register

# 方式 A: uv（推荐）
uv venv .venv
source .venv/bin/activate
uv pip install -r requirements.txt

# 方式 B: pip + venv
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 验证关键依赖
python -c "import curl_cffi; print('curl_cffi OK')"
python -c "import fastapi; print('fastapi OK')"
python -c "import sqlalchemy; print('sqlalchemy OK')"
```

**完成标志：** 三个 import 无报错

**状态：** [ ] 未完成

---

### ═══════════════════════════════════════════
### Step 6: 创建 .env 配置文件
### ═══════════════════════════════════════════

```bash
cd ~/codex-register

cat > .env << 'ENVEOF'
APP_HOST=0.0.0.0
APP_PORT=8000
APP_ACCESS_PASSWORD=此处替换为你的强密码
ENVEOF
```

> ⚠️ 重要：请替换 `此处替换为你的强密码` 为一个真实的密码！

**完成标志：** `.env` 已创建，`cat .env` 确认内容正确

**状态：** [ ] 未完成

---

### ═══════════════════════════════════════════
### Step 7: 验证网络连通性
### ═══════════════════════════════════════════

GCP VM 在美国，直连即可访问 OpenAI，无需任何代理：

```bash
echo "--- 1. IP Location ---"
curl -s https://cloudflare.com/cdn-cgi/trace | grep loc=

echo "--- 2. auth.openai.com ---"
curl -s -o /dev/null -w "HTTP %{http_code}\n" https://auth.openai.com

echo "--- 3. sentinel.openai.com ---"
curl -s -o /dev/null -w "HTTP %{http_code}\n" https://sentinel.openai.com

echo "--- 4. api.tempmail.lol ---"
curl -s -o /dev/null -w "HTTP %{http_code}\n" https://api.tempmail.lol/v2/inbox/create
```

**期望：**
```
1. loc=US           ← 美国 IP ✅
2. HTTP 200 或 302  ← OpenAI 可达 ✅
3. HTTP 200 或 405  ← Sentinel 可达 ✅
4. HTTP 200 或 405  ← Tempmail 可达 ✅
```

**完成标志：** 至少前 3 项通过

**状态：** [ ] 未完成

---

## Phase 3: 启动服务

### ═══════════════════════════════════════════
### Step 8: 首次启动 Web UI
### ═══════════════════════════════════════════

```bash
cd ~/codex-register
source .venv/bin/activate
python webui.py
```

**期望输出：**
```
[Settings] 初始化默认设置: ...
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
```

> 保持运行，打开新终端或浏览器进行 Step 9

**完成标志：** 看到 `Uvicorn running`

**状态：** [ ] 未完成

---

### ═══════════════════════════════════════════
### Step 9: 浏览器访问 Web UI
### ═══════════════════════════════════════════

在本地 Mac 终端获取 VM IP：
```bash
gcloud compute instances describe codex-register \
  --zone=us-west1-b --format='get(networkInterfaces[0].accessConfigs[0].natIP)'
```

浏览器打开：`http://<VM外部IP>:8000`

1. 输入 .env 中设置的 APP_ACCESS_PASSWORD
2. 应看到注册系统主界面

> 打不开排查：
> - 防火墙 `allow-codex-web` 是否创建？（Step 2）
> - VM 内 webui.py 是否在运行？（Step 8）
> - APP_HOST 是否为 `0.0.0.0`？

**完成标志：** 浏览器成功登录 Web UI

**状态：** [ ] 未完成

---

### ═══════════════════════════════════════════
### Step 10: 配置 systemd 后台服务
### ═══════════════════════════════════════════

先 Ctrl+C 停掉前台进程，然后在 VM 内执行：

```bash
# 获取当前用户名和家目录
REAL_USER=$(whoami)
REAL_HOME=$(eval echo ~$REAL_USER)
echo "User: $REAL_USER, Home: $REAL_HOME"

# 创建 systemd 服务
sudo tee /etc/systemd/system/codex-register.service > /dev/null << EOF
[Unit]
Description=Codex Register Web UI
After=network.target

[Service]
Type=simple
User=${REAL_USER}
WorkingDirectory=${REAL_HOME}/codex-register
Environment=PATH=${REAL_HOME}/codex-register/.venv/bin:/usr/bin:/bin
ExecStart=${REAL_HOME}/codex-register/.venv/bin/python webui.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 启用并启动
sudo systemctl daemon-reload
sudo systemctl enable codex-register
sudo systemctl start codex-register

# 验证
sudo systemctl status codex-register
```

**常用管理命令：**
```bash
sudo systemctl start codex-register     # 启动
sudo systemctl stop codex-register      # 停止
sudo systemctl restart codex-register   # 重启
sudo journalctl -u codex-register -f    # 实时日志
```

**完成标志：** `status` 显示 `active (running)`

**状态：** [ ] 未完成

---

## Phase 4: 配置邮箱 & 首次注册测试

### ═══════════════════════════════════════════
### Step 11: 配置邮箱服务
### ═══════════════════════════════════════════

在浏览器 Web UI 中操作：

**先用 Tempmail.lol（零配置开箱即用）：**

1. 进入「邮箱服务」页面
2. 检查是否已有 Tempmail.lol
3. 没有则「添加服务」→ 选 Tempmail.lol → 默认配置 → 保存
4. 点击「测试」→ 连接成功

**后续可升级的方案：**

| 邮箱服务 | 配置需求 | 适合 |
|---------|---------|------|
| TempMail CF Worker | Worker 地址 + Admin 密码 + 域名 | 大批量首选 |
| Freemail CF Worker | Worker 地址 + Admin Token | 大批量 |
| DuckMail | API 地址 + 默认域名 | 自建邮箱 |
| MoeMail | API 地址 + API 密钥 | 自有域名 |
| Outlook | 批量导入账号 | 最稳定 |

**完成标志：** 邮箱服务测试通过

**状态：** [ ] 未完成

---

### ═══════════════════════════════════════════
### Step 12: 单次注册测试 🎯 关键里程碑
### ═══════════════════════════════════════════

在 Web UI 首页：

1. 邮箱服务：Tempmail.lol
2. 注册数量：**1**
3. 点击「开始注册」
4. 观察实时日志

**GCP VM 直连无需代理！** VM 在美国，IP 自动通过检查。

**期望成功日志：**
```
[HH:MM:SS] ============================================================
[HH:MM:SS] 开始注册流程
[HH:MM:SS] ============================================================
[HH:MM:SS] 1. 检查 IP 地理位置...
[HH:MM:SS] IP 位置: US                          ← VM 在美国，通过！
[HH:MM:SS] 2. 创建邮箱...
[HH:MM:SS] 成功创建邮箱: xxxxx@tempmail.lol
[HH:MM:SS] 3. 初始化会话...
[HH:MM:SS] 4. 开始 OAuth 授权流程...
[HH:MM:SS] 5. 获取 Device ID...
[HH:MM:SS] Device ID: xxxxxxxx-xxxx-xxxx-xxxx
[HH:MM:SS] 6. 检查 Sentinel 拦截...
[HH:MM:SS] Sentinel token 获取成功
[HH:MM:SS] 7. 提交注册表单...
[HH:MM:SS] 提交注册表单状态: 200
[HH:MM:SS] 8. 注册密码...
[HH:MM:SS] 生成密码: xxxxxxxxxxxx
[HH:MM:SS] 9. 发送验证码...
[HH:MM:SS] 验证码发送状态: 200
[HH:MM:SS] 10. 等待验证码...
[HH:MM:SS] 成功获取验证码: 123456
[HH:MM:SS] 11. 验证验证码...
[HH:MM:SS] 验证码校验状态: 200
[HH:MM:SS] 12. 创建用户账户...
[HH:MM:SS] 账户创建状态: 200
[HH:MM:SS] 13. 获取 Workspace ID...
[HH:MM:SS] 14. 选择 Workspace...
[HH:MM:SS] 15. 跟随重定向链...
[HH:MM:SS] 16. 处理 OAuth 回调...
[HH:MM:SS] OAuth 授权成功
[HH:MM:SS] ============================================================
[HH:MM:SS] 注册成功!
[HH:MM:SS] ============================================================
```

**完成标志：** 「注册成功!」，账号页面出现新账号

**状态：** [ ] 未完成

---

### ═══════════════════════════════════════════
### Step 13: 常见问题排查
### ═══════════════════════════════════════════

| 卡在哪一步 | 原因 | 解决 |
|-----------|------|------|
| Step 1: `IP 检查失败` | 极少见，GCP IP 被误判 | 换可用区重建 VM |
| Step 5: `Device ID 失败` | auth.openai.com 连接异常 | VM 上 curl 测试确认 |
| Step 6: `Sentinel 失败` | 安全检测 | 通常可忽略，不影响 |
| Step 7: `表单 429` | 请求太频繁 | 等 5 分钟重试 |
| Step 7: `表单 403` | GCP IP 被封 | 换区域重建 VM（换 IP） |
| Step 10: `验证码超时` | 邮箱不稳定 | 重试或换邮箱服务 |
| Step 11: `验证码失败` | OTP 过期 | 重新注册 |

**GCP IP 被封应急：**
```bash
# 本地 Mac 执行 — 删除实例换 IP
gcloud compute instances delete codex-register --zone=us-west1-b --quiet
# 换一个可用区重建（不同 IP 段）
gcloud compute instances create codex-register \
  --zone=us-central1-a \
  --machine-type=e2-small \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=20GB \
  --boot-disk-type=pd-balanced \
  --tags=codex-web \
  --metadata=enable-oslogin=FALSE
# 然后从 Step 3 重做
```

---

## Phase 5: 生产加固 & 批量运营（成功后再做）

### Step 14: 配置动态代理（批量注册用）

同 IP 注册过多会被封。批量注册需配动态代理：
- Web UI → 设置 → 启用动态代理 → 填 API URL
- 每次注册自动获取不同出口 IP

### Step 15: 批量注册调参

```
注册数量:   5-10（先小批量）
并发模式:   流水线 (Pipeline)
并发数:     3
注册间隔:   15-60 秒
最大重试:   3 次
超时时间:   180 秒
```

### Step 16: 配置 CPA/Sub2API 上传

Web UI → 设置中按需配置上传目标。

### Step 17: 安全加固

```bash
# 限制 Web UI 访问来源 IP
gcloud compute firewall-rules update allow-codex-web \
  --source-ranges=你的公网IP/32

# 安装 Nginx + SSL (可选)
sudo apt-get install -y nginx certbot python3-certbot-nginx

# 定时备份数据库 (crontab)
crontab -e
# 添加：0 3 * * * cp ~/codex-register/data/database.db ~/backups/db-$(date +\%F).db
```

---

## 进度追踪

| Phase | Step | 描述 | 状态 | 备注 |
|-------|------|------|------|------|
| 1 | 1 | 创建 GCP VM | ✅ | e2-small, External IP: 34.187.162.3 |
| 1 | 2 | 防火墙规则 | ✅ | allow-codex-web, tcp:8000 |
| 1 | 3 | SSH 验证 VM | ✅ | loc=US, Debian 12, user=amerlin |
| 2 | 4 | 安装系统依赖 | ✅ | Python 3.11.2, pip 23.0.1, git 2.39.5, uv 0.10.11 |
| 2 | 5 | 克隆项目 & 依赖 | ✅ | 32 packages installed (uv) |
| 2 | 6 | .env 配置 | ✅ | 密码: Codex2026!Reg#Secure |
| 2 | 7 | 网络连通性 | ✅ | US IP, OpenAI/Sentinel/Tempmail 均可达 |
| 3 | 8 | 启动 Web UI | ✅ | systemd active (running) |
| 3 | 9 | 浏览器访问 | ✅ | API 验证通过 (HTTP 302) |
| 3 | 10 | systemd 服务 | ✅ | codex-register.service enabled |
| 4 | 11 | 邮箱服务 | ✅ | Tempmail.lol ID=1, 连通性正常 |
| 4 | 12 | **单次注册测试** | ⬜ | 🎯 关键里程碑 ← 当前步骤 |
| 4 | 13 | 问题排查 | ⬜ | |
| 5 | 14-17 | 生产加固 | ⬜ | 可选 |

---

## 附录: 快速命令参考

```bash
# ═══════════════════════════════════════
#  本地 Mac 终端 (gcloud 操作)
# ═══════════════════════════════════════

# VM 列表
gcloud compute instances list

# 获取 VM IP
gcloud compute instances describe codex-register \
  --zone=us-west1-b --format='get(networkInterfaces[0].accessConfigs[0].natIP)'

# SSH 到 VM
gcloud compute ssh codex-register --zone=us-west1-b

# 停止 VM (省钱，磁盘仍收费 ~$2/月)
gcloud compute instances stop codex-register --zone=us-west1-b

# 启动 VM
gcloud compute instances start codex-register --zone=us-west1-b

# 删除 VM (彻底删除)
gcloud compute instances delete codex-register --zone=us-west1-b

# ═══════════════════════════════════════
#  VM 内 (SSH 操作)
# ═══════════════════════════════════════

# 激活虚拟环境
cd ~/codex-register && source .venv/bin/activate

# 手动启动
python webui.py

# 服务管理
sudo systemctl start codex-register
sudo systemctl stop codex-register
sudo systemctl restart codex-register
sudo systemctl status codex-register
sudo journalctl -u codex-register -f     # 实时日志

# 检查 IP
curl -s https://cloudflare.com/cdn-cgi/trace | grep loc=

# 数据库
sqlite3 ~/codex-register/data/database.db ".tables"
sqlite3 ~/codex-register/data/database.db "SELECT count(*) FROM accounts"
```

---

## 费用估算

| 资源 | 规格 | 月费用 |
|------|------|--------|
| VM (e2-small) | 2 vCPU + 2GB | ~$13 |
| 磁盘 (pd-balanced) | 20GB | ~$2 |
| 网络出站 | <1GB | 免费 |
| **合计** | | **~$15/月** |

> 不用时 `gcloud compute instances stop codex-register --zone=us-west1-b`
> 停止后只收磁盘费 ~$2/月。
