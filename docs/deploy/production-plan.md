# 生产部署方案 —— 腾讯云服务器（500 用户）

> **状态**: 待主人 review（2026-09-19，plan-first）
> **执行原则**: 本方案确认后再动手；**dev（tc 机器）全程保持运行，一行不改**
> **关联**: [`docs/deploy.md`](../deploy.md)（通用部署手册）、[ADR-0008](../adr/0008-apk-web-domain-spec.md)（双域）、`AGENTS.md §4.5`
> **拍板来源**: 主人 2026-09-19 ask_user 六项回答（见 §0）

---

## 0. 已拍板决策（2026-09-19）

| 项 | 决定 |
|---|---|
| 生产端位置 | **腾讯云服务器**（非 tc） |
| 域名 | 生产 = `nuankebao.tooyang.top`；dev = `nuankebao-dev.tooyang.top`（新增） |
| 数据 | **生产空库启动**（不迁移 dev 的 61 客户 / 35 养生记录） |
| 登录 | **真实手机验证码**（供应商待定，见 §8） |
| APK | **正式 release keystore** |
| 实施 | **先出方案（本文档）**，主人 review 后按 §6 分阶段实施 |

---

## 1. 先回答主人的三个问题

### 1.1 500 用户需要多大配置？

**负载推导**（按 500 注册用户、50% DAU、10% 峰值并发估算）：

| 维度 | 估算 | 说明 |
|---|---|---|
| API 请求 | 3–5 万/天，平均 <1 QPS，峰值 5–15 QPS | Flutter 走 JSON API，单请求极小 |
| 数据库 | 1 年 < 5–10 GB（含审计日志） | 客户 ~10 万行级、养生记录 ~45 万条/年 |
| 照片 | 0.3–0.5 GB/天 → 10–15 GB/月 → 120–180 GB/年 | 增长最快的部分，决定磁盘选型 |
| 内存 | Next.js 0.3–0.6 GB + PG 0.5–1 GB + OS/Docker 0.5 GB | 4 GB 能跑，8 GB 从容（含 Docker 构建） |

**推荐配置**：

| 档位 | 配置 | 适用场景 | 说明 |
|---|---|---|---|
| ✅ 推荐 | **4 vCPU / 8 GB / 200 GB SSD**，带宽按流量计费（或 10 Mbps） | 500 用户正式 | 照片放本盘也可撑约 1 年；Docker 构建不憋屈 |
| 最低 | 2 vCPU / 4 GB / 100 GB | 内测 / 前 100 用户 | 可用，但构建慢、照片增长需尽早接 COS |
| 机型 | **轻量应用服务器**（Lighthouse）4C8G | 起步首选 | 便宜、含流量包、备案规则与 CVM 相同 |
| 机型（备选） | CVM 4C8G | 以后要灵活扩盘/更细云监控 | 贵一些 |

**带宽**：日常均值 < 5 Mbps，照片批量上传时突发 20–50 Mbps。建议 **按流量计费**（大陆约 ¥0.8/GB；按 30–50 GB/月 ≈ ¥25–40），或固定 10 Mbps；轻量套餐自带月流量包基本够用。

**磁盘/存储**：照片是最快增长项。本盘 200 GB 约撑 1 年；**推荐下一阶段接 COS**（应用侧 S3 兼容改造，`.env` 已预留 `S3_*` 变量，属 Phase 2 工作）。

### 1.2 网络：腾讯云 vs 自有服务器，是否更简单？

| 维度 | 腾讯云大陆区 | 腾讯云香港/海外区 | 自有服务器（现状 tc + CF Tunnel） |
|---|---|---|---|
| 公网可达 | 固定公网 IP、稳定带宽 | 同左 | 依赖家宽 + Cloudflare Tunnel（已跑通） |
| **备案** | ❌ **必须 ICP 备案**（2–4 周） | ✅ 免备案 | ✅ 免备案（Cloudflare 隧道出站） |
| 大陆访问速度 | 最优 | 跨境延迟/抖动 | 取决于家宽上行 + CF 线路，一般 |
| 稳定性 | 有 SLA、云监控/快照/告警 | 同左 | 断电/断网/家宽故障 = 全挂 |
| 短信签名审核 | 材料更齐，最顺 | 需其他资质证明 | 需其他资质证明 |
| 数据位置 | 境内（合规友好） | ⚠️ 境外（健康数据出境，违背"不放第三方云"精神） | 境内（主人自有） |
| 成本 | 中（¥150–300/月） | 低-中（¥80–200/月） | 机器已有，但隐性运维成本高 |

