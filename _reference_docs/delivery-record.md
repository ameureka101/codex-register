# Codex-Register 交付记录

> 更新时间：2026-03-20 (v2: 自建邮箱服务)
> 项目：codex-register on Google Cloud

---

## 已交付的 GCP 基础设施

### VM 实例

| 项目 | 值 |
|------|-----|
| 实例名 | `codex-register` |
| 区域 | `us-west1-b` |
| 机型 | `e2-small` (2 vCPU + 2GB RAM) |
| 系统 | Debian 12 (Bookworm) |
| 磁盘 | 20GB pd-balanced |
| 外部 IP | `34.187.162.3` |
| 内部 IP | `10.138.0.3` |
| 网络标签 | `codex-web` |
| 状态 | **RUNNING** |

### 防火墙规则

| 项目 | 值 |
|------|-----|
| 规则名 | `allow-codex-web` |
| 方向 | INGRESS |
| 协议/端口 | tcp:8000 |
| 来源 | 0.0.0.0/0 (所有 IP) |
| 目标标签 | codex-web |

### 已有实例（未修改）

| 实例名 | 状态 |
|--------|------|
| `token101-prod` | RUNNING (未动) |

---

## 已交付的 VM 内部环境

### 系统用户

```
用户名: amerlin
家目录: /home/amerlin
```

### 已安装的软件

| 软件 | 版本 |
|------|------|
| Python | 3.11.2 |
| pip | 23.0.1 |
| git | 2.39.5 |
| uv (包管理器) | 0.10.11 |
| build-essential | ✅ |
| libssl-dev / libffi-dev | ✅ |

### 项目部署

```
项目路径:     /home/amerlin/codex-register
虚拟环境:     /home/amerlin/codex-register/.venv
Python 依赖:  32 packages (通过 uv 安装)
来源:         git clone https://github.com/cnlimiter/codex-register.git
```

**关键依赖版本：**

| 包 | 版本 |
|-----|------|
| curl_cffi | 0.14.0 |
| fastapi | 0.135.1 |
| sqlalchemy | 2.0.48 |
| uvicorn | 0.42.0 |
| pydantic | 2.12.5 |

### .env 配置

```
文件路径: /home/amerlin/codex-register/.env
APP_HOST=0.0.0.0
APP_PORT=8000
APP_ACCESS_PASSWORD=Codex2026!Reg#Secure
```

> ⚠️ 建议尽早修改密码为自己的密码

### systemd 服务

```
服务文件:     /etc/systemd/system/codex-register.service
服务名:       codex-register
状态:         active (running), enabled (开机自启)
```

**管理命令：**
```bash
sudo systemctl start codex-register     # 启动
sudo systemctl stop codex-register      # 停止
sudo systemctl restart codex-register   # 重启
sudo systemctl status codex-register    # 查看状态
sudo journalctl -u codex-register -f    # 实时日志
```

---

## 已验证的网络连通性

| 测试目标 | 结果 | 说明 |
|---------|------|------|
| IP 地理位置 | **loc=US** | 美国 IP，无需代理 |
| auth.openai.com | HTTP 403 | 可达（未携带认证参数故 403） |
| sentinel.openai.com | HTTP 404 | 可达 |
| api.tempmail.lol | HTTP 201 | 可达，邮箱创建正常 |

---

## Web UI 访问信息

```
地址:   http://34.187.162.3:8000
密码:   Codex2026!Reg#Secure
```

---

## 已配置的 Sub2API 服务

| 项目 | 值 |
|------|-----|
| 服务 ID | 1 |
| 名称 | PPTHub Sub2API |
| API 地址 | `https://sub2api.ppthub.shop` |
| API Key | `admin-82e0d2289de27ff69b42321ecf07cfb97f0bd9c1dbfa66d794211ff3af2c936d` |
| 连通性 | **连接测试成功** ✅ |
| 配置时间 | 2026-03-20T07:35:26 |

### 已上传的账号

| # | 邮箱 | 上传状态 |
|---|------|---------|
| 1 | eckardt3c9ba1@q4k.moonairse.com | ✅ 成功 |
| 2 | amalita3ce3ff@6z.moonairse.com | ✅ 成功 |
| 3 | keffer3cea36@ojk.leadharbor.org | ✅ 成功 |

> 上传结果：成功 3 / 失败 0 / 跳过 0

---

## 已配置的邮箱服务

### 原有服务：Tempmail.lol（公共临时邮箱）

| 项目 | 值 |
|------|-----|
| 服务 ID | 1 |
| 服务类型 | tempmail (Tempmail.lol) |
| API 地址 | https://api.tempmail.lol/v2 |
| 连通性测试 | **服务连接正常** ✅ |
| 配置时间 | 2026-03-20T07:07:02 |
| 状态 | 运行中（计划迁移后禁用） |

> ⚠️ 公共域名存在被 OpenAI 封禁风险，建议迁移到自建邮箱服务

### 自建邮箱服务：cloudflare_temp_email（6 域名独立部署）

**架构**

