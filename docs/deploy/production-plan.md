# 生产部署方案 v2 —— tc 本机 Docker 隔离（Phase 1）

> **状态**: 待主人 review（2026-09-19，plan-first）
> **执行原则**: 本方案确认后再动手；**dev（tc 上的 `next dev` / dev 库 / Flutter 预览）全程保持运行**
> **v2 变更**（2026-09-19 主人指示）: 生产位置回到 **tc 本机 Docker 隔离**（腾讯云降为后续迁移参考）；登录从"手机+短信"改为**账号+密码（邀请制）**；立即停用了危险的 `nuankebao-stack.service`
> **关联**: [`docs/deploy.md`](../deploy.md)、[ADR-0008](../adr/0008-apk-web-domain-spec.md)、`AGENTS.md §4.5`/`§6.3`

---

## 0. 拍板汇总

| 项 | 决定 | 来源 |
|---|---|---|
| 生产位置（Phase 1） | **tc 本机 Docker 隔离**；dev 不动 | 主人 2026-09-19 |
| 生产位置（后续） | 腾讯云迁移 = 附录 A（Phase 1 稳定后再评估） | 同上 |
| 域名 | 生产 `nuankebao.tooyang.top` → prod web :3004；dev `nuankebao-dev.tooyang.top` → dev :3003 | 主人 2026-09-19 |
| 数据 | **生产空库启动**（不迁 dev 的 61 客户 / 35 养生记录） | 主人 2026-09-19 |
| 登录 | **账号 + 密码**，邀请制（不开放自助注册） | 主人 2026-09-19 |
| 系统管理员 | `tooyan`（初始口令由主人提供，**不写入 git**；建议首登后改密） | 主人 2026-09-19 |
| 照片/文件 | **本盘**（Docker 卷持久化；后续可迁 COS） | 主人 2026-09-19 |
| APK | 正式 release keystore | 主人 2026-09-19 |
| 实施方式 | 先方案、主人确认后按 §6 分阶段实施 | 主人 2026-09-19 |
| 就地已办 | ✅ `nuankebao-stack.service` 已 stop + disable + reset-failed（消除误撞 dev 库风险） | 本次 |

---

## 1. 两个关键选择说明

### 1.1 账号+密码登录 —— 比短信简单多少？

**结论：明显更简单**（工作量从 ~2–3 天降到 ~1 天，且无外部资质依赖）：

| 对比项 | 手机+短信 | 账号+密码（采纳） |
|---|---|---|
| 外部依赖 | 短信平台资质：签名 + 模板审核（1–3 工作日）、按条计费 | 无 |
| 后端工作 | `verification_code` 表 + 发码接口 + SMS adapter + 限流 | `password_hash` 列 + 校验 + 限流（复用现有 `src/lib/rate-limit.ts`） |
| 前端工作 | "发送验证码"按钮 + 倒计时 + 双接口 | 密码输入框（去掉验证码逻辑） |
| 忘记密码 | 短信重置 | 管理员重置（邀请制场景足够） |
| 安全要求 | 码有效期/防撞库 | 密码哈希存储 + 防爆破 + 传输 HTTPS |
| 成本 | ~¥45/月（500 人） | 0 |

**安全设计**（实现时按此落）：
- 密码用 **Node 内置 `crypto.scrypt`** 加盐哈希（`scrypt$salt$hash`），不新增依赖、不存明文
- 登录失败统一提示（不区分账号不存在/密码错），失败限流（防爆破）
- 邀请制：管理员建号 → 给初始密码 → 建议首登后修改（自助改密入口做进"我的"页，工作量 ~0.5h）
- 密码强度校验（长度 ≥ 8，含字母+数字）

⚠️ 主人对话里给出的 `tooyan` 口令不会写进仓库：建档时通过环境变量一次性传入，只落库哈希。因口令已出现在聊天记录里，建议首次登录后更换。

