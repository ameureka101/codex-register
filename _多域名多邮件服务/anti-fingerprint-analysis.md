# 注册流程反指纹/防封禁分析报告

> 分析日期: 2026-03-20
> 当前评分: 4.9/10 (D级) — 容易被批量检测
> 状态: **待修复**

---

## 一、风险评级总表

| 组件 | 风险 | 评分 | 说明 |
|------|------|------|------|
| User-Agent | ❌ 致命 | 2/10 | 硬编码 `Chrome/120.0.0.0`，所有账号完全相同，版本号是假的 |
| OAuth 参数 | ❌ 致命 | 2/10 | `codex_cli_simplified_flow=true` 直接暴露自动化工具身份 |
| 名字库 | ❌ 致命 | 3/10 | 仅 50 个英文名，250 个号 99% 概率出现重名 |
| Sentinel 令牌 | ⚠️ 风险 | 5/10 | 版本号 `sv=20260219f9f6` 硬编码，过期后全部被标记 |
| 请求头 | ⚠️ 风险 | 5/10 | Accept-Language/Referer/Sec-Fetch 全部账号一致 |
| 步骤时序 | ⚠️ 风险 | 5/10 | 步骤间 0 延迟，人类通常 2-5 分钟完成注册 |
| IP/代理 | ⚠️ 风险 | 6/10 | 支持代理轮转但当前未配置，所有号同 IP |
| Cookie 管理 | ⚠️ 中等 | 7/10 | 每次新 Session 隔离好，但数据库存储模式可关联 |
| Session 隔离 | ✅ 安全 | 8/10 | 每个注册新建独立 Session |
| Device ID | ✅ 安全 | 9/10 | 服务端生成，每个账号唯一 |
| PKCE/State | ✅ 安全 | 9/10 | `secrets.token_urlsafe` 加密随机 |
| 密码生成 | ✅ 安全 | 9/10 | 12 位随机，71 bit 熵值 |

---

## 二、致命问题详解

### 2.1 OAuth 参数暴露工具身份（最危险）

**文件**: `src/core/openai/oauth.py` 约第 200 行

```python
params = {
    ...
    "codex_cli_simplified_flow": "true",  # ← 直接标识自动化工具
    "id_token_add_organizations": "true",  # ← 非标准参数
}
```

**风险**: OpenAI 只需一个查询就能找出所有自动注册的账号：
```sql
SELECT * FROM oauth_logs WHERE params LIKE '%codex_cli_simplified_flow%'
```

**修复方案**: 移除这两个参数，或者用标准 OAuth 参数替代

---

### 2.2 User-Agent 全部相同

**文件**: `src/core/http_client.py` 约第 233 行

```python
"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
             "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
```

**风险**:
- `Chrome/120.0.0.0` 不是真实版本号（真实应为 120-130 左右）
- 1000 个账号全部共享同一个 UA = 一眼看穿
- 连 Chrome 主版本号都是假的（3.1 vs 真实的 120+）

**修复方案**:
```python
USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64)...Chrome/125.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)...Chrome/124.0.0.0 Safari/537.36",
    "Mozilla/5.0 (X11; Linux x86_64)...Chrome/126.0.0.0 Safari/537.36",
    # 20+ 个真实 UA，涵盖 Windows/Mac/Linux 和不同 Chrome 版本
]
# 每个注册随机选一个
```

---

### 2.3 名字库太小

**文件**: `src/config/constants.py` 约第 195 行

```python
FIRST_NAMES = [
    "James", "John", "Robert", "Michael", "William", ...  # 仅 50 个
]
```

**风险**: 统计碰撞概率
- 250 个号 → 99% 概率有重名
- 1000 个号 → 每个名字平均出现 20 次
- OpenAI 按名字分组聚类即可发现批量注册

**修复方案**: 扩充到 5000+ 名字，包含：
- 美国 SSA 热门名字 Top 1000
- 英国/澳大利亚/加拿大英文名
- 西班牙语/阿拉伯语/中文拼音名（国际化）
- 加入姓氏（目前只有名，没有姓）

---

## 三、中等风险详解

### 3.1 步骤间无人类延迟

**当前行为**:
```
OAuth(0ms) → DeviceID(0ms) → Sentinel(0ms) → 提交表单(0ms) → 密码(0ms) → 验证码(等邮件) → 验证(0ms) → 创建账户(0ms)
```
全程 13-15 秒完成。真实人类注册大约 2-5 分钟。

**修复方案**:
```python
time.sleep(random.uniform(2, 8))   # 提交表单后"思考"
time.sleep(random.uniform(1, 4))   # 输入密码前"阅读"
time.sleep(random.uniform(3, 10))  # 收到验证码后"输入"
```

### 3.2 请求头一致性

所有账号共享：
- `Accept-Language: en-US,en;q=0.9` — 固定
- `Referer` — 硬编码完全相同
- `Sec-CH-UA` — 缺失（真实 Chrome 会发送）

### 3.3 Sentinel 版本号

```python
"referer": "https://sentinel.openai.com/...?sv=20260219f9f6",
```
该版本号硬编码，OpenAI 更新后所有请求都会被标记为使用过期版本。

---

## 四、OpenAI 可能的检测策略

```
1. 参数签名检测
   → codex_cli_simplified_flow=true → 100% 命中所有自动注册账号

2. UA 聚类
   → GROUP BY user_agent HAVING count > 10 → 全部暴露

3. 名字统计
   → 50个名字中每个出现20次 → 明显非自然分布

4. IP 聚类
   → 同IP + 短时间内 > 5个注册 → 触发限速/封禁

5. 时序分析
   → 注册全程 < 30秒 → 人类不可能这么快

6. 请求序列指纹
   → 所有账号步骤顺序完全一致 → 自动化特征
```

---

## 五、修复优先级

### P0 — 紧急（影响所有已注册账号存活）

| # | 任务 | 文件 | 工作量 |
|---|------|------|--------|
| 1 | 移除 `codex_cli_simplified_flow` 等暴露参数 | `src/core/openai/oauth.py` | 10 分钟 |
| 2 | User-Agent 随机池（20+ 真实 UA） | `src/core/http_client.py` | 30 分钟 |
| 3 | 名字库扩充到 5000+ | `src/config/constants.py` | 1 小时 |

### P1 — 重要（降低批量检测概率）

| # | 任务 | 文件 | 工作量 |
|---|------|------|--------|
| 4 | 步骤间加随机人类延迟 | `src/core/register.py` | 30 分钟 |
| 5 | 请求头随机化 (Accept-Language, Sec-CH-UA) | `src/core/http_client.py` | 30 分钟 |
| 6 | curl_cffi impersonate 版本随机 | `src/core/http_client.py` | 15 分钟 |

### P2 — 建议（进一步提升隐蔽性）

| # | 任务 | 文件 | 工作量 |
|---|------|------|--------|
| 7 | Sentinel 版本号动态获取或随机 | `src/core/register.py` | 30 分钟 |
| 8 | 代理轮转默认启用 + 警告 | `src/config/settings.py` | 15 分钟 |
| 9 | 注册间隔强制 30-60 秒 | `src/web/routes/registration.py` | 15 分钟 |

### 预估总工作量: 约 4 小时

---

## 六、做得好的地方（无需修改）

- ✅ Device ID: 服务端生成，每号唯一
- ✅ PKCE/State: `secrets.token_urlsafe` 加密随机
- ✅ Session 隔离: 每次注册新 Session
- ✅ 密码: 12位随机 `secrets.choice`
- ✅ 生日: 18-45岁合理分布
- ✅ curl_cffi TLS 指纹: 自动匹配真实 Chrome
