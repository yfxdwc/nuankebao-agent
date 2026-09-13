# 暖客宝部署修复 SOP — nuankebao.tooyang.top 修复

> **状态**: 🚨 生产故障 (v0.1.2 改名后遗留)
> **拍板来源**: 主人 2026-09-13 ask_user (key_modules_ui 拍板后, 主人反馈 "admin 里没看到 UI", 排查发现公网根本没部署)
> **影响**: `https://nuankebao.tooyang.top/*` **全部 404**, 包括 admin / login / dev / app-preview

---

## 🚨 根因 (3 个独立故障)

### 故障 1: 独立 cloudflared tunnel **从未创建**

```
主人机器 ~/.cloudflared/                ← 主理人 (lk) 的 tc-studio99 tunnel
├── config.yml                          (只路由 bip + tc.pi-web)
├── cert.pem
└── 98795a68-...json                     (token)

❌ ~/.cloudflared-nuankebao/ 不存在     (主人自己 v0.1.0 写的 tools/nuankebao-tunnel.sh 设计这个目录)
❌ /etc/systemd/system/nuankebao-cloudflared.service 不存在
❌ nuankebao-cloudflared.service 没在任何 systemctl scope
```

**原因**: v0.1.2 改名 (BBT → 暖客宝, per CHANGELOG [0.2.0] + [0.3.0]) **只改了 hostname 默认值 + docker 命名**, **没创建独立的 cloudflared tunnel + credentials + systemd unit**.

主人 `tools/nuankebao-tunnel.sh` 已经写好一键脚本, 但**从未执行过**.

### 故障 2: nuankebao-nextjs.service systemd 启动**失败 12162 次**

```
systemctl --user status nuankebao-nextjs.service:
  Active: activating (auto-restart) (Result: exit-code) since Sun 2026-09-13 07:30:52 UTC
  Process: 1016611 ExecStart=...next start -p 3003 (code=exited, status=1/FAILURE)

journalctl:
  Sep 13 07:30:52 tc node[1016611]: Error: listen EADDRINUSE: address already in use :::3003
```

**原因**: 端口 3003 被**老的 next dev 进程** (pid 398590, started Sep 12) 占用, systemd 的 `next start -p 3003` 起不来, 疯狂重启循环 (12162 次).

### 故障 3: 老的 next dev 进程**僵死/编译中**

```
ps 398590:
  node /home/tooyan/nuankebao-agent/node_modules/.bin/../next/dist/bin/next dev -p 3003 -H 0.0.0.0
  跑了 18 小时, CPU 16976%, 16GB 虚拟内存

curl localhost:3003/admin: HTTP 000 (10s 超时)
```

**原因**: Next.js dev mode 首次启动**编译慢** + 持续监听文件变化. 但这个进程占着端口, systemd 起不来.

---

## 🔧 修复步骤 (4 步, 按顺序执行)

> ⚠️ **AGENTS §3 红线**: "不要 sudo 改系统配置". agent **不直接动**主人机器.
> 主人手工执行以下步骤, 或确认后让 agent 协助.

### Step 1: 杀老 next dev 进程 (释放 3003 端口)

```bash
# 看具体进程
ps -ef | grep "next dev" | grep -v grep
# 输出: tooyan 398590 ... next dev -p 3003

# 杀
kill 398590
# 或如果 kill 不响应: kill -9 398590

# 验证端口释放
ss -tlnp | grep 3003
# 期望: 空 (无监听)
```

### Step 2: 让 systemd 接管 (nuankebao-nextjs.service)

```bash
# 看当前 systemd 状态
systemctl --user status nuankebao-nextjs.service

# 手动启动 (替代 auto-restart 循环)
systemctl --user start nuankebao-nextjs.service

# 等 5-10s
sleep 8

# 看新状态
systemctl --user status nuankebao-nextjs.service
# 期望: Active: active (running)

# 健康检查
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:3003/api/health
# 期望: HTTP 200
```

### Step 3: 创建 nuankebao 独立 cloudflared tunnel

> 主人手工 (需 Cloudflare Dashboard 操作 + scp):

**3a. Dashboard 创建 tunnel**:
```
1. 打开 https://one.dash.cloudflare.com/
2. Zero Trust → Networks → Tunnels → Create a tunnel
3. 名字: nuankebao
4. 选 "Cloudflared" → Save tunnel
5. 复制 Token JSON (e.g. 5f8a9b...json)
6. scp 5f8a9b...json mm7@<server>:/home/tooyan/.cloudflared-nuankebao/credentials.json
```

**3b. 一键脚本** (创建 cloudflared + systemd unit):

```bash
# 主人机器
cd /home/tooyan/nuankebao-agent

# 跑 nuankebao-tunnel.sh (需要 sudo 写 /etc/systemd/system/)
sudo bash tools/nuankebao-tunnel.sh
```

**脚本输出**:
```
✓ Token: /home/tooyan/.cloudflared-nuankebao/credentials.json
✓ Config: /home/tooyan/.cloudflared-nuankebao/config.yml
✓ Systemd: /etc/systemd/system/nuankebao-cloudflared.service
```

### Step 4: 配 DNS + 验证公网