### 1.2 为什么先 tc 本机 Docker 隔离（而不是直接上云）

- tc 已有资源（6 核 / 15 GB / 65 GB 空闲），500 用户负载完全 hold 住（推导见附录 A.1）
- 零新增成本、零备案等待，内测最快
- **dev 与 prod 完全隔离**：独立 compose 项目、独立数据卷、独立端口、独立容器名、独立备份目录
- 后续要上云时，同一套 `docker-compose.prod.yml` + dump/restore 即可整体搬迁（附录 A）

---

## 2. 目标架构（tc 双栈隔离）

```
┌─ tc 机器 ──────────────────────────────────────────────────────────┐
│                                                                     │
│  ── dev（保持现状，一行不改）────────────────────────────────────  │
│    nuankebao-nextjs.service : next dev :3003                        │
│    nuankebao-postgres（docker, 手工 run）: :5432, 卷 nuankebao-postgres-data
│    Flutter dev :8080 + dev-app-proxy :8181                          │
│    每日备份 timer（deploy/backup.sh）→ GPG → lk 异地                 │
│                                                                     │
│  ── prod（新增，Docker 隔离）────────────────────────────────────  │
│    compose project: -p nuankebao-prod -f docker-compose.prod.yml    │
│      ├─ nuankebao-prod-postgres（不映射 host 端口）                  │
│      │    卷 nuankebao-prod-postgres-data                            │
│      └─ nuankebao-prod-web（Next.js standalone, 127.0.0.1:3004）     │
│            └─ uploads 卷: ./data/prod/uploads                       │
│    生产备份 → 独立目录 + 独立 timer（不覆盖 dev 备份）                │
│                                                                     │
│  ── 公网入口（cloudflared-tc-prod.service）───────────────────────  │
│    nuankebao.tooyang.top      → prod :3004   （销售 / APK）          │
│    nuankebao-dev.tooyang.top  → dev  :3003   （主人开发预览）        │
│    /dev-app*                  → Flutter dev :8181                    │
└─────────────────────────────────────────────────────────────────────┘
```

**端口/资源规划**（3004 已跑 `tools/check-port.sh` 确认为空闲）：

| 资源 | dev（保持） | prod（新增） |
|---|---|---|
| Web | `next dev` :3003 | `nuankebao-prod-web` → 127.0.0.1:**3004** |
| Postgres | `nuankebao-postgres` :5432 | `nuankebao-prod-postgres` 仅容器内网 |
| 数据卷 | `nuankebao-postgres-data` | `nuankebao-prod-postgres-data` |
| 上传目录 | `public/uploads` | `./data/prod/uploads`（卷挂进容器） |
| 备份 | `nuankebao-databackups/`（现有 GFS） | `nuankebao-databackups/prod/`（独立） |

> `docker-compose.prod.yml` 现有的容器名/卷名（`nuankebao-postgres` 等）与 dev 冲突，**必须重命名**（A2）。

---

## 3. 工作包（实施清单）

### A. 生产栈（当前是坏的，先修）

| # | 问题 | 修法 |
|---|---|---|
| A1 | Docker 构建失败：builder 阶段 `pnpm build` 报 `packages field missing or empty` | `pnpm-workspace.yaml` 补 `packages: ["."]` |
| A2 | prod compose 不完整且与 dev 撞名 | 容器/卷改名 `nuankebao-prod-*`；web 加 `127.0.0.1:3004:3000`；`env_file: .env.prod`；uploads 卷；去掉不需要的 nginx 容器（tc 由 cloudflared 反代） |
| A3 | migration 跑不了 | Dockerfile 加 `migrate` stage（含 bash + `tools/check-migration-compat.sh` + drizzle + node_modules）；compose 加 `migrate` service（profile tools）；`docker compose run --rm migrate pnpm db:migrate` |
| A4 | `docker/nginx.conf` 过时（`bbt_web`、`/opt/bbt`） | tc 不需要容器 nginx；文件保留给未来迁移服务器时重写（附录 A） |
| A5 | ~~tc 上 stack unit 用错 compose~~ | ✅ 已停用（本次） |
| A6 | 生产关闭 dev 工具路由 | `/app-preview`、`/preview` 加环境开关，production 默认 404/redirect |
| A7 | `.gitignore` 缺 keystore | 补 `key.properties`、`*.jks` |