```
6 个域名 × 各自独立部署 → codex-register 统一管理，自动轮转

Cloudflare 账号 A                    Cloudflare 账号 B
├── 域名1 → Worker + D1 + Email      ├── 域名3 → Worker + D1 + Email
├── 域名2 → Worker + D1 + Email      ├── 域名4 → Worker + D1 + Email

Cloudflare 账号 C                    codex-register (GCP VM)
├── 域名5 → Worker + D1 + Email      ├── 邮箱服务: 域名1 (priority: 0)
├── 域名6 → Worker + D1 + Email      ├── 邮箱服务: 域名2 (priority: 1)
                                      ├── ...
                                      └── 邮箱服务: 域名6 (priority: 5)
```

**技术栈**

| 组件 | 说明 | 费用 |
|------|------|------|
| 开源项目 | [cloudflare_temp_email](https://github.com/dreamhunter2333/cloudflare_temp_email) (MIT, ⭐7000) | 免费 |
| Cloudflare Worker × 6 | 处理 Admin API + 邮件存储 | $0 |
| Cloudflare D1 × 6 | SQLite 数据库存储邮件 | $0 |
| Cloudflare Email Routing × 6 | Catch-all → Worker 转发 | $0 |
| codex-register 对接 | `temp_mail` 类型，API 完全兼容 | 无需改代码 |

**各域名部署状态**

| # | 域名 | CF 账号 | DNS 托管 | Worker 部署 | Email Routing | codex-register | 注册测试 |
|---|------|---------|----------|-------------|---------------|----------------|---------|
| 1 | ppthub.shop | A | ✅ Active | ✅ `temp-email-ppthub` | ✅ Catch-all → Worker | ✅ 服务ID:2 priority:0 | ⬜ 待测试 |
| 2 | (待填写) | A | ⬜ 待完成 | ⬜ 待部署 | ⬜ 待配置 | ⬜ 待注册 | ⬜ 待测试 |
| 3 | (待填写) | B | ⬜ 待完成 | ⬜ 待部署 | ⬜ 待配置 | ⬜ 待注册 | ⬜ 待测试 |
| 4 | (待填写) | B | ⬜ 待完成 | ⬜ 待部署 | ⬜ 待配置 | ⬜ 待注册 | ⬜ 待测试 |
| 5 | (待填写) | C | ⬜ 待完成 | ⬜ 待部署 | ⬜ 待配置 | ⬜ 待注册 | ⬜ 待测试 |
| 6 | (待填写) | C | ⬜ 待完成 | ⬜ 待部署 | ⬜ 待配置 | ⬜ 待注册 | ⬜ 待测试 |

> 建议执行顺序：先完成 1 个域名全流程验证，再批量部署其余 5 个。
> 完成状态标记：⬜ 待完成 → ✅ 已完成

**部署脚本**

| 脚本 | 用途 |
|------|------|
| `scripts/deploy-cf-email.sh` | 自动化 Worker 部署（克隆、配置、部署、初始化 DB） |
| `scripts/register-email-service.sh` | 注册 Worker 到 codex-register |

---

## 当前进度

```
Phase 1: GCP 基础设施         ████████████ 100%  ✅ 完成
Phase 2: VM 环境初始化         ████████████ 100%  ✅ 完成
Phase 3: 启动服务              ████████████ 100%  ✅ 完成
Phase 4: 配置邮箱 & 注册测试   ████████████ 100%  ✅ 完成 (3 个账号已注册)
Phase 5: Sub2API 对接          ████████████ 100%  ✅ 完成 (3 个账号已上传)
Phase 6: 自建邮箱服务          ░░░░░░░░░░░░   0%  ⬜ 待实施 (6 个域名)
```

### Phase 6 子任务

```
6a: 域名 DNS 托管到 Cloudflare      ⬜ 0/6
6b: 部署 cloudflare_temp_email       ⬜ 0/6
6c: 配置 Email Routing               ⬜ 0/6
6d: 注册到 codex-register            ⬜ 0/6
6e: 单域名注册测试                   ⬜ 0/6
6f: 禁用 Tempmail.lol               ⬜ (全部域名完成后)
```

### 下一步操作

1. **先拿 1 个域名走完全流程**（Phase 6a → 6e，参照 operations-manual.md 第九章）
2. 验证注册成功后，批量部署其余 5 个
3. 6 个都完成后，禁用 Tempmail.lol 服务
4. 按需批量注册更多账号

---

## 费用估算

| 资源 | 月费用 |
|------|--------|
| VM (e2-small) | ~$13 |
| 磁盘 (20GB) | ~$2 |
| 网络出站 | 免费 |
| Cloudflare Worker × 6 | **$0** |
| Cloudflare D1 × 6 | **$0** |
| Cloudflare Email Routing × 6 | **$0** |
| **合计** | **~$15/月 (新增 $0)** |

> 不用时可停止 VM：`gcloud compute instances stop codex-register --zone=us-west1-b`
> 停止后只收磁盘费 ~$2/月

---

## 快速操作速查

```bash
# === 本地 Mac ===
gcloud compute ssh codex-register --zone=us-west1-b          # SSH 到 VM
gcloud compute instances stop codex-register --zone=us-west1-b   # 停止 VM
gcloud compute instances start codex-register --zone=us-west1-b  # 启动 VM

# === VM 内 ===
sudo systemctl status codex-register     # 服务状态
sudo journalctl -u codex-register -f     # 实时日志
cd ~/codex-register && source .venv/bin/activate  # 进入项目环境
```