**结论**：腾讯云大陆区 + ICP 备案最符合"500 用户正式生产 + 健康数据合规"。备案是唯一的大门槛，建议**与 P1–P3 实施并行推进**（备案期间用香港临时节点或 tc 内测均可过渡）。

**ICP 备案要点**（腾讯云代提交）：
- 材料：主体证件（个人身份证 / 企业营业执照）、已实名域名、服务器实例（购买 ≥ 3 个月）、真实性核验（腾讯云 App 人脸/幕布）
- 周期：腾讯云初审 1–2 工作日 + 管局 5–20 工作日
- 备案期间域名不能对大陆 IP 提供 80/443 服务（腾讯云会拦截）；SSH 等其他端口不受影响
- 备案通过后：可领腾讯云免费 SSL 证书，短信签名审核也更容易过

### 1.3 真实手机验证：云上是否更简单？

**短信与服务器位置无关** —— 都是调第三方网关 API。真正的门槛是**签名 + 模板审核**：

| 供应商 | 所需材料 | 审核时长 | 备注 |
|---|---|---|---|
| 阿里云短信 | 实名账号 → 短信签名（需 已备案网站 / APP / 公众号 / 小程序 之一作证明）→ 验证码模板 | 1–3 工作日 | 代码里已预留 `ALIYUN_SMS_*` 变量 |
| 腾讯云短信 | 实名账号 → 签名（需已备案域名 / APP / 公众号）→ 模板 | 1–3 工作日 | 与服务器同账号，控制台/告警更顺 |

云上略顺的点：备案通过后证明材料齐全；但短信本身不难，**资质审核才是关键路径**（可与开发并行）。

**代码现状（缺口，详见 §3.B）**：
- 没有"发送验证码"接口；验证码生成/存储/校验链路不存在
- Auth.js `authorize()` 仍是 W1 桩：**任意手机号 + `123456` → 都登成用户 1**
- Flutter 登录页"发送验证码"是假按钮（弹提示 `123456`）
- `.env.local` 中 `ALIYUN_SMS_ACCESS_KEY/SECRET_KEY` 为空（签名/模板字段有值）

**工作量**：后端 ~1 天 + Flutter ~0.5 天 + 资质审核 1–3 天（并行）。

---

## 2. 目标架构

```
销售手机（Flutter APK，release 签名）
  API base = https://nuankebao.tooyang.top/api
        │ HTTPS
        ▼
┌─ 腾讯云服务器（4C8G，大陆区）──────────────────────────────┐
│  nginx :443（TLS：Let's Encrypt / 腾讯免费证书）            │
│    └─ nuankebao-web（Next.js standalone，Docker，127.0.0.1:3000）
│         ├─ /api/*            共享后端（Flutter + web 都走这里）
│         ├─ /admin            主人管理（冻结中，可用）
│         ├─ /download         APK 分发页
│         └─ /app-preview      ⚠️ 生产关闭（环境开关，见 §3.A）
│    └─ nuankebao-postgres（Docker，仅内网，named volume）
│         └─ 备份链路：pg_dump 加密 → COS + 云硬盘快照 +（可选）异地 lk
└────────────────────────────────────────────────────────────┘

┌─ tc（开发机，保持现状，仅入口改名）─────────────────────────┐
│  cloudflared: nuankebao-dev.tooyang.top → next dev :3003   │
│               /dev-app                  → Flutter dev :8181│
│  Postgres dev :5432 / 备份 timer / 预览 全部不动             │
└────────────────────────────────────────────────────────────┘
```

说明：
- 生产**不用 cloudflared**：大陆直连 + 备案域名/证书更稳；dev 继续走 CF 隧道没问题。
- 生产 DB 只在 Docker 内网，不对公网暴露 5432。
- dev 与 prod **数据、备份、域名、容器完全隔离**。

---

## 3. 上线前代码/配置缺口（工作包）

### A. 生产栈修复（当前是坏的）