### B. 账号密码登录

| # | 工作 | 说明 |
|---|---|---|
| B1 | migration `0010_user_credentials` | `user` 表加 `username text` + `password_hash text`（可空 = 向后兼容）；`username` 唯一索引；配 `down.sql`，跑 `pnpm db:compat` |
| B2 | 密码哈希工具 | `src/lib/auth/password.ts`：scrypt 哈希/校验（`timingSafeEqual`），无新依赖 |
| B3 | Auth.js 真实校验 | `authorize()` 支持 `username` 或 `phone` + `password`；查 active 用户；返回**真实 user.id**；删除 W1 桩 |
| B4 | ⚠️ Auth.js Edge/Node 拆分 | `middleware.ts` 目前直接 import 带 DB 的 auth（有 Edge 500 前科）。按 Auth.js v5 标准拆 `auth.config.ts`（edge 安全）+ `auth.ts`（Node） |
| B5 | 登录限流 | 复用 `src/lib/rate-limit.ts`：每账号/IP 失败限速；统一错误文案 |
| B6 | Flutter 登录页 | 验证码输入改为密码输入（去掉"发送验证码"）；`AuthService.login(username/phone, password)`；web dev 预览的 `flutter-login`（dev-only）同步改为密码校验 |
| B7 | 管理员建档 | `scripts/create-admin.ts`：读 `ADMIN_USERNAME`/`ADMIN_PASSWORD` 环境变量，scrypt 哈希后 upsert —— 用于创建 `tooyan`；**口令不落 git** |
| B8 | 邀请制导入 | `scripts/import-users.ts`：CSV（姓名/手机号/角色/初始密码）幂等导入；不生成初始密码时随机生成并只打印一次，由主人分发 |
| B9 | 自助改密（推荐） | `PATCH /api/me/password` + Flutter「我的 → 修改密码」；否则改密只能找管理员 |
| B10 | 生产 env 安全 | 实测 `DEV_SKIP_AUTH` 目前**不受 NODE_ENV 保护**（`skip-auth.ts` 只认变量值）。生产 `.env.prod` 严禁出现该变量，并顺手加 NODE_ENV 硬门闸 |

### C. 生产备份与监控（与 dev 隔离）

| # | 工作 | 说明 |
|---|---|---|
| C1 | 备份 profile | `deploy/backup.sh` 目前硬编码 dev 容器。加 profile 参数（`paths.prod.conf`）：容器 `nuankebao-prod-postgres`、媒体 `data/prod/uploads`、目录 `nuankebao-databackups/prod/`、异地 `lk:.../nuankebao-prod/` |
| C2 | 独立 timer | 新增 `nuankebao-prod-backup.service/timer`（03:30，避开 dev 03:00） |
| C3 | 健康检查 | `nuankebao-prod-healthcheck.timer`：curl `127.0.0.1:3004/api/health`，失败自动 restart web + 记日志 |
| C4 | 恢复演练 | 月度：解密备份 → 临时 PG → 行数比对（复用 `deploy/restore_verify.sh` 思路） |

### D. APK 正式签名与分发

| # | 工作 | 说明 |
|---|---|---|
| D1 | 生成 release keystore | `keytool -genkeypair -keyalg RSA -keysize 2048 -validity 10000`；口令主人设置 |
| D2 | 保管 | keystore 不进 git：口令管理器 + `nuankebao-databackups/` + 云盘副本；`.gitignore` 补 `key.properties`/`*.jks` |
| D3 | gradle 改造 | `android/app/build.gradle` 读 `key.properties`，release 用正式签名（当前 debug keys） |
| D4 | 构建分发 | `flutter build apk --release --dart-define=NUANKEBAO_API_BASE=https://nuankebao.tooyang.top/api` → 上传 prod `public/downloads/` → `/download` 页 + 二维码；保留最近 2–3 版回滚 |