```bash
# 4a. 配 DNS (用 cloudflared tunnel route dns)
CLOUDFLARED_BIN=/usr/local/bin/cloudflared
TUNNEL_ID=$(jq -r .TunnelID /home/tooyan/.cloudflared-nuankebao/credentials.json)

cd /home/tooyan/.cloudflared-nuankebao
$CLOUDFLARED_BIN tunnel route dns "$TUNNEL_ID" nuankebao.tooyang.top

# 4b. 测公网 (等 30s DNS propagate)
sleep 30
curl -s -o /dev/null -w "HTTP %{http_code}\n" --max-time 15 https://nuankebao.tooyang.top/api/health
# 期望: HTTP 200

# 4c. 浏览器访问
# https://nuankebao.tooyang.top/admin
# https://nuankebao.tooyang.top/dev                  (★ v0.1.3 新加的 3 个 dev UI)
# https://nuankebao.tooyang.top/dev/architecture     (mermaid 渲染 CHARTER §4.1)
# https://nuankebao.tooyang.top/dev/deploy           (备份健康 dashboard)
# https://nuankebao.tooyang.top/dev/snapshot         (任务快照列表)
```

---

## 🚀 一键脚本 (替代手工 4 步)

> **⚠️ 主人 review 后再执行**:
>
> `tools/fix-nuankebao-deploy.sh` 是**agent 写**, **主人手工跑**. agent 不直接执行.
> 脚本内容: 杀进程 + systemctl start + 验证健康, 但**不包含 Step 3 (Dashboard 创建 tunnel)**—— 那是主人手工.

```bash
cd /home/tooyan/nuankebao-agent
# Step 1: 杀老 next dev
bash tools/fix-nuankebao-deploy.sh kill-old-dev

# Step 2: 让 systemd 起来 + 健康检查
bash tools/fix-nuankebao-deploy.sh start-systemd

# 验证
bash tools/fix-nuankebao-deploy.sh verify
# 输出:
#   ✅ next.js on :3003
#   ❌ tunnel on nuankebao.tooyang.top (待主人手工配 tunnel)
```

---

## 📋 修复后的 dev UI 验证清单

部署修复后, 主人浏览器验证:

```
✅ https://nuankebao.tooyang.top/
✅ https://nuankebao.tooyang.top/login
✅ https://nuankebao.tooyang.top/admin
✅ https://nuankebao.tooyang.top/app-preview
✅ https://nuankebao.tooyang.top/dev                   (★ v0.1.3 新)
✅ https://nuankebao.tooyang.top/dev/architecture      (★ mermaid 渲染)
✅ https://nuankebao.tooyang.top/dev/deploy            (★ 备份 dashboard)
✅ https://nuankebao.tooyang.top/dev/snapshot          (★ 任务快照列表)
✅ https://nuankebao.tooyang.top/dev/snapshot/pre-...  (★ 详情 + rollback)
```

---

## 🔍 为什么不直接 agent 修

按 [AGENTS.md §3](../../AGENTS.md) **不该做**:

> ❌ **不要 sudo 改系统配置** — 这是 暖客宝 项目级别, 跨用户操作要找主人拍

**3 个修复步骤都涉及主人机器全局状态**:
- Step 1 (杀进程): 影响主人当前 SSH session / 任何在跑的 dev session
- Step 2 (systemctl): 影响生产 next.js
- Step 3 (cloudflared + Dashboard): 影响主人全局 Cloudflare account + DNS

**agent 职责**: 诊断 + 写 SOP + 写脚本 + 主人 review 后执行.

---

## 📚 关联文档

- [CHANGELOG.md [0.3.0] v0.1.2 改名完成](../../CHANGELOG.md) (BBT → 暖客宝, 但没配 tunnel)
- [AGENTS.md §6 命名一致性](../../AGENTS.md) (hostname 强绑定)
- [AGENTS.md §3 协作规则](../../AGENTS.md) (不要 sudo 改系统配置)
- [tools/nuankebao-tunnel.sh](../../tools/nuankebao-tunnel.sh) (主人 v0.1.0 写的一键脚本, 从未跑)
- [tools/tunnel-status.sh](../../tools/tunnel-status.sh) (主人 v0.1.0 写的状态检查)
- [tools/setup-tunnel.sh](../../tools/setup-tunnel.sh) (主人 v0.1.0 写的另一种 tunnel 开通工具)
- [deploy/paths.conf](../../deploy/paths.conf) (主人当前机器 path 配置)

---

## ⏱️ 修复时间预估

- **Step 1-2** (杀进程 + systemctl): 1 分钟
- **Step 3** (创建 tunnel + scp + 跑脚本): 5-10 分钟 (Dashboard 操作 + 等 token)
- **Step 4** (DNS + 公网验证): 5 分钟 (DNS propagate 30s)

**总计**: 10-15 分钟 (主人手工)

---

## 🚦 当前状态

- ❌ https://nuankebao.tooyang.top/admin — 404 (cloudflared 没路由)
- ❌ https://nuankebao.tooyang.top/dev — 404
- ✅ http://localhost:3003/admin — **理论上能工作**, 但 next dev 僵死, systemd EADDRINUSE 抢端口
- ⚠️ http://localhost:3003/dev — 路径存在源码, 但 next dev / systemd 都不可用

**修复后预期**:
- ✅ https://nuankebao.tooyang.top/* 全部 200
- ✅ next.js 生产模式跑 (systemd 接管)
- ✅ dev UI 在公网可访问

---

**主理人 (主人) review 后, 按 Step 1-4 顺序执行. 任何步骤卡住, 重新跑 `tools/fix-nuankebao-deploy.sh verify` 看诊断输出.**
