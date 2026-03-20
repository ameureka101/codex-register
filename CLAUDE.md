# codex-register 项目记忆

## 项目架构
- codex-register: OpenAI 账号自动注册系统，位于 ~/Desktop/codex-register
- GCP VM: codex-register 运行在 34.187.162.3:8000，systemd 服务，venv 在 /home/amerlin/codex-register/.venv
- VM 登录密码: Codex2026!Reg#Secure

## Git 仓库
- origin: git@github.com:ameureka101/codex-register.git (用户 fork)
- upstream: https://github.com/cnlimiter/codex-manager.git (上游源)
- 同步脚本: scripts/sync-upstream.sh
- 合并冲突时保留我们的 temp_mail.py JWT 降级逻辑

## 已部署自建邮箱服务 (cloudflare_temp_email)
- Cloudflare 账号: ameureka@webmail.spobcollege.edu
- Account ID: e08ccf48bda30edaeb5b89a399bb41cf
- API Token: cfut_bIKBONyLBXyDneIE2Dh4ycsMcwMLccddGW5d9wm6a2617efe
- Global API Key: ebf079b1b341e687df22c2608944dae7ea073

### 域名1: ppthub.shop (服务ID:2, priority:0)
- Zone ID: a3132bfec0c821e9aa59309f06928369
- Worker: temp-email-ppthub, 前端: gomail.ppthub.shop
- Admin密码: _lRwMnoL3vO6_INfMPZVFQ, 站点密码: ppthub2026

### 域名2: guochunlin.com (服务ID:3, priority:1)
- Zone ID: 11e24c8b9e845f706a798b48dc01fc7b
- Worker: temp-email-guochunlin, 前端: gomail.guochunlin.com
- Admin密码: en5ysQdFsUhvhG7BoSGxlA, 站点密码: guochunlin2026

## 部署文档
- 实战手册: _多域名多邮件服务/cloudflare-email-deployment-runbook.md
- 同步工作流: _多域名多邮件服务/upstream-sync-workflow.md
- 部署时 wrangler.toml 需含 [assets] + PASSWORDS + site_password
- codex-register 服务配置需加 site_password 字段

## ⚠️ 待办: 反指纹/防封禁优化 (重要但未修复)
分析评分 4.9/10 (D级)，以下问题需修复:
1. 【紧急】OAuth参数 codex_cli_simplified_flow=true 直接暴露工具身份
2. 【紧急】User-Agent 硬编码 Chrome/120.0.0.0，所有账号完全相同
3. 【紧急】名字库仅50个，250个号99%概率重名
4. 【重要】步骤间无人类延迟，全程0延迟机器人特征
5. 【重要】请求头(Accept-Language/Sec-CH-UA等)全部相同
6. 【建议】Sentinel版本号 sv=20260219f9f6 硬编码过期风险

## 待部署域名
- 还有4个域名待部署自建邮箱 (共6个，已完成2个)
- 部署脚本: scripts/deploy-cf-email.sh, scripts/register-email-service.sh