### E. 部署脚本与 secrets

| # | 工作 | 说明 |
|---|---|---|
| E1 | `.env.prod` | 新 `POSTGRES_PASSWORD` / `AUTH_SECRET` / `PGCRYPTO_KEY`（空库用全新密钥，不复用 dev）；`AUTH_URL=https://nuankebao.tooyang.top`；**不含任何 dev 开关**；chmod 600 |
| E2 | `deploy/prod-deploy.sh` | 拉码 → 备份 → build → migrate → up → 健康检查 → 失败回滚（保留上一镜像 tag） |
| E3 | systemd unit | 新的 `nuankebao-prod-stack.service`（`-p nuankebao-prod -f docker-compose.prod.yml --env-file .env.prod`）；容器自带 `restart: always` |
| E4 | 首次部署 SOP | 对齐 `docs/deploy.md`，修正过期脚本名（`deploy/backup.sh`，非 `tools/backup.sh`） |

---

## 4. 域名与切换

**切换顺序（先 dev 后 prod，随时可回滚）**：

1. **加 dev 入口**：Cloudflare DNS 加 `nuankebao-dev.tooyang.top` → 同一 tunnel；`/home/tooyan/.cloudflared-tc-prod/config.yml` 加 ingress（dev → :3003）；`systemctl --user restart cloudflared-tc-prod.service`
2. **改 dev 强绑定**：tc `.env.local` 的 `AUTH_URL` → `https://nuankebao-dev.tooyang.top`；LAN 访问继续可用
3. **生产切换**：tunnel ingress 把 `nuankebao.tooyang.top` 从 :3003 改指 :3004；重启 cloudflared；APK 用生产域名构建
4. 验证三件套一致（AGENTS §6.3）：

```
[hostname]  nuankebao.tooyang.top（prod） / nuankebao-dev.tooyang.top（dev）
    ↕ AUTH_URL        .env.prod ↔ .env.local
    ↕ APK dart-define NUANKEBAO_API_BASE=https://nuankebao.tooyang.top/api
```

**回滚**：tunnel ingress 把主域名改回 :3003 即可；prod 库独立，dev 不受影响。

---

## 5. 安全基线

- 生产 Postgres 只在 Docker 内网，不对主机/公网暴露端口
- 密码：scrypt 哈希存储；登录限流；生产禁用 dev 开关（B10）
- 密钥：`.env.prod` chmod 600 不进 git；APK keystore 双备份
- dev 工具路由（/app-preview）生产关闭（A6）
- 备份全链路 GPG 加密；恢复演练 ≥ 1 次
- 健康数据只落本机（主人自有服务器），无出境/第三方 SaaS

---

## 6. 实施阶段与验收

| 阶段 | 内容 | 验收 | 预估 |
|---|---|---|---|
| **P0 准备**（✅ 已完成） | 停用 `nuankebao-stack.service`；端口 3004 确认；决策拍板 | unit inactive/disabled；dev 正常 | — |
| **P1 生产栈修复** | §3.A 全部 + `prod-deploy.sh` + 本地容器跑通 | `docker build` 通过；本地起 prod 容器连临时库 `/api/health` 200 | 1–2 天 |
| **P2 账号密码登录** | §3.B 全部（含 `tooyan` 建档） | 密码登录成功；两个账号 = 两个身份；错误密码被限流；首登改密可用 | ~1 天 |
| **P3 tc 生产部署** | §3.C/E：空库 migrate + seed、prod 栈起在 :3004、备份/健康检查 | LAN `http://192.168.1.99:3004/api/health` 200；第一份加密备份；恢复演练 | ~1 天 |
| **P4 APK 签名发布** | §3.D | 真机安装 release APK → 登录 → 录入养生记录 | 0.5 天 |
| **P5 域名切换 + 内测** | §4；邀请 1–2 销售 | 销售日常可用；dev 预览不受影响 | 0.5 天 + 内测周期 |