| # | 问题 | 现状 | 修法 |
|---|---|---|---|
| A1 | Docker 构建失败 | builder 阶段 `pnpm build` 报 `packages field missing or empty`（`pnpm-workspace.yaml` 缺 `packages`，pnpm@9 当 workspace 处理） | 补 `packages: ["."]`（或删掉该文件） |
| A2 | `docker-compose.prod.yml` 不完整 | web 无 host 端口、无 `env_file`、**uploads 无持久化卷**、缺 migration runner | 补 `127.0.0.1:3000:3000`、`env_file: .env.prod`、`./data/uploads:/app/public/uploads`、新增 `migrate` service（profile tools） |
| A3 | migration 跑不了 | runner 镜像只有 standalone 产物，没有 `tsx`/`drizzle/`/`tools/`；`migrate.ts` 还会调 `tools/check-migration-compat.sh`（需要 bash） | Dockerfile 加 `migrate` stage（含 bash + 全仓 + node_modules），compose 用 `docker compose run --rm migrate pnpm db:migrate` |
| A4 | `docker/nginx.conf` 过时 | 上游名 `bbt_web`、`/opt/bbt/...` 路径 | 改为 host nginx（推荐，证书管理简单）或重写容器 nginx 配置 |
| A5 | tc 上 `nuankebao-stack.service` 危险残留 | 用 **dev compose** 起生产栈，撞 5432/3003/容器名，且正在失败重启循环（每 30s 重试） | **立即停用**（主人 sudo，见 §6 P0）；腾讯云上改用正确的 prod unit |
| A6 | 生产关闭 dev 工具路由 | `/app-preview`、`/preview`、`flutter-login`（代码已 404） | 加 `APP_PREVIEW_ENABLED` 类开关，production 默认关 |
| A7 | `key.properties` / `*.jks` 未 gitignore | 见 §3.D | 补 `.gitignore` |

### B. 登录改造（真实短信，最大工作包）

| # | 工作 | 说明 |
|---|---|---|
| B1 | 新表 `verification_code` | `phone_hash / code_hash / expires_at / attempts / created_at`；走 drizzle migration + `db:compat` + `down.sql` |
| B2 | `POST /api/auth/send-code` | 6 位数字、5 分钟有效、单号 1 次/分钟 + 10 次/天、IP 限流（复用 `src/lib/rate-limit.ts`） |
| B3 | SMS adapter | 新增 `src/lib/sms/`（阿里云或腾讯云），生产走真实短信；dev 模式打日志/返回提示 |
| B4 | Auth.js 真实校验 | `authorize()` 查 `phone_hash` + 校验码 + `is_active`，返回**真实 user.id**；删掉 W1 桩 |
| B5 | ⚠️ Auth.js Edge/Node 拆分 | 现状 `middleware.ts` 直接 import `@/lib/auth`；`authorize()` 引 DB 有已知 Edge 500 风险（CHANGELOG 2026-09-18 实测回滚过）。按 Auth.js v5 标准模式拆 `auth.config.ts`（edge 安全，给 middleware）+ `auth.ts`（Node，带 DB provider） |
| B6 | Flutter 登录页 | `_sendCode()` 调真实接口；native 登录仍走 Auth.js callback，无需改协议 |
| B7 | 用户开通脚本 | `scripts/import-users.ts`：CSV（姓名/手机号/角色）→ 加密 + hash → 幂等导入；**邀请制，不做自助注册**（web admin 冻结 ≤ 不新增注册 UI） |
| B8 | 生产 env 安全 | ⚠️ 实测 `DEV_SKIP_AUTH` 目前**不受 NODE_ENV 保护**（`skip-auth.ts` 只认变量值）。生产 `.env.prod` 严禁出现 `DEV_SKIP_AUTH` / `DEV_LOGIN_ANY_USER`，并顺手加 NODE_ENV 硬门闸 |

### C. 备份与监控（与 dev 隔离）

| # | 工作 | 说明 |
|---|---|---|
| C1 | prod 备份 profile | `deploy/backup.sh` 目前硬编码 dev 容器/路径。加 profile 参数（`deploy/paths.prod.conf` 或 `NUANKEBAO_PROFILE=prod`），独立目录/GPG 键/COS/异地，不覆盖 dev 备份 |
| C2 | 加密后上传 | `pg_dump -Fc` → GPG → COS（`rclone`/`coscli`）；media/uploads 同样 tar+zst+加密 → COS |
| C3 | 云硬盘快照 | 控制台设：1 天 1 次，保留 7–14 天（整机级兜底） |
| C4 | 健康检查 | 服务器 systemd timer：`curl /api/health` 失败告警 + 自动 restart web；腾讯云监控告警（CPU/内存/磁盘/存活）→ 微信 |
| C5 | 恢复演练 | 月度：解密备份 → 临时 PG → 行数比对（复用 `deploy/restore_verify.sh` 思路） |
| C6 | 异地副本 | 可选：每日从腾讯云拉回 tc/lk（或 COS 跨地域复制） |

### D. APK 正式签名与分发

| # | 工作 | 说明 |
|---|---|---|
| D1 | 生成 release keystore | `keytool -genkeypair -keyalg RSA -keysize 2048 -validity 10000`；口令主人设置 |
| D2 | 保管 | keystore 不进 git：口令管理器 + `/home/tooyan/nuankebao-databackups/`（tc）+ 云上私有 COS；`.gitignore` 补 `key.properties` / `*.jks` |
| D3 | gradle 改造 | `android/app/build.gradle` 读 `key.properties`，release 用正式签名（当前是 debug keys） |
| D4 | 构建与分发 | `flutter build apk --release --dart-define=NUANKEBAO_API_BASE=https://nuankebao.tooyang.top/api` → 上传生产服务器 `public/downloads/nuankebao-vX.Y.Z.apk` → `/download` 页 + 二维码；**保留最近 2–3 个版本**供回滚 |

### E. 部署脚本与 secrets

| # | 工作 | 说明 |
|---|---|---|
| E1 | `.env.prod` 模板 | 新 `POSTGRES_PASSWORD` / `AUTH_SECRET` / `PGCRYPTO_KEY`（空库 = 全新密钥，不复用 dev）；`AUTH_URL=https://nuankebao.tooyang.top`；SMS/AI 密钥；**不含**任何 dev 开关 |
| E2 | `deploy/prod-deploy.sh` | 一键：拉码 → 备份 → build → migrate → up → 健康检查 → 失败回滚（保留上一镜像 tag） |
| E3 | systemd unit | 服务器上 `nuankebao-stack.service`（`-p nuankebao -f docker-compose.prod.yml --env-file .env.prod`）；容器自带 `restart: always` |
| E4 | 首部署 SOP | 与 `docs/deploy.md` §2 对齐，补齐实际脚本名（`deploy/backup.sh`，不是 `tools/backup.sh`） |

---

## 4. 域名与切换

**切换顺序（先 dev 后 prod，随时可回滚）**：

1. 新增 DNS `nuankebao-dev.tooyang.top` → tc（Cloudflare）→ 更新 tc tunnel ingress → dev 入口就位
2. `AUTH_URL`（tc dev）同步改为 `https://nuankebao-dev.tooyang.top`；旧 LAN 访问继续可用
3. 腾讯云生产就绪（备案 + 证书 + 健康检查通过）
4. `nuankebao.tooyang.top` 解析切到腾讯云 IP（生产）
5. APK 用生产域名构建、分发（新装用户天然对新域名）

**强绑定三件套（AGENTS §6.3，改一个必须同步改）**：
```
[hostname] nuankebao.tooyang.top
    ↕ AUTH_URL（prod .env.prod）
    ↕ APK dart-define NUANKEBAO_API_BASE
```

**回滚**：tc cloudflared 路由保留；极端情况把 `nuankebao.tooyang.top` DNS 指回 tc 即可（dev 数据独立，生产库不受影响）。

---

## 5. 安全基线

- 安全组：443 对公网；22 仅主人 IP；**不开** 5432 / 3000
- SSH 仅密钥登录，禁密码
- TLS：Let's Encrypt（certbot）或腾讯云免费证书；强制 HTTPS
- 登录：短信验证码 + 限流；生产禁用 dev 开关（§3.B8）
- 密钥：`.env.prod` chmod 600，不进 git；keystore 双备份
- 数据：健康数据只落主人租用的云服务器（IaaS），不用第三方 SaaS；**避免海外区**（出境风险）
- 审计/备份：现有 audit 触发器 + 加密备份链（+ 云快照）

---

## 6. 实施阶段与验收