**开工到可内测 ≈ 4–5 个工作日。**

---

## 7. 费用

- Phase 1（tc 本机）：**增量成本 ≈ 0**（仅磁盘占用；注意系统盘已用 82%，prod 上传目录需监控）
- 未来上腾讯云：见附录 A.1/A.2

---

## 8. 需要主人提供 / 确认

1. `tooyan` 初始口令已给（建档时一次性传入；建议首登后更换）
2. 首批邀请用户名单（姓名 + 手机号 + 角色）——P2 后提供即可
3. release keystore 口令（P4 时主人设定）
4. 是否保留自助改密入口（建议保留，B9）

---

## 9. 验收清单（DoD）

- [ ] prod compose 本地构建通过，容器名/卷/端口与 dev 零冲突
- [ ] prod 空库 migrate + seed + 审计触发器生效
- [ ] `tooyan` 管理员可登录；邀请制建号可用；改密可用
- [ ] APK：release 签名、指向 `nuankebao.tooyang.top`、`/download` 可下载
- [ ] 生产备份每日执行 + 恢复演练 ≥ 1 次
- [ ] 健康检查 timer 生效；`/app-preview` 在生产关闭
- [ ] 域名：prod → :3004、dev → :3003；三件套（hostname/AUTH_URL/APK base）一致
- [ ] dev 机器验收：`next dev` / Flutter 预览 / dev 备份 全部未受影响

---

## 附录 A. 未来迁移腾讯云（Phase 2 参考，暂不实施）

### A.1 500 用户硬件估算

| 维度 | 估算 | 说明 |
|---|---|---|
| API | 3–5 万/天，均 <1 QPS，峰值 5–15 QPS | Flutter JSON API，单请求小 |
| 数据库 | 1 年 < 5–10 GB（含审计） | 客户 ~10 万行、养生 ~45 万条/年 |
| 照片 | 0.3–0.5 GB/天 → 120–180 GB/年 | 增长最快项；上云建议接 COS |
| 内存 | Next.js 0.3–0.6 GB + PG 0.5–1 GB + OS 0.5 GB | 4 GB 能跑，8 GB 从容 |

推荐：**4C8G / 200 GB SSD / 按流量计费**（轻量应用服务器即可，¥150–300/月）；最低 2C4G（内测）。带宽日常 <5 Mbps、突发 20–50 Mbps；按流量约 ¥0.8/GB。

### A.2 备案与网络

- 大陆区必须 ICP 备案（2–4 周：腾讯云初审 + 管局），备案期间域名不能对大陆 IP 提供 80/443
- 香港/海外区免备案，但跨境延迟 + 健康数据出境（违背红线）
- 自有服务器（tc）靠 Cloudflare Tunnel 免备案，但依赖家宽/电力，正式 500 用户建议上云

### A.3 如果以后仍要接短信（可选）

- 短信与服务器位置无关；门槛是签名/模板审核（需已备案网站/APP/公众号 之一）
- 阿里云 / 腾讯云皆可，1–3 工作日；代码侧加 `verification_code` 表 + 发码接口 + adapter 即可（本方案 B 包已为账号体系打好底，短信可作为二期 2FA/找回密码）

---

## 10. 关联文档

- [`docs/deploy.md`](../deploy.md) — 通用部署手册
- [ADR-0008](../adr/0008-apk-web-domain-spec.md) — APK 域 / WEB 域
- [AGENTS.md §6.3](../../AGENTS.md) — hostname / AUTH_URL / APK base 强绑定
- [`deploy/README.md`](../../deploy/README.md) — 备份栈（dev 现状）