| 阶段 | 内容 | 验收 | 预估 |
|---|---|---|---|
| **P0 云资源/资质** | 购买服务器、安全组、域名；**停用 tc 的 stack unit**；启动备案；申请短信签名/模板 | 服务器可 SSH；备案/短信提交成功 | 0.5 天（备案等 2–4 周，并行） |
| **P1 代码修复** | §3.A 全部（Docker build / compose / migrate / nginx / 开关）+ `prod-deploy.sh` | `docker build` 本地通过；本地容器连测试库 `/api/health` 200 | 1–2 天 |
| **P2 登录落地** | §3.B 全部（表/接口/SMS/adapter/auth 拆分/Flutter/导入脚本） | 真实短信登录；两个不同手机号 = 两个不同身份；限流生效 | 2–3 天 |
| **P3 首部署+备份监控** | §3.C/E：空库 migrate + seed、web 起、nginx/TLS、快照/备份/健康检查 | 公网 `/api/health` 200；第一份加密备份生成；恢复演练通过 | 1 天 |
| **P4 APK 签名发布** | §3.D：keystore、gradle、构建、上传、`/download` | 真机安装 release APK → 登录 → 录入一条养生记录 | 0.5 天 |
| **P5 切换+内测** | §4 域名切换；`nuankebao-dev` 就位；邀请 1–2 销售 | 销售日常可用；dev 预览不受影响 | 0.5 天 + 内测周期 |

**开工到可内测 ≈ 4–6 个工作日**（备案另计 2–4 周；备案期间可用 tc/香港过渡内测）。

---

## 7. 费用粗算（以腾讯云控制台实时价为准）

| 项 | 估算 |
|---|---|
| 轻量 4C8G（大陆，含流量包） | ¥150–300/月（新购促销波动大） |
| 轻量 4C8G（香港/海外） | ¥80–200/月 |
| CVM 4C8G（大陆） | ¥300–400/月 |
| 云硬盘快照 + COS 存储 | ¥30–80/月 |
| 短信（500 人 × 2 条/天 × ¥0.045） | ≈ ¥45/月（内测期远低于此） |
| **合计** | **大陆 ≈ ¥250–450/月；海外 ≈ ¥150–300/月** |

---

## 8. 待主人拍板（实施前需要）

1. **备案路线**：A 大陆区 + ICP 备案（推荐） / B 香港·海外区免备案（快，但数据出境 + 跨境延迟） / C 其他
2. **短信供应商**：A 阿里云（代码占位已有） / B 腾讯云（同厂生态） / C 稍后再定
3. **用户开通方式**：A 邀请制 CSV 脚本导入（推荐，符合 web admin 冻结） / B 自助注册（需新增注册流程）
4. **照片/文件存储**：A 先本盘 200 GB，内测后再迁 COS（推荐） / B 一步到位接 COS
5. **配置档位**：A 4C8G（推荐） / B 2C4G（省钱，需盯磁盘） / C 其他

---

## 9. 验收清单（DoD）

- [ ] 生产服务器：Docker + compose + nginx/TLS + 安全组就绪
- [ ] 生产库：migrate + seed 完成，审计触发器生效
- [ ] 登录：真实短信、每用户独立身份、限流与失败重试可用
- [ ] APK：release 签名、指向生产域名、`/download` 可下载
- [ ] 备份：每日加密备份 + 云快照 + 异地副本；**恢复演练 ≥ 1 次**
- [ ] 监控：健康检查 timer + 云监控告警可用
- [ ] 域名：`nuankebao.tooyang.top` → 生产；`nuankebao-dev.tooyang.top` → tc dev
- [ ] dev 机器验收：`next dev` / Flutter 预览 / dev 备份 全部未受影响
- [ ] tc 上 `nuankebao-stack.service` 已停用（消除误撞 dev 的风险）

---

## 10. 关联文档

- [`docs/deploy.md`](../deploy.md) — 通用部署手册（Nginx/certbot/升级/回滚）
- [ADR-0008](../adr/0008-apk-web-domain-spec.md) — APK 域 / WEB 域
- [AGENTS.md §6.3](../../AGENTS.md) — hostname / AUTH_URL / APK base 强绑定
- [`docs/security-compliance.md`](../security-compliance.md) — 加密与合规
- [`deploy/README.md`](../../deploy/README.md) — 备份栈（dev 现状，prod 参考）
