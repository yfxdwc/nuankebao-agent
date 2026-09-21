# 变更日志 (CHANGELOG)

所有 暖客宝 重要变更记录于此。格式基于 [Keep a Changelog](https://keepachangelog.com/)。

### Changed (客户列表排序 = 内部规则, 去掉用户选择控件, 2026-09-21)

> **主人原话**: 「排序不需要标签供选择 …… 这是一套背后的排序规则, 不需要标签选择」

- **删掉客户列表的「排序」选择行** (原 4 段胶囊: 🔥紧急 / 最近联系 / 最近添加 / 姓名)
  —— `flutter_app/lib/modules/customer/screens/customers_page.dart` 移除 `_sort` /
  `_sortUrgencyLocked` 状态与整个 `SegmentedButton` 行 (−78 行)
- 列表**恒定**按 `sortByUrgency` 级联排序: **紧急度 → 最近联系 → 最近添加**
  (分档 → 分数 → 距上次联系天数 → 建档时间), 用户不需要理解排序概念
- `GET /api/customers?sort=` 参数**保留** (后端能力 / 老客户端兼容), App 不再暴露;
  非会员仍按 Q1 判权由后端降级为 `new`, 但不再有 🔒 提示胶囊
- 筛选胶囊 (全部/加盟/普通/种子) 不变 —— 那是"看谁"不是"怎么排"
- 方案: `docs/follow-up-list-plan.md` §6.2 改写为「排序 = 内部规则」

### Fixed (客户行「名字被标签挤没」, 2026-09-21)

> 来源: 改完排序后按 AGENTS §3「改前端必截图验证」跑预览截图 —— **截图才发现**的 bug。

- **现象**: 客户行第一行是 `Row(名字 Flexible + 标签/🎂 徽章不可压缩)`, Flutter 先给
  不可压缩的标签分空间 → 长名字 + 2~3 个标签时**名字被挤成 0 宽**,
  截图实测「王女士」整行只剩 `🔥该回访了` `🔁复购窗口`, **名字看不见**
- **修法** (`flutter_app/lib/modules/customer/widgets/customer_row.dart`):
  名字改成「最多占 55% 宽」的 `ConstrainedBox` (短名字按真实宽度拿空间, 富余让给标签),
  标签尾巴 (= 推荐标签 + 🎂 生日徽章, 抽成 `_rowTail`) 用 `Expanded` + 横向
  `SingleChildScrollView` 吃剩余宽度 —— 放不下可滑动, 既不裁字也不报 overflow
- 验证: 预览站截图 (修前 `/tmp/list-after.png`, 修后 `/tmp/list-fixed2.png`);
  `flutter analyze lib` 0 error
- ⚠ 遗留 (未修, 见交付说明): 标签排满时 🎂 徽章会露一半 (可滑动);
  服务端 `pickFollowUpTags` 的生日标签与前端遗留 🎂 徽章仍是两套 (方案 §4.2 早说了要合并)

### Added (客户跟进引擎 P1 收尾 + P2 全部完成, 2026-09-21)

> 方案: [docs/follow-up-list-plan.md](docs/follow-up-list-plan.md) (主人 2026-09-20 拍 8 项)
> 本次把 **P1 剩余项 + P2 全部** 做完 → 主人原始需求 (客户列表集成跟进分析/推荐/提醒;
> 名字右侧推荐标签; 排序以跟进紧急度为第一规则) 三段全部闭环。

- **复购窗口接线 (P2, 会员)**: `src/lib/follow-up/repurchase.ts` 重构为**纯函数**
  (`computeRepurchaseWindow`, 单测 9 条) + 一次 SQL 批量取到店日期 (`batchRepurchaseWindows`)。
  route 层只给会员算 → `followUp.repurchase` + 名字右侧 `🔁复购窗口` 标签生效
  (实测客户 #1: 平均 4 天到店 → 窗口已开, `reason` 带上「复购窗口已开 N 天」)
- **客户详情「跟进分析」卡 (P1, 免费)**: 新端点 `GET /api/customers/[id]/follow-up-analysis`
  + 纯函数 `src/lib/follow-up/analysis.ts` (单测 16 条) + Flutter 卡
  (`modules/follow_up/widgets/follow_up_analysis_card.dart`, 放在 AI 区之前)。
  指标: 近 30/90 天联系次数 · 平均联系间隔 (中位数) · 趋势 (变热/变冷/稳定) ·
  到店规律 · 复购间隔中位数 · 未完成跟进任务 (逾期天数) + 一句话 headline
- **每日提醒 systemd timer**: `nuankebao-followup-tasks.{service,timer}` (每日 07:00,
  比用户 08:30 提醒早) + `deploy/run-followup-tasks.sh` 薄包装 (显式 source .env.local)。
  已装到本机 (next run 07:02:45 UTC); `install-systemd.sh` 纳入 (13 个 unit)
- **本地通知 (P2 免费)**: `flutter_local_notifications` + `flutter_timezone` + `timezone`;
  每日 08:30 一条「今天有 N 位客户要跟进」→ 点击直达 `/follow-ups`。
  「我的」→ 新增「提醒」卡开关 (权限被拒 → 开关不打开, 不假装成功)。
  **web 预览站不受影响**: web 走条件 import 空实现 (`follow_up_reminder_stub.dart`),
  因为 flutter_local_notifications 依赖 dart:io, 会炸 web build
- **`followUp.lastContactType` 修复**: 之前 route 没传 `lastInteractionTypes` → 该字段
  永远是 null, 客户行第二行「· 上次电话」是**死代码**。改为 attach 层自己批量查
  (`loadLastInteractionTypes`, 一次 SQL window function)

### Fixed (scripts/*.ts 环境变量加载失效 — 14 个脚本, 2026-09-21)

- **现象**: `npx tsx scripts/<任意>.ts` → `Error: DATABASE_URL is not set`, 14 个脚本全中
  (含本功能要用的 `refresh-follow-up-tasks.ts`) —— 之前"实测通过"其实是在手工 export 了
  env 的 shell 里跑的
- **根因**: `import { config } from "dotenv"; loadEnv(); import { db } from "@/lib/db";`
  这个写法在 ESM 下**无效** —— import 声明会被提升到模块顶部, `@/lib/db` 先求值
- **修法**: 新增 `scripts/_env.ts` (只做 dotenv 副作用), 把它放成脚本的**第一个 import**
  (ESM 按源码顺序深度优先求值 → 一定先于读 env 的模块)。本次先修
  `refresh-follow-up-tasks.ts`; 其余 13 个脚本同样的 1 行改法待主人拍 (改动机械但面广)

### Docs

- `docs/api.md`: `GET /api/customers` 补全 `type`/`sort` 参数 + `followUp` 块 + `summary`/`urgencyLocked`
  契约; 新增 `GET /api/customers/[id]/follow-up-analysis`
- `docs/follow-up-list-plan.md`: 状态 → P0/P1/P2 全部落地 (P3 列待拍项)


### Added (Flutter Web 预览自动重建守护, 2026-09-20)

- 背景: 主人要「真正的实时最新预览地址」。`/app-preview` 吃静态 `public/app`, 不自动跟随源码;
  `?dev=1` 的 DDC 调试模式慢 (几百个模块过 Cloudflare) 且 dev server 停在 14:26、
  API base 写死 `127.0.0.1:3003` → 浏览器侧空白
- 新增 `tools/watch-flutter-web.sh`: 每 15s 轮询 `flutter_app/lib/**` + `pubspec.yaml` 指纹,
  变化后 20s 去抖 → `tools/build-flutter-web.sh --auto` 重建 + 同步 `public/app`
- systemd user 单元 `nuankebao-flutter-web-watch.service` (常驻, Restart=always);
  `deploy/install-systemd.sh` 扩展为 11 个 unit
- 验证: touch 源码 → 15s 检测 + 20s 去抖 + 50s 构建 → `public/app` 自动更新 (总 ~1.5 分钟)
- 预览地址不变: LAN `http://192.168.1.99:3003/app-preview` /
  公网 `https://nuankebao-dev.tooyang.top/app-preview`（首次打开需强刷清 SW 缓存）

### Chore (预览静态包重建 0.2.6#7 — 补上注册入口等新功能, 2026-09-20)

- 背景: 主人发现 LAN `/app-preview` 界面旧 (没有注册入口); 静态包停在 02:25 (`0.2.4#5`),
  而注册入口/B1 自助注册等是 05:08 之后才进源码 —— `/app-preview` 吃静态 `public/app`,
  不自动跟随源码变化
- 处理: `tools/build-flutter-web.sh --auto` 重建 + 同步 `public/app`（§9.3, `--no-verify` 提交）
- 验证: `version.json` = `0.2.6#7`; 注册入口/收款码 字符串命中; 预览快照测试通过
- 备忘: 热更新预览走 `https://nuankebao-dev.tooyang.top/app-preview?dev=1`
  （`/dev-app` 反代只在 dev 公网域名下，LAN IP 访问不到）

### Changed (生产同步 + APK 0.2.5+6, 2026-09-20)

- 生产 web 重新部署: 同步 03:45 后全部提交 (自助注册 B1 + 推荐人确认、账号=客户建档、
  长期登录 10 年 + 7 天滚动续期、APK 升级三道保险等); 迁移 14 → **16**
  (`0014_referral_confirm` / `0015_referral_source`)
- APK 重建: `0.2.4+5` → **`0.2.5+6`** (官方 `tools/build-apk.sh`, 含签名材料硬拦截 + 指纹打印),
  签名指纹不变 (`0D:B0:A1:BC:…`, 口令轮换后密钥对未变) → 可覆盖安装不丢登录
- 验证: `/api/app-version` = 0.2.5+6; 静态直链/下载接口 200 (26,255,451 bytes); dev 3003 不受影响
- 部署前备份: `prod/pg-backups/pg-20260920-063213.dump.gpg`

### Security (keystore 口令轮换为随机强口令 + 弱口令副本清理, 2026-09-21 主人拍板)

**背景**: 核查发现签名口令是**复用弱口令** (（复用弱口令, 已失效）, 同一串值还出现在主人的 Obsidian 凭证库里当 QQ/ID/WG 口令,
且那两个 vault 都配了 GitHub 远端) → 等于"签名钥匙的保护 = 一串通用密码"; 另有多份未加密副本散落。

**主人拍板三项, 全部执行完毕**

| # | 决策 | 执行结果 |
|---|---|---|
| ① | 换 keystore 口令 | ✅ 24 位随机 (口令只存在密码管理器 / RECOVERY-CARD / muse wiki, **不写进本文件**); 旧口令 (复用弱口令, 已失效) **已失效**; **签名指纹不变** (`0DB0A1BC…`) → 用户零影响、无需重装 |
| ② | vault 里改指针 | ✅ 两个 Obsidian vault 各加一条**指针** (无明文); 核查确认 vault 里**没有**暖客宝上下文 (只是复用了同一串值) → 轮换后那串值从此打不开 keystore |
| ③ | 删异地未加密裸 keystore | ✅ `lk:.../nuankebao-keys/` 已删; 异地只留**加密归档** (含 keystore + 口令) |

**技术细节 (踩到的坑, 记下来)**

- keystore 扩展名是 `.jks` 但**实际格式是 PKCS12** → `keytool -keypasswd` 报
  `-keypasswd commands not supported if -storetype is PKCS12`; PKCS12 **只有一个口令**,
  store/key 必须同值 (改 `-storepasswd` 即可, 同时改了私钥的保护口令)
- 弱口令副本清理: 本机副份 (`~/nuankebao-databackups/keys/`) 已刷新为新口令版;
  临时文件 (`/tmp/pre-rotate-keystore.jks` 等) 已 `shred`;
  加密归档已用新口令重做并异地核对 (sha256 本机=异地 `1d5db0746f1aa010…`)

**验证**

- `keytool -list` 新口令可用 / 旧口令**打不开** ✓
- 用新口令 `apksigner sign` 真签一次 → `SHA-256 digest: 0db0a1bcff6da703…` **与线上一致** ✓
- `bash deploy/verify_signing_key.sh` 全流程通过 (解密归档 → 口令一致 → 用备份 keystore 重签 → 指纹一致) ✓
- `bash tools/build-apk.sh --no-build` 显示同一指纹 ✓
- vault 校验: 新口令**不在**任何 vault / git 跟踪文件里 ✓

**⚠️ 本次事故 (agent 自查发现并已处理)**

轮换完成写 CHANGELOG 时, agent **把新口令明文写进了 `CHANGELOG.md`**(git 跟踪文件) →
`git grep` 自查发现 (项目仓库未 push, 但已 commit `d921011`)。处理:

1. **立即二次轮换** → 那个值已失效 (`keytool` 验证过: 打不开 keystore)
2. CHANGELOG 里两处口令明文已抹除 (现值与历史值都不在仓库里)
3. **加自动检测**: `deploy/verify_signing_key.sh` 新增"口令泄漏扫描"——用**当前口令**扫
   `git ls-files` 跟踪的全部文件, 一旦命中就**演练失败** (月度自动跑, 也随时可手跑)
4. 规则沉淀: **口令永不写入任何 git 跟踪文件** (含 CHANGELOG / 文档 / 测试); 只进
   密码管理器 / RECOVERY-CARD / muse wiki (无远端)

**文档同步**: `~/nuankebao-databackups/keys/RECOVERY-CARD.txt` (新口令 + 轮换说明) ·
muse wiki `901/entities/nuankebao.md` (轮换记录, commit `bc046d98`) ·
两个 vault 指针 (各自本地 commit `4964b06` / `4d954a1`, **未 push**)

⚠️ **仍需主人做**: 把新口令抄进**密码管理器** (或打印)。目前它在本机两处 (wiki 页 / 恢复卡) + 加密归档 (本机 + 异地)。

### Added (keystore 治本方案: 3-2-1 备份 + 月度真签演练, 2026-09-21)

**主人问**: 「这个可能性大吗，有什么治本的消除此风险的方案吗 (keystore 丢 = 全体用户卸载重装)」

**先查清暴露面 (实测)**

| 项 | 结果 |
|---|---|
| keystore 副本 | 2 份 (`~/nuankebao-keys/` + `~/nuankebao-databackups/keys/`), sha256 一致 **但都在同一块盘 `/`** |
| 口令 (`key.properties`) | **只有 1 份**, 也在同一块盘; 全盘 grep 无其他副本 |
| 异地备份 | rsync 只同步 `pg-backups` + `media` → **keys 没在异地** ✗ |
| App 是否有"只存本地"的业务数据 | `sqflite` 声明了但**未被使用** → 无 → **重装只丢登录态, 业务数据在服务器** ✓ |

**治本三层**

1. **密钥不丢 (L1, 已实施)**: `deploy/backup.sh` 新增「签名密钥加密备份」——把 keystore **+ key.properties 口令**
   一起打包 GPG 加密 → 本地备份目录 (月度留档 12 份) → **rsync 到异地 `lk:`** (与 PG/media 同一条流水线)
2. **备份必须"验过" (L1.5, 已实施)**: 新 `deploy/verify_signing_key.sh` —— 解密备份 → 用**备份里的 keystore
   真签一次 APK** → `apksigner verify` 指纹必须等于线上 (`0DB0A1BC…`) 才算通过;
   已接入 `deploy/restore_verify.sh` (月度 timer 自动跑, 日志 `data/logs/signing-key-verify.log`)
3. **万一丢了影响最小 (L2, 已核实)**: App **没有只存本地的业务数据** → 重装 = 重新登录一次;
   文档写明补救流程 (通知 → 卸载重装 → 手机号+密码登录)

**同时说明为什么不走"结构性方案"**: Google Play App Signing 需要 Play (大陆不可用, 当前是直发 APK);
Android v3 密钥轮换**必须用旧私钥签 lineage** → 只适合"有计划换钥匙", 救不了"已丢失"。所以唯一治本 = L1+L1.5。

**验证**
- `bash deploy/verify_signing_key.sh` 全流程通过: 工作副本可打开 → 加密备份解密后 sha256 一致 → 口令一致 →
  **用备份 keystore 重签 APK → 指纹 `0DB0A1BCFF6DA703…` 与线上一致** ✓
- 备份段单独实跑: 产出 `signing-keys.tar.zst.enc` (3791 bytes) + 月度留档 `signing-keys-202609.tar.zst.enc` ✓
- `bash -n` 语法检查通过 (backup.sh / restore_verify.sh / verify_signing_key.sh)
- 文档 `docs/deploy.md §APK 签名` 补齐: 风险矩阵前后对比 + 自动化调度 + 灾难恢复命令 + 补救流程

**还需主人做的一件小事 (我做不到)**: 把 keystore 口令抄一份到**密码管理器或纸质**记录里 ——
口令跟 keystore 存在同一台机器上, 是这套方案里最后一个"同点故障"。

### Added (APK 升级与登录态: 签名硬拦截 + 指纹自检 + 一键打包脚本, 2026-09-21)

**主人问**: 「升级 app 后能保持登录状态吗」→ 答案的关键是**签名密钥一致** (Android 只允许同签名覆盖安装,
签名变了必须先卸载 → app 数据含登录凭证一起没了)。为此做了三件让这件事"可核对"的事:

| 改动 | 内容 |
|---|---|
| **硬拦截** (gradle) | `flutter_app/android/app/build.gradle`: release 构建缺少 `key.properties` 时**直接失败**并给中文指引 —— 以前会**静默回退 debug 签名**, 打出与线上签名不同的包 (用户装不上 → 卸载 → 掉登录)。只拦 release (debug/`flutter run` 不受影响), 已实测: 移开 key.properties 跑 `assembleRelease` → 报 [暖客宝] 明确指出原因 |
| **指纹自检** (App 内) | 新 `shortBuildSignature()` / `installInfoLine()`: 「我的 → 网络自检」新增「安装包」行 (包名 + 版本 + **签名前 16 位**); 「复制诊断信息」也带上; 「关于与帮助」显示同一行 → 发版前后在手机上对一眼即可 |
| **一键打包** (新脚本) | `tools/build-apk.sh [api-base] [--no-build]`: 检查签名材料 → 打包 (自动带 `--dart-define=NUANKEBAO_API_BASE`) → 打印产物大小 + **签名指纹** (keytool) + 对照口诀 |

**实测**
- 现有 release APK 签名: `CN=NuankeBao` / `SHA256 0DB0A1BCFF6DA703…` —— **是正式 keystore, 不是 debug key** ✓
  (debug key 会是 `CN=Android Debug`; 也就是说**历史版本之间签名是连续的, 升级不会掉登录**)
- `bash tools/build-apk.sh --no-build` → 打印 25.0 MB + SHA1/SHA256 + 对照办法 ✓
- release 缺 key.properties → 构建失败并指出修法 (fail fast, 不把问题带到用户手机上) ✓
- `flutter test test/session_token_test.dart` **8 pass** (新增 3 例: 指纹简写/取不到时说人话/安装信息一行文案)
- `flutter analyze` / `npx tsc --noEmit` (我的文件) 0 error

### Fixed (退出 App 后又要重新登录 → 同设备长期记住登录, 2026-09-20 主人要)

**主人要**: 「当前 app 退出后又要重新登录。在同一个设备需要能够长期记住登录状态，不限时长」

**根因 (代码事实)**: `src/lib/auth/config.ts` 的 `session` **没写 maxAge** → Auth.js 默认 **30 天**;
`/api/auth/flutter-login` 又自己写了一份 30 天 (两处各写一份, 改一处忘一处) → 到期 JWT 失效 → 401 → 重新登录。
另外安卓 `flutter_secure_storage` 读取**没有 try/catch**, keystore 失效时异常冒泡 → 表现为"莫名被登出"。

| 改动 | 内容 |
|---|---|
| 会话上限 | **10 年** (`315360000s`) + **7 天滚动续期** (`updateAge`) → 常用设备实际永不掉线 |
| 唯一真相 | 新 `src/lib/auth/session.ts`: Auth.js 与 dev 端点共用; 运维手闸 `SESSION_MAX_AGE_DAYS` (1-3650, 非法值回退) |
| Flutter 存储 | `sessionToken()/sessionCookieName()` 加 try/catch (读失败=当作未登录但**不删**数据); 新增 `saveSession()` 统一写入路径 (3 处重复写收敛成 1 处) |
| 自检可见 | 新 `core/http/session_token.dart` (JWS 解 exp / JWE 解不开不瞎猜) + 「我的 → 网络自检」新增「登录状态」一行: 「已记住登录, 有效期至 2036-09-17 (无需重复登录)」 |
| 退出登录 | 注释写明: 纯 JWT 阶段**服务端无法单点吊销**, 设备丢失要走 停用账号 / 换 `AUTH_SECRET` (记入 ADR-0013 §3) |

**验证 (实测)**
- `curl /api/auth/session` (带 cookie) → `expires: 2036-09-17T05:45:39.757Z` = **10.0 年** ✓
- 登录响应头 → `authjs.session-token=…; Expires=Wed, 17 Sep 2036; Max-Age=315360000` ✓
- `tests/auth-session-ttl.test.ts` **5 pass** (含"Auth.js 配置真的接上了这两个值"——防"写了常量没接线")
- `flutter_app/test/session_token_test.dart` **5 pass** (JWS/JWE/脏数据/文案)
- `npx tsc --noEmit` / `flutter analyze` (我的文件) 0 error

### Fixed (推荐关系加 source: 区分「管理员代建」与「自助注册」两种 pending, 2026-09-20)

**发现的真冲突**: 同仓另一 session 在 `src/lib/auth/registration.ts` 建了**唯一建号入口**
`createAccountWithProfile()` (建号 = 建账号 + 强制建客户档案 + 推荐码必填, 主人 2026-09-19 拍),
它内部会调 `claimReferralCode()` → 新人**立刻**拿 15 天 (管理员已背书)。

而我新加的 B1 自助注册走 `registerWithReferral()` → 关系是 `pending`, **等推荐人确认**才发。

两者都用 `status='pending'`, UI 上分不开 → 推荐人会看到一堆"等你确认"其实**早就生效**的关系
(点确认还会得到"之前已经发过了")。已修:

| 改动 | 说明 |
|---|---|
| `referral_reward.source` (migration `0015_referral_source`, 加性 NOT NULL DEFAULT 'admin') | `admin` = 管理员代建 (已生效) / `self_signup` = 自助注册 (等推荐人确认) |
| `claimReferralCode()` | 写 `source: 'admin'` (管理员/脚本建号路径) |
| `registerWithReferral()` | 写 `source: 'self_signup'` |
| `GET /api/billing/referral/pending` | 返回 `source` |
| Flutter `MyReferral` | 新增 `needsMyConfirmation` (= pending && self_signup); 只有它才显示「这是我朋友 / 不认识」按钮 |
| 状态文案 | pending(admin) → 「已生效 (等对方成为加盟者后你得 15 天)」; pending(self_signup) → 「等你确认」 |
| 「我的」页入口 | 「好友待确认 (N)」只统计 `needsMyConfirmation` 的 |
| 顺带核对 | 另一 session 已把我早前在 `import-users.ts` 里加的重复 `claimReferralCode` 调用换成 `createAccountWithProfile` 的返回值 → **无重复认领** (已 grep 确认) |

**验证**
- `tests/billing-integration.test.ts` **21 pass** (新增 1 例: 管理员建号路径 → `source='admin'` + 新人立刻拿到 15 天;
  自助注册用例补断言 `source='self_signup'`)
- `flutter test` **42 pass** (推荐人用例改成 3 条: 自助待确认 / 管理员代建 / 已确认 → 只显示「好友待确认 (1 人)」)
- `pnpm db:compat` 0 error; `npx tsc --noEmit` / `flutter analyze` (我的文件) 0 error

### Added (B1 自助注册: 凭推荐码注册 + 推荐人确认, 2026-09-20 主人拍)

**主人问**: 「当前 app 的登录界面里没有注册账户的入口，新用户怎么注册？是邀请人代注册吗」
**主人拍**: 选 **B1** + 「账号/用户名提醒用户填真实姓名，真实手机号」

**背景事实 (核查结果)**: 登录页无注册入口; App/Web 都没有用户管理页; 建号只能靠服务器脚本
(`create-admin.ts` / `import-users.ts`) → 新人进来必须经主人在服务器上手工操作, 推荐码也被迫经主人转手。

**闭环**

```
新人  登录页「有新推荐码? 去注册」→ 推荐码 + 真实姓名 + 真实手机号 + 自设密码
      → 注册成功 (免费档, 还没有权益; 页面写明"等推荐人确认")
推荐人 我的 → 好友待确认 (N) → 看 姓名+打码手机号 → 「这是我朋友」/「不认识」
      → 确认: 新人立刻得 15 天 (推荐人的 15 天仍等新人成为加盟者, D23 不变)
      → 驳回: 没有任何权益 (防"码被转发后陌生人白嫖")
```

| 层 | 内容 |
|---|---|
| 表 | `referral_reward` 状态机扩展为 `pending(待推荐人确认) → confirmed → rewarded`, 新增 `confirmed_at` / `rejected_at` (migration `0014_referral_confirm`, 加性) |
| 注册 API | `POST /api/auth/register` (公开 + IP 限流 5 次/10 分钟): 强校验 码/姓名/手机号/密码/手机号唯一 → 建号 + 待确认推荐关系, **不发权益** |
| 确认 API | `GET /api/billing/referral/pending` (我的推荐列表)、`POST .../pending/[id]` (confirm/reject, 仅本人可操作) |
| 校验规则 | 姓名 2-20 字且含中文或字母 (纯数字/符号拒); 手机号 `1[3-9]` 11 位且唯一; 密码走全仓 scrypt 策略 |
| Flutter | 新 `modules/auth/screens/register_screen.dart` (注册页, 带"真实姓名/真实手机号"提示) + 登录页入口 + 新 `screens/my_referrals_page.dart` (好友确认页) + 「我的」页「好友待确认 (N)」入口 + 路由 `/register` `/profile/referrals` |
| 防刷 | 封顶把 **pending 也算**; 注册 IP 限流; 一人一号 (phone_hash 唯一); 确认/驳回只能由该条推荐的推荐人操作 |

**验证**
- `tests/billing-integration.test.ts` **20 pass** (新增 5 例: 姓名/手机号/密码/码 校验全拒 /
  注册成功但**不发权益** / 手机号重复被拒 / 推荐人确认后新用户得 15 天 + 重复确认幂等 /
  越权确认被拒 + 驳回不发权益)
- `flutter test` **42 pass** (新增: 注册页四个必填项 + **真实姓名/手机号提示文案** + 邀请制说明 +
  预填推荐码 + 未填全给中文提示; 「我的」页「好友待确认 (1 人)」入口)
- `npx tsc --noEmit` (我的文件) 0 error; `flutter analyze` (我的文件) 0 issue; `pnpm db:compat` 0 error
- 注: `scripts/create-admin.ts` 当前有一条**另一 session 在途改动**的 TS 报错 (`ensureAccountProfile`), 与本轮无关

### Changed (生产同步 + APK 重建 0.2.4+5, 2026-09-20)

- 生产 web 重新部署: 包含 2026-09-19 11:21 之后全部提交 (网页登录表单修复、
  会员/收款体系 S0/S0.5、预览网络修复等); 迁移 12 → 14 条
  (`0012_membership_billing` / `0013_manual_payment`), 新增表
  `membership` / `entitlement_grant` / `billing_config` / `manual_payment_request`
- APK 重建: `0.2.3+4` → `0.2.4+5` (含收款码接入 App、推荐码注册口径、客户列表头像标签等),
  release 签名不变 (SHA-256 `0db0a1bc…`), 已替换生产下载文件 (26,219,828 bytes)
- 验証: 生产网页表单已是账号/密码; `admin` 登录 302 + session、`/api/me` 200;
  `/api/app-version` = 0.2.4+5; `/api/apk-download` 200; dev 3003 不受影响
- 注意: `/api/app-version` 版本号来自 web 镜像内 `flutter_app/pubspec.yaml`
  → 每次 bump 版本需重建 web 镜像 (本次已重建)
- 部署前备份: `prod/pg-backups/pg-20260920-031644.dump.gpg`;
  旧镜像 tag `nuankebao-prod-web:rollback`

### Changed (P5: 公网域名切换 — 生产正式上线, 2026-09-20)

- `nuankebao.tooyang.top` → 生产 Docker 栈 `127.0.0.1:3004`（原指 dev :3003）
- 新增 `nuankebao-dev.tooyang.top` → dev :3003（Cloudflare CNAME + tunnel ingress）;
  dev 预览 `/app-preview` 与 Flutter dev server `/dev-app*` (8181) 同步迁到 dev 域名
- dev `.env.local` 增 `AUTH_URL=https://nuankebao-dev.tooyang.top`
  （原先无该行, 一直从 `.env` 读主域名）
- 运维: `cloudflared-tc-prod.service` 重启生效; 配置备份
  `~/.cloudflared-tc-prod/config.yml.bak-20260920-030337`
- 验证 (公网 HTTPS): prod 登录 302 + session、`/api/me` 200、`/admin/download` 200、
  `/api/apk-download` 200 (26.1MB); prod `/app-preview` 404（生产门闸）、`flutter-login` 404;
  dev 健康/预览 200、`flutter-login` 400; `sales-ai` 等其他隧道 200 不受影响
- 回滚: tunnel config `3004` 改回 `3003` + dev 规则搬回主域名 → 重启 cloudflared

### Fixed (预览频繁「网络不太好」+ 刷新慢, 2026-09-20 w21 主人反馈)

**症状**: `/app-preview` iframe 模式下, 任何「首次进页面」都频繁弹「网络不太好, 请检查网络后重试」; 主人硬刷新也常常慢 30s+。

**根因**: Next.js dev mode 懒编译 — 每个 API 路由**首次 hit 触发 webpack 编译**, 实测最坏 43s (`/api/franchisees/placement-requests`), 个别 `auth-flutter-login` 188s。
Flutter web dio 之前 `connectTimeout=10s` 完全不够, 任何冷路由都超时 → 落到 `ErrorState`(「网络不太好」) UI。

**治本 (两层, 互补)**

| 改动 | 文件 | 作用 |
|---|---|---|
| dio `connectTimeout` 10s → **60s** (web) | `flutter_app/lib/core/http/api_client.dart:255-274` | 兜住 dev mode 冷编译最坏情况 |
| dio `receiveTimeout` 30s → **60s** (web) | 同上 | 配套 |
| `kIsWeb` 分平台 | 同上 | native APK 保持 10s/30s (蜂窝网络应快显, 失败不卡人) |
| 新增 `tools/prewarm-dev-routes.sh` | `tools/prewarm-dev-routes.sh` | 默认预热 10 个最热路由, `--all` 全 33, `--top N` `--parallel N` 可调 |

**prewarm 脚本默认预热列表** (按真实 hit 频率排): `/api/auth/session` `/api/auth/csrf` `/api/auth/flutter-login` `/api/me` `/api/health` `/api/customers` `/api/customers/stats` `/api/wellness-records` `/api/salons` `/api/franchisees/me/tree`。

**不要**给 systemd `ExecStartPost=` 加这个脚本 (dev server 启动期还没就绪, 会跑空 + 把启动队列拖入 33 路由编译 = 卡死); 主人手跑。

**验证**
- `pnpm test tests/preview-framework-snapshot.test.ts` → 19/19 pass (128ms)
- Playwright 现场 `/app-preview` → iframe 加载 OK, 无错误 UI, `main.dart.js` HTTP 200
- API 真实响应: 之前 32s+, 现在 200ms (路由已编译)

**关联**:
- 同步修了 `flutter_app/lib/modules/wellness/screens/wellness_record_detail_page.dart:209` — 照片 URL 之前硬编码 `192.168.1.200:3003` (跟 dio IP bug 同根), 改为 `ApiClient.baseOrigin`
- 同步重建 Flutter web (`./tools/build-flutter-web.sh --auto`), main.dart.js 不再含硬编码 IP, web 模式从 `Uri.base.origin` 运行时推导
- AGENTS §5 待补: "Dart 源码不要硬编码 host:port" (code smell 条目, 跟 R12 同类治本)

### Added (内测收款码接入 App: 微信个人收款码已就位, 2026-09-20)

**主人要**: 「把内测模式的收款码接入应用」

**过程 (我看不了图, 所以用"程序化取图 + 模型复核"两条腿)**

1. **从会话记录里取出原图**: 附件以 base64 存在会话 JSONL 里 → 解出 1118×1524 PNG
2. **客观识别 (不靠肉眼)**: 装 `opencv-python-headless` 到临时 venv →
   `QRCodeDetector` 定位 + 解码 → payload = `wxp://f2f07c2u…`
   → **确认是微信个人收款码** (wxp:// 是微信收款协议), 且二维码在原图里只占
   x 322-796 / y 394-870 (截图四周是手机界面)
3. **自动裁切**: 按检测框 + 10% 静默区裁切 → 白底方形放大到 900×900 →
   16 色量化 (515KB → **48KB**) → 处理后再扫一次, **payload 完全一致** = 裁完仍可扫
4. **模型复核**: 派视觉子 agent (MiniMax-M3) 看裁切后的图, 确认"是微信收款码 / 居中完整 /
   没有裁掉定位角 / 无其他可读个人信息" (结论见下)

**代码改动**

| 项 | 说明 |
|---|---|
| `public/payment/wechat-qr.png` | 裁切+优化的收款码 (900×900, ~48KB), 用静态兜底路径 |
| `GET /api/billing/pay-info` | 新增 `qrAvailable` 字段: **真的检查文件存在** (原来只看"有没有在后台配置", 静态文件在位也会误报"还没设置收款码") |
| 客户端 | 「开通会员」弹层改为 `!qrAvailable` 才提示未设置; 有码时正常显示大图二维码 |
| `.gitignore` | `public/payment/*.{png,jpg,jpeg,webp}` 不入库 (个人收款码是私人凭证, 进历史难撤下) |
| `public/payment/README.md` | 记录来源/处理过程 + 两种换码方式 (App 内上传优先, 或换静态文件) |

**验证**
- `curl /payment/wechat-qr.png` → **HTTP 200, image/png, 48169 bytes**
- `curl /api/billing/pay-info` → `qrUrl=/payment/wechat-qr.png, qrAvailable=true,
  isFallbackQr=true, payeeName=管理员, products=[1个月 ¥69, 3个月 ¥189]`
- OpenCV 复扫裁切前后 payload 一致 (`wxp://…`)
- 视觉子 agent 复核结论: 见任务记录 (确认是微信收款码、裁切完整居中)

### Changed (推荐码只在注册(建号)时填 —— 「我的」页去掉填码入口, 2026-09-19 主人要)

**主人要**: 「朋友的推荐码仅在用户注册时可填入。"我的"页面中不应该再有填入他人邀请码的入口」

**背景校正**: 登录已改为**账号+密码 (邀请制, 不开放自助注册)** (production-plan v2, 2026-09-19),
所以"注册"= **管理员建号那一刻** —— 填码入口应落在建号路径, 而不是用户自己的页面。

| 项 | 改动 |
|---|---|
| 「我的」页 | **删除「我有推荐码」入口 + 填码弹层** (只保留"我的推荐码"展示, 给朋友拿去用) |
| 推荐码说明文案 | 改为「把码告诉朋友, 由管理员给朋友建号时填入 (只在建号时有效); 双方各得 15 天会员」 |
| 建号路径 | `scripts/import-users.ts` CSV 新增第 6 列 **`referral_code`** (选填): 建号即填码 → 新用户立刻得 15 天; 码无效时不影响建号, 打印 ⚠ 并汇总; dry-run 也会提示 |
| 服务端硬约束 | `claimReferralCode` 新增**注册窗口**: 账号创建 24h 内才收码 (`REFERRAL_CLAIM_WINDOW_HOURS`), 超时拒并提示"推荐码只能在注册时填" —— 防止有人直接打 API 给老账号补码 |
| 保留的接口 | `POST /api/billing/referral/claim` 仍在 (未来若开放自助注册, 注册页直接调), 但受窗口 + 一人一次 + 反作弊约束 |

**验证**
- `tests/billing-integration.test.ts` **15 pass** (新增: 新号可填 → 得 15 天; 把 `created_at` 推到 3 天前 → 拒 + 文案含"注册时")
- `flutter test` **38 pass** (免费档会员卡用例改为断言 **不再有**「我有推荐码」入口)
- 真建号实测: `npx tsx scripts/import-users.ts users.csv` (带 `referral_code=WRJZAN`) →
  `✓ 已创建 测试甲 … | 推荐码 WRJZAN 已生效 (+15 天)`; DB 核对 `member_until = +15 天` + 权益流水 1 条 + 推荐关系 1 条
  (测试账号已清理, 审计日志保留轨迹)
- dry-run 输出带 `推荐码=… (+15 天)` 提示; 码格式不合法 (非 6 位/含易混字符) 在解析阶段就报错并指出行号

### Added (系统管理员 = 永久会员, 2026-09-19 主人要)

**主人要**: 「把系统管理员(admin)设置成永久会员」

**做法: 角色即规则 (不写权益行)**

| 项 | 内容 |
|---|---|
| 判定 | `user.role = 'admin'` → `isMember=true` / `permanent=true` / `planCode='admin'` / `membershipSource='admin'` / `memberUntil=null` |
| 实现 | `getMembership()` 一次查询 (leftJoin user+membership) 同时拿 role 与到期时间; admin 直接短路返回 → **零数据、零维护** |
| 为什么不用"发 3650 天权益" | 到期要续、换人要补数据、`entitlement_grant` 里堆假流水污染审计; 而 role 本来就是"这是后台账号"的唯一真相 |
| 自动跟随 | `requireFeature` / `hasFeatureAccess` / 生日提醒过滤 / `/api/me` 全部走 `getMembership` → 一处改全局生效 |
| 客户端 | 「我的」页显示「管理员账号 · 永久会员 (无需付费, 不会到期)」, **不显示开通/续费入口**; 会员功能全部可用 |
| 安全边界 | 只认数据库里的 `user.role` (不信客户端/session 可改字段); admin 照常参与审计 |

**验证**
- `tests/billing-integration.test.ts` **14 pass** (新增 2 例: admin 恒会员且不落库 / 升 admin 立刻会员、降回 sales 立刻按真实权益算)
- `flutter test`: **38 pass** (新增「管理员会员卡: 永久会员 + 无开通入口」一例)
- curl 实测 (dev admin 账号): `/api/me` → `isMember=true, permanent=true, features=9`; 之前 402 的
  AI 跟进建议 → **200**、互动记录 POST → **201**; DB 里 `membership` 行数为 0 (规则判定, 无残留)
- `npx tsc --noEmit` / `flutter analyze` 改动文件 0 error

### Added (S0.5 人工收款闭环: 个人微信收款码 + App 内核销, 2026-09-19 主人拍)

**主人要**: 「当前内测阶段，暂时用我个人的微信收款码实现。继续完成全部剩余步骤」

**闭环 (全程手机内完成, 管理员不用开电脑)**

```
用户  我的 → 会员 → 开通会员 → 看收款码 (¥69/月 · ¥189/3月) → 微信扫码付款
      → 回 App 填备注 (手机号后4位) ± 传付款截图 → 点「我已支付」(pending)
管理员 我的 → 管理员工具 → 付款申请(待审) → 核对到账 → 「通过并开通」→ 对方 +30 天
用户  我的 → 会员 → 会员中 · 有效期至 X 月 X 日
```

| 层 | 内容 |
|---|---|
| 表 (migration `0013_manual_payment`) | `billing_config` (收款码 URL / 收款人 / 备注提示 / 开关) + `manual_payment_request` (金额/天数/备注/截图/状态/核销人/实际天数), 两张都挂审计触发器 |
| 用户接口 | `GET /api/billing/pay-info` (收款信息 + 我的申请状态)、`POST/GET /api/billing/manual-payments` |
| 管理员接口 | `GET /api/billing/admin/manual-payments?status=`、`POST .../[id]` (approve/reject)、`POST /api/billing/admin/pay-info` (换收款码) — 全部服务端查 `role=admin` |
| 收款码来源 | `billing_config.manual_wechat_qr_url` (App 内上传→`/uploads/`) > 静态兜底 `public/payment/wechat-qr.png` |
| Flutter | `screens/profile_sheets.dart` 新增「开通会员」弹层 (收款码/金额/备注/截图/我已支付/申请状态) + `screens/admin_tools_page.dart` (管理员工具: 上传收款码 + 待审列表 + 通过/驳回 + 截图查看) + 路由 `/profile/admin` + 「我的」页 admin 入口 (按 role 显示) |
| 免费上传 | `POST /api/photos` 新增免费 purpose: `payment_proof` (付钱的人还不是会员, 拦了就没法核对) / `payment_qr` (管理员传收款码) |

**顺手修一个真 bug (集成测试当场抓出)**
- `audit_trigger()` 用 `COALESCE(NEW.id, OLD.id)::BIGINT` —— **没有 `id` 列的表 (键值型 `billing_config`) 写入直接报
  `record "new" has no field "id"`, 该表所有写操作全挂**。改为从 `to_jsonb()` 取值 + 缺 id 退化成 0
  (`drizzle/audit_function.sql`) → 以后任何 kv 表都能安全挂审计

**验证**
- `tests/billing-integration.test.ts`: **12 pass** (新增 5 例: 默认收款信息/管理员换收款码/提交→通过→会员生效 30 天/重复提交与重复核销被拒/驳回不加天数)
- `tests/billing-rules.test.ts`: 23 pass; `flutter test profile_page+user_avatar+me_model`: **37 pass** (新增开通会员弹层一例)
- `npx tsc --noEmit` / `flutter analyze` (改动文件) / `pnpm db:compat` 全 0 error
- **curl 全链路**: pay-info → 管理员设置收款码 → 提交申请 → 待审列表 → approve → `/api/me` 显示 `isMember=true, until=+30天, features=9`
- 冒烟后已把 dev 账号复位为免费、清掉测试申请与测试收款码配置 (管理员的真实收款码由主人在 App 内上传)

**待办 (S1 及以后)**: 自动续费 (需周期扣款资质) / 电子发票 / 在线支付 (微信·支付宝 APP 支付 + 回调对账) / AI 用量台账

### Added (会员付费 S0 落地: 会员骨架 + 9 项判权 + 推荐码 + 人工开通, 2026-09-19)

**主人拍板后开工** (ask_user `0ecdc2ab`: D21 会员档 / D22 月30累计360 / D23 被推荐人成为加盟者后发奖 / D20 开工 S0)

**后端 (新域 `billing` / `membership` / `referral`, 与加盟域零外键)**

| 文件 | 作用 |
|---|---|
| `src/lib/billing/features.ts` | 9 项会员功能清单 (ai.assistant / ai.follow_up / ai.customer_profile / ai.effect_analysis / ai.repurchase / salon.create / crm.interaction / crm.birthday_reminder / media.upload) |
| `src/lib/billing/referral.ts` | 推荐码字符集 (去 0/O/1/I/L) / 封顶 月30·累计360 / 反作弊判定 / 顺延叠加 / 幂等键 (纯函数, 可单测) |
| `src/lib/billing/entitlements.ts` | `getMembershipView` / `requireFeature`(402) / `grantDays`(幂等+顺延) / `ensureReferralCode` / `claimReferralCode` / `rewardReferrerOnFranchisee` / `adminGrant` |
| `src/lib/billing/guard.ts` | route 级 `featureGuard` (402 + code=MEMBERSHIP_REQUIRED) + `hasFeatureAccess` (读数据降级用) |
| `src/lib/billing/membership-filter.ts` | 非会员 → `birthdayRemindDays` 读成 null (数据保留, 续费即恢复) |
| `drizzle/0012_membership_billing.sql` | `plan` / `membership` / `entitlement_grant` / `referral_code` / `referral_reward` (加性, compat 0 error) + 5 张表挂审计触发器 |
| `GET /api/me` | 新增 `membership { isMember, memberUntil, planCode, features[], referralCode }` |
| `POST /api/billing/referral/claim` / `GET .../summary` / `POST /api/billing/admin/grant` | 填码 / 我的码与进度 / 管理员手工开通 (role=admin) |
| 判权落地 | `ai/{follow-up,profile,effect-analysis,repurchase-prediction}` + `interactions POST` + `photos POST` (`purpose=avatar` 例外放行) + 客户列表/详情生日提醒字段 |

**推荐奖励触发点**: 被推荐人**成为加盟者**时 (D23) — 挂在 `createPlacementRequest`(admin 立即落位) /
`decidePlacementRequest`(三方确认齐) / `createFranchisee` 三条落位路径的事务**提交之后**
(奖励失败不影响落位; 幂等靠 (referrer,referee) 唯一 + grant idempotencyKey)

**Flutter (S0 UI)**

- `core/models/me.dart`: `MeMembership` (isMember / memberUntil / features / referralCode) + `MeProfile.isMember` / `canUse(key)`
- `core/services/api.dart`: `BillingService` (claimReferralCode / referralSummary) + `PhotoService.upload(purpose:)`
- `core/http/api_client.dart` + `app.dart`: **402 全局兜底** —— 任何页面点到会员功能, 统一 SnackBar +「去开通」跳「我的」(避免每个页面各写一遍还漏)
- `screens/profile_page.dart`: 「会员」卡 (免费版/会员中 + 到期日 + 开通/续费入口 + 我的推荐码 + 「我有推荐码」填码弹层)
- 头像上传改传 `purpose=avatar` (个人头像免费, 不受会员限制)

**验证**

- `npx vitest run tests/billing-rules.test.ts`: **23 pass** (9 项清单 / 推荐码形状 / 封顶 / 反作弊 / 顺延 / 幂等键)
- `tests/billing-integration.test.ts`: **7 pass** (真 test DB: 填码→被推荐人得 15 天 → 成为加盟者→推荐人得 15 天 → 幂等 → 手工开通)
- `flutter test profile_page+me_model+user_avatar`: **36 pass** (含新增会员卡 免费档/会员中 两例; 视口随页面变高调到 3400)
- `npx tsc --noEmit` 0 error; `flutter analyze` 改动文件 0 issue; `pnpm db:compat` 0 error
- **curl 冒烟**: 免费用户 `GET /api/me` → `isMember=false + 推荐码 WRJZAN`; AI/互动/`photos(purpose=wellness)` 全 **402 + MEMBERSHIP_REQUIRED**; `photos(purpose=avatar)` **201 放行**; 推荐码格式错 **400**; `admin/grant` 用 admin 账号 **200** 并落审计 (测试后已把 dev 账号会员状态复位为免费, 撤销同样留审计)

**未做 (下一腿)**: 免费用户界面隐藏会员入口 (AI 卡/互动区/拍照) —— 服务端已拦, 客户端目前靠 402 全局提示兜底;
`沙龙` 的判权等 `modules/salon` 建完再接; 发票/自动续费属 S2

### Changed (会员付费草案 v0.2 — 依主人补充信息重写计费模型, 2026-09-19)

**主人补充**: 免费用户可用除 9 项外的全部功能 (AI助手/跟进建议/沙龙发起/客户画像/跟进推荐/
效果分析/互动记录/生日提醒/图片上传); 到期停会员功能但继续用基础功能; **¥69/月**, 自动续费 **¥49/月**;
付费方都是个人 (每人自己充值); 与业务资金无关 ("加盟体系本身不收费；软件订阅费与资格/层级解耦");
个体户账户收款 (问经营类别要求); **每人固定 6 位推荐码**, 注册可选填, 双方各得 15 天会员权益

**`docs/membership-billing-draft.md` v0.1 → v0.2 关键变更**

| 项 | v0.1 | v0.2 |
|---|---|---|
| 付费对象 | 租户 (门店/品牌) | **个人订阅** (每人自己充值) |
| 计价 | 席位+客户数+AI量 | **个人月费 69 / 49** (不设席位/客户数上限) |
| 档位 | 试用/基础/专业/品牌 | **免费档 / 会员档** (9 项受限, 附实施状态表) |
| 到期行为 | 只读停用 | **降级免费档**, 基础功能照用, 数据不删不锁 |
| 推荐 | 无 | **推荐码机制** (§2.3: 6 位/去易混字符/双向 15 天 + 五道合规护栏 + 反作弊) |
| 收款 | 对公转账 → 微信/支付宝 | **个体工商户**: 经营范围/类目/备案/软著/费率/税务 + **周期扣款资质风险** (§10.1) |
| 决策点 | D1-D20 | **D1-D25** (+复购预测归属/推荐封顶/发奖条件/不可折现/免费档无上限) |

**新增关键结论**
- **推荐码是全案最需要律师复核的一条** (《禁止传销条例》"拉人头"特征): 只送服务权益 (不可提现/转让/折现)、
  只有一层、与层级无关、有封顶 (建议月 2 次/累计 24 次)、协议写明"非投资收益"
- **自动续费 (周期扣款) 个体户通过率低** → 建议 S0/S1 先做"手动续费同价 ¥49" (零资质风险), 能开代扣再上 S2
- **沙龙 (meeting) 功能实际不存在** (`modules/meeting` 已不在仓库) → 会员权益里先占位, 建好即会员专属
- **AI 含在会员内** 但必须补 `ai_usage` 台账 (防单用户烧穿 MiniMax 成本)
- 权益发放 (`entitlement_grant`, 送天数) 与 **钱账本** (`billing_ledger`) 分离 —— 避免"权益=现金价值"联想

**顺带**: ADR-0006 修订项已写明主人确认的表述; 律师复核/服务商三问/代账确认列入 §14 前置清单

### Added (会员付费系统 工业级草案 (DRAFT) — 只出方案, 不落代码, 2026-09-18 主人要)

**主人要**: 「当前项目还没有会员付费系统，先给我工业级的草案，根据当前项目性质列出一些关键决策点」

**产出**: `docs/membership-billing-draft.md` (15 节, 待主人拍板) —— 拍板后转 ADR-0012 + `docs/billing.md`

**核心结论** (基于本项目性质, 不是通用模板):

| # | 结论 |
|---|---|
| 1 | **钱与加盟必须物理隔离**: `billing_*` 表不与 `franchisee`/`customer` 有任何外键或金额流转 —— 否则触碰《禁止传销条例》红线 (ADR-0006 §2) |
| 2 | **加盟资格 ↔ 付费解耦**: 不续费只"用不了软件", 不丢加盟身份/上下级/历史数据; 付费买的是软件使用权 |
| 3 | **禁止一切返利/推荐奖/按下线计酬** (含"推荐打折"), 默认不做, 要做需律师复核 |
| 4 | **付费人通常是门店老板**, 不是销售员本人 → 计价 = 租户 + 席位 + 客户数 + AI 用量 |
| 5 | **分 4 期**: S0 会员骨架 (2~3 天, 对公转账人工开通, 零支付集成) → S1 微信/支付宝 APP 支付 + 回调幂等 + 每日对账 → S2 AI 点数/发票 → S3 多租户 (与 phase-3-saas 合流) |
| 6 | **金额一律整数分** + append-only `billing_ledger` (触发器拒 UPDATE/DELETE) + 每日渠道对账 |
| 7 | **判权一律服务端** (`requireEntitlement`/`assertQuota`), 402 与 403 分开, APK 只做提示 |
| 8 | **到期只读, 永不删数据** (数据主权 = 产品卖点) |
| 9 | **不给支付渠道传任何客户健康/手机号数据** (只传订单号+金额+商品描述) |
| 10 | 旧草案 `phase-3-saas §3.5` (¥99/¥299) 降级为**价格锚点**, 正式定价等 3-5 个客户访谈 |

**20 个关键决策点 (D1-D20)**: 收款主体 / 付费对象 / 计价维度 / 收款方式 / 渠道 / 定价 / 试用与宽限 /
自动续费 / AI 计价 / 判权实现 / 财务后台 (WEB 冻结例外) / 账本 / 密钥 / 多租户时机 / 法务 /
发票税务 / 退费政策 / 到期数据保留 / 回调兜底 / 上线节奏 —— 每条含选项 + 影响 + 建议 + 最晚决策时间。

**顺带发现的风险**: `ADR-0006` 里的"系统不收任何费用"表述在加付费后必须修订
(→ "加盟体系本身不收费; 软件订阅费与加盟资格/层级完全解耦"), 并列入律师复核项。

### Fixed (登录补漏: 网页表单 + dev admin 账号 + 预览重建, 2026-09-19)

**背景**: 主人反馈「登录不上」。排查 dev 日志: (1) 网页 `/login` 仍走旧手机号+验证码表单,
而后端 P2 已改为 identifier/password → 恒 CredentialsSignin; (2) `admin` 只在生产库, dev 库没有;
dev 用户也都没有密码 → Flutter 预览登录 401。

- `src/components/auth/login-form.tsx`: 两步验证码表单 → 一步「账号/手机号 + 密码」
  (`signIn("credentials", { identifier, password })`); 错误文案统一「账号或密码错误, 或尝试过于频繁」
- dev 库补建 `admin` (scripts/create-admin.ts, 同生产口令) → dev 网页/预览均可登录
- `api.dart` 残留旧文案「登录失败, 请检查验证码」→「账号或密码错误, 或尝试过于频繁」
- 预览 `public/app` 重建 (含新登录 UI + 改密弹层; version.json 0.2.4#5, 按 §9.3 --no-verify)
- APK 重建并替换 `data/prod/downloads/NUANKEBAO-release.apk` (26.1MB, 同签名 SHA-256 `0db0a1bc…`)

**验证**: dev `admin`+口令 → 网页 callback 302+session ✓ / flutter-login 200+token ✓;
`pnpm type-check` ✓; 预览基线快照测试 ✓ (改前)

### Added (P4: APK release 签名 + 生产分发链路, 2026-09-19)

**签名**

- 生成 release keystore (RSA2048 / 10000 天 / alias `nuankebao`, 口令主人设定):
  主 `~/nuankebao-keys/nuankebao-release.jks` + 本机副份 `nuankebao-databackups/keys/`
  + 异地 `lk:/media/mm7/tc_backup/nuankebao-keys/` (3 处保管)
- `flutter_app/android/app/build.gradle`: `signingConfigs.release` 读 `key.properties` (gitignored),
  缺文件回退 debug 签名; `gradle.properties` 降为 `-Xmx3G/Metaspace 1G` + `workers.max=2`
  (与另一会话/dev server 共享 15G 机器, 首次构建曾 `mergeReleaseShaders` native thread 失败)
- pubspec `0.2.2+3` → `0.2.3+4`

**分发**

- prod compose web 新增挂载 `./data/prod/downloads:/app/public/downloads:ro`;
  `deploy/prod-deploy.sh` 自建该目录 (APK 放进去即生效, 不用重建镜像)
- 构建: `flutter build apk --release --dart-define=NUANKEBAO_API_BASE=https://nuankebao.tooyang.top/api`
  → 26.1MB; `apksigner verify` 通过 (SHA-256 `0db0a1bc...`)
- Dockerfile runner 补 `COPY flutter_app/pubspec.yaml` + `.dockerignore` 放行该文件
  (修 app-version 在容器内读不到 pubspec 而回退 0.1.0 的缺口)

**验证 (prod :3004)**

- `/api/app-version` → `{version: 0.2.3, buildNumber: 4}` + APK size/mtime/md5
- `/api/apk-download` → 200 / 26,127,503 bytes; `/admin/download` → 200 (显示 0.2.3)
- 口令/keystore 位置/指纹已记入 muse wiki: `~/.muse/wiki/901/entities/nuankebao.md`

**待办**: 真机安装 release APK → 登录 → 录入养生记录 (P4 验收最后一步, 机器上无 adb 设备)

### Fixed + Added (P3: 生产备份/监控/开机自启 + dev 备份 P0 修复, 2026-09-19)

**P0 修复 (dev 备份连挂 3 天)**

- 根因: `/home/tooyan/nuankebao-databackups` 被删后, systemd `StandardOutput=append:<path>`
  在 unit 启动时就 209/STDOUT 失败 (ExecStartPre 也救不了: systemd 先配 stdout 再跑 ExecStartPre);
  9/17-9/19 每日备份全部启动即失败 (lk 异地盘还有此前的 8 份旧备份)
- 修: 新建 `deploy/run-with-log.sh` 包装器 (`mkdir` 目录 + 命令输出 tee 到 journal+文件,
  退出码保持命令的); 5 个 service (dev 3 + prod 2) 全部改用包装器
- 验证: dev backup + prod backup 手动跑均 exit 0, 目录/GFS/健康 JSON/异地 rsync 全到位

**生产备份 profile (C1/C2)**

- `deploy/backup.sh`: `NUANKEBAO_PROFILE=prod` → 容器 `nuankebao-prod-postgres`, 目录
  `.../prod/{pg-backups,media,logs,backup-health}`, 异地 `lk:.../nuankebao-prod`;
  媒体从 named volume (`nuankebao-prod-uploads`) 用 `docker run --entrypoint tar` 流式打包
- `deploy/systemd/nuankebao-prod-backup.{service,timer}` (每日 03:30, 避开 dev 03:00)
- `deploy/install-systemd.sh` 同步扩展为 10 个 unit (dev 3 对 + prod 2 对)

**健康检查 (C3)**

- `deploy/prod-healthcheck.sh` + `nuankebao-prod-healthcheck.{service,timer}` (每 5 分钟);
  失败自动 `docker restart nuankebao-prod-web` + 10s 复检; 正常时静默不刷日志

**开机自启 (E3)**

- `tools/nuankebao-stack.service` 修正版已安装到 `/etc/systemd/system/` + enable + active:
  `-p nuankebao-prod -f docker-compose.prod.yml --env-file .env.prod`, `Restart=no`

**恢复演练 (C4)**

- 解密最新 prod 备份 → 临时库 `nuankebao_restore_check` → `pg_restore` → 行数比对:
  表 24/24, user 1/1, audit_log 14/14, body_part 9/9 ✅ → 清理

**运维文档 (E4)**

- `docs/deploy.md` 新增「tc 本机 Docker 隔离生产栈」章节 (常用命令 + 红线)

### Added (P2: 账号密码登录 + 邀请制建档 + 自助改密, 2026-09-19)

**背景**: 登录从「手机号 + 短信验证码」(W1 mock) 改为「账号 / 手机号 + 密码」(邀请制,
不开放自助注册), 省掉短信资质/成本; 方案 `docs/deploy/production-plan.md` v2 §3.B。

**后端**

- migration `0011_user_credentials` (+down): `user.username` / `user.password_hash` (可空, 兼容老行)
  + `idx_user_username` 唯一索引; `meta/0011_snapshot.json` 顺带修正 0010 无 snapshot 的历史漂移
- `src/lib/auth/password.ts`: scrypt 哈希/校验 (Node 内置, 无新依赖) + 强度策略 (≥8 位含字母数字)
- `src/lib/auth/credentials.ts`: username / phone_hash 查用户 + scrypt 校验 + 5 次/分钟限流
- `src/lib/auth/config.ts`: Auth.js v5 **Edge 安全拆分** (middleware 用, 无 DB);
  `src/lib/auth/index.ts` 现为 Node 侧真实 `authorize` (删 W1「任意手机号+123456 → 用户1」桩)
  - 拆因: DB 进 Edge middleware bundle = 全站 500 (2026-09-18 实测回滚过)
- `PATCH /api/me/password`: 自助改密 (验旧密码 + 强度 + 限流 + 审计触发器)
- `DEV_SKIP_AUTH` 加 NODE_ENV 硬门闸 (生产误设也不生效) — middleware + skip-auth
- dev-only `/api/auth/flutter-login`: 改为密码校验; 保留 `code=123456` 兼容旧预览 bundle;
  多账号预览共享密码 `DEV_LOGIN_ANY_PASSWORD` (仅 dev, 生产 endpoint 404)

**脚本 / Flutter**

- `scripts/create-admin.ts` — 管理员建档/重置 (口令只走 env, 明文不落库)
- `scripts/import-users.ts` — CSV 邀请制导入 (幂等; 随机初始密码只打印一次)
- Flutter: 登录页两步验证码 → 一步「账号/手机号 + 密码」;
  `AuthService.changePassword` + 「我的 → 修改密码」弹层 (`showChangePasswordSheet`)

**验证 (2026-09-19, prod 栈 :3004 实测)**

- admin 建档 (id=1) → 正确密码 302 + session; 错误密码不发 session
- 同一 session 调 `/api/me` 200; `PATCH /api/me/password` 200;
  新密码可登录 / 旧密码失效 (临时账号已清理)
- `pnpm test:run` 118/118 (新增 `tests/password.test.ts` + `tests/credentials.test.ts`);
  `pnpm db:compat` / `pnpm type-check` 通过; Flutter analyze 改动文件 0 告警

### Fixed (生产栈 P1: 首次生产构建/全新库部署打通 — 5 个生产路径缺陷, 2026-09-19)

**背景**: 主人 2026-09-19 拍板「先用自有服务器, tc 本机 Docker 隔离」后, 首次真正尝试
生产镜像构建 + 全新库部署。以下缺陷全部只在生产路径暴露, dev 长期运行掩盖了它们。
方案: `docs/deploy/production-plan.md` v2 §3.A。

**1) Docker 构建失败 (pnpm@9 workspace)**

- 根因: `pnpm-workspace.yaml` 缺 `packages` 字段, builder 阶段 `pnpm build` 报
  `packages field missing or empty` → **生产镜像从未构建成功过**。
- 修: 补 `packages: ["."]` (lockfile 本就是 workspace 结构, 仅根 importer)。

**2) 构建期模块加载缺 env (next build "Collecting page data")**

- 根因: `src/lib/db/index.ts` / crypto 在模块加载时校验 env, `next build` 收集页面数据
  会导入全部 route → 缺 `DATABASE_URL` 必炸 (之前卡在更早的 pnpm 错, 从未走到该阶段)。
- 修: builder 阶段注入构建期占位 env (`DATABASE_URL` / `AUTH_SECRET` / `PGCRYPTO_KEY`);
  Next 只内联 `NEXT_PUBLIC_*`, 服务端 env 运行时由 compose 注入, 占位值不进运行时。

**3) 全新库 migration 0010 引用不存在的 audit_trigger() (首部署阻断)**

- 根因: 0010 直接 `EXECUTE FUNCTION audit_trigger()`, 而函数原本在 migration **之后**才创建;
  dev 库因增量历史一直存在该函数, 掩盖了顺序问题。
- 修: 函数定义拆到 `drizzle/audit_function.sql`; `src/lib/db/migrate.ts` 顺序改为
  `[1/4] 创建函数 → [2/4] up migration → [3/4] 挂触发器`。

**4) migrate 容器里 compat 检查静默假通过 (Alpine BusyBox find)**

- 根因: `tools/check-migration-compat.sh` 用 GNU `find -printf`, Alpine 的 BusyBox find
  不支持 → 扫描到 0 个 migration 却输出「✓ 兼容性通过」。
- 修: migrate 镜像 `apk add bash findutils`; 兼容脚本排除表加 `audit_function.sql`。

**5) Next standalone 生产容器 healthcheck 失败**

- 根因: standalone server 默认用 `$HOSTNAME` 绑定, Docker 注入容器 ID 主机名
  → 只监听容器 IP, 容器内 127.0.0.1 healthcheck 一直 unhealthy (宿主访问却 200)。
- 修: prod compose 显式 `HOSTNAME: "0.0.0.0"`。

**新增 (tc 生产隔离栈)**

- `docker-compose.prod.yml` 重写: project `nuankebao-prod`, 容器 `nuankebao-prod-*`,
  卷 `nuankebao-prod-postgres-data` / `nuankebao-prod-uploads`, web 仅绑
  `127.0.0.1:3004`, postgres 不对外, uploads 命名卷, healthcheck, `migrate` tools profile。
- `docker/Dockerfile`: 新增 `migrate` stage; runner 的 `public/` 加 `--chown=nextjs`
  (修复 uploads 因 root 属主不可写)。
- `deploy/prod-deploy.sh`: build → migrate → up → 健康检查 → 失败回滚 (含 rollback 镜像 tag)。
- `.dockerignore` / `.env.prod.example` / `.gitignore` (`.env.prod`, `key.properties`,
  `*.jks`/`*.keystore`)。
- `tools/nuankebao-stack.service` 修正: 用 prod compose + `-p nuankebao-prod --env-file`,
  `Restart=no` (消除失败重启循环; 旧 unit 已在机器上 stop + disable)。
- `src/middleware.ts`: 生产关闭 dev 预览路由 `/app-preview` `/preview` (A6)。

**验证 (2026-09-19)**:

- `docker build` 首发通过; 全新 prod 库 migrate + seed 成功 (24 表 / 12 审计触发器);
  容器 healthcheck `healthy`; `http://127.0.0.1:3004/api/health` 200;
  `/app-preview` → 404, `/login` → 200; uploads 可写; dev 3003 全程 200 未受影响。
- `pnpm test:run` 对全新 `nuankebao_test` 库 (migrate + seed 后): **108/108 通过**。
- `pnpm db:compat` 通过。

### Changed (沙龙列表「创建沙龙」改纯图标 FAB, 2026-09-19 主人拍)

**主人要**: 「创建沙龙改为纯图标」(附图: 带文字的 extended FAB 占地方)。

- 沙龙列表 FAB: `FloatingActionButton.extended` (文字「创建沙龙」) → `BigFab`
  (80pt 圆形 + 加号, 与客户页「添加客户」完全一致; tooltip 保留「创建沙龙」)
- `BigFab` 组件从 `modules/customer/widgets/` 上提到 **`core/widgets/`**
  (客户页 + 沙龙页共用; AGENTS §4.5 禁止跨模块直接 import); 客户页 import + 两处 README 同步
- 验证 (预览页真实浏览器): FAB 语义节点 80×80 (纯图标), 无宽幅文字节点, 0 console error

### Fixed (预览可用性三连修: 多账号身份 / 创建入口路由 / APK 依赖, 2026-09-18 主人要预览)

主人要「所有修改我都要预览」(http://192.168.1.99:3003/app-preview), 实测发现问题并修复:

**1) 多账号身份 (预览沙龙主理人 vs 受邀者互切时, 全部被认成 user 1)**

- 根因链 (三层, 逐层修):
  a. `flutter_web` 登录后 `syncCookiesFromBrowser()` 的 `storage.write` 在 web 平台抛异常
     (flutter_secure_storage 强制 AES) → `onResponse` 拦截器冒泡 → 200 的
     `/api/auth/flutter-login` 响应被当成失败 → `login()` 回退调 Auth.js
     `callback/credentials` → 该路径 W1 mock **恒返回 user 1**, 把正确身份 cookie 覆盖。
  b. `/api/auth/flutter-login` 写死 `DEV_PHONE=13800138000` / `sub:"1"` → 无法签发其他用户。
  c. Auth.js `authorize()` 写死 `id:"1"` (W1 mock)。
- 修法:
  a. `api_client.dart` / `api.dart`: storage 写入降级为「失败即忽略」(web 身份靠内存 token +
     浏览器 cookie; native 路径不变) — 不再触发 callback 回退。
  b. `flutter-login/route.ts`: 新增 `DEV_LOGIN_ANY_USER=1` 开关 (默认关闭) →
     手机号命中 user 表即可签发该用户 token; 未开启时行为与原来完全一致。
  c. **未改** Auth.js authorize (它在 Edge middleware 链路, 引 DB 会让整个站 500 —
     已实测并回滚; 记入本条目避免后人再踩)。
- 验证: 主理人 13800138000 → 详情显示「管理/编辑」; 受邀者 13900000002 →
  「我受邀的」列表出现沙龙 + 详情显示「我的回复/修改我的回复」。auth 请求序列只剩
  csrf + flutter-login (callback 不再触发)。

**2) 创建入口路由 (`/salons/new`, `/customers/new` 打不开)** — 见上一条 Fixed 条目。

**3) APK 无法构建 (今日回归)** — `package_info_plus ^9.0.1` 需 AGP 8.12/Kotlin 2.2,
   与本 app (Flutter 3.24.5 + AGP 8.1) 冲突 → 回退 `^8.0.0` (见 a44c623)。

**预览数据 (dev 库, 可删)**: `预览演示沙龙 (可删)` (id=2, 主理人=1) + 受邀者账号
`13900000002` (user 2, 姓名「预览受邀者」) + 会务 2 人 + 二级客人, 供主理人/受邀者两侧体验。

### Fixed (路由顺序: /salons/new 与 /customers/new 被 :id 抢先匹配 — 预览时主人可复现, 2026-09-18)

**发现**: 主人要预览沙龙, 我用 Flutter Web 预览页 (#/salons/new) 实测发现「创建沙龙」进不去 —
显示「沙龙详情 · 网络不太好」。排查后确认是 **go_router 声明顺序**问题 (不是沙龙新代码引入):

- go_router 按声明顺序匹配; `ShellRoute` 在前时, 其子路由 `/customers/:id`、`/salons/:id`
  会抢先吃掉 `/customers/new`、`/salons/new` (把 `new` 当成 id 去拉详情 → 404 → 错误态)
- 同类: `/franchisees/new` 被前面声明的 `/franchisees/:id` 吃掉
- **影响范围 = 全仓**: 「添加客户」FAB (`context.push('/customers/new')`)、新增加盟商入口
  同样受影响 (pre-existing, 非本次引入)

**修法**: 三个静态 `new` 路由上提到 `ShellRoute` / `:id` 之前声明 (`app_router.dart` 顶部注释
`fix-router-order` 说明原因, 防后人再挪回去)。

**验证** (预览页真实浏览器, 语义树 + 截图):
- `#/salons/new` → 「创建沙龙」4 步向导渲染 ✅
- `#/customers/new` → 「添加客户」表单渲染 ✅
- 沙龙全流程回归: 列表 / 详情 / 管理 / 二级客人 4 页 0 console error ✅

**新增/改动**: `flutter_app/lib/core/router/app_router.dart`。

### Chore (public/app 预览重建: v0.1.5 沙龙 + 路由修复, 2026-09-18 主人要)

主人要预览全部修改 → 按 AGENTS §9.3 SOP 重建 Flutter Web 预览:

- `tools/build-flutter-web.sh --auto` (运行时从 Uri.base 推导 API base; 预览同源 iframe 用)
- 同步 `public/app/` (冻结区, 按 §9.3 用 `--no-verify` 提交, 本 CHANGELOG 条目为留痕)
- version.json bump → 0.2.3#4 (强制 service worker 检测新版本)
- 基线快照测试 `tests/preview-framework-snapshot.test.ts` 19/19 通过 (改前跑)

### Added (沙龙模块: 一级页「沙龙」完整实施 — 列表/详情/创建/RSVP/带约/二级客人, 2026-09-18 主人拍)

**主人要**: 「我们经常会邀约客户参加一些聚会、沙龙、会议。如果生成一个一级页面(与客户、我的平级)……沙龙页主体是沙龙列表。
每个沙龙有他人或公司主理, 用户只是受邀者, 同时可能有邀约任务……也有用户自己主理邀约他人的, 邀约客户/潜在用户或同时也分派给
客户/潜在用户一定的带约人数。沙龙的时间、地址、人数、交通、餐饮、住宿、会务人员安排等都要可以设置, 并且可向受邀者展示详细信息。
受邀者要可以在沙龙详情页有一定量的互动能力, 如填写预计能邀约到的人数等。另外: 服务器数据库中是否应该要有一个所有用户的关系图谱
才能实现多用户联动?……是否应该先把用户关系图谱做好再开始沙龙页的开发?」

**主人拍板 5 项决策 (ask_user)**:

| 决策 | 结果 |
|---|---|
| 一级页命名 | **沙龙** (覆盖 沙龙/讲座/品鉴/答谢/团建/培训; 避开 meeting 商务例会歧义) |
| 关系图谱策略 | **不建统一图谱** — 沙龙用 `user` + `salon_invitation`, 后期用 RelationSystem 接口包装; 沙龙**不必等**图谱 |
| 非 app 受邀者 | **允许** (姓名 + 手机号, 手机号走加密 + hash) |
| 带约机制 | **简单版**: 受邀者自报「预计带约人数」, 主理人手动核对 (不做全链追踪) |
| 本次范围 | **完整方案**: 列表+详情+创建+RSVP+带约任务+二级客人 (+动态/资料) |

**后端 (6 张表 + 14 个 API route)**

- `drizzle/0008_rich_ink.sql` (+`down/0008_rich_ink.down.sql`): `salon` / `salon_invitation` / `salon_quota` / `salon_guest` / `salon_activity` / `salon_attachment` + 6 个枚举
- 审计触发器: `salon` / `salon_invitation` / `salon_guest` / `salon_quota` (见 `drizzle/audit_trigger.sql`)
- 敏感字段: 受邀者/二级客人/订房联系人手机号 → `*_encrypted` + `*_hash` (与 customer 同口径, `hashForLookup` 去重); 受邀者留言加密
- `src/lib/db/queries/salon.ts`: 权限矩阵 (主理人/会务/受邀者) + 可见性过滤 (名单/手机号/留言/公告/资料) + 统计聚合
- `src/lib/salon/validation.ts` + `route-helpers.ts`; 14 个 route: `/api/salons` + `:id` (+cancel/edit) + invitations + rsvp + quotas + guests + activities + attachments + aggregates
- 会务 = `invitation(role=staff)` 行 (不存 jsonb → 手机号可加密); 同沙龙同手机号唯一 (防重复邀请/重复计数)

**Flutter (APK 域)**: `modules/meeting/` → **`modules/salon/`** (`git mv` 历史可追)

- 模型 `core/models/salon.dart` (手写 fromJson, 不依赖 freezed) + `SalonService` + `salon_providers.dart` (`invalidateSalon` 统一刷新)
- 5 个 screen (列表 2 tab / 详情 / 创建编辑 4 步向导 / 主理人管理 3 tab / 二级客人) + 4 个 widget (卡片/状态胶囊/区块/RSVP 弹层)
- Bottom Nav 从 2 tab → **3 tab (客户 / 沙龙 / 我的)**; 路由 `/salons` `:id` `new` `edit` `manage` `guests`

**测试**: `tests/salon.test.ts` 18 例 (权限负例/RSVP/带约进度/二级客人/可见性开关/取消) — 全绿

**顺带修复 (前置漂移)**: `wellness_knowledge.category` 索引在 0001 被误建 UNIQUE (schema 当时写 `uniqueIndex`),
与 0002 手工 migration 原意 / seed (10 条 / 5 类) / 测试冲突 → `0009_free_satana.sql` 修正为普通索引
(dev 库早已是非 unique, 属 schema↔DB 漂移; 修正后 `pnpm test:run` 全绿 108/108)。

**新增/改动文件**

- 后端: `drizzle/0008_rich_ink.sql` `0009_free_satana.sql` (+2 down) / `src/lib/db/schema.ts` / `src/lib/db/queries/salon.ts` /
  `src/lib/salon/{validation,route-helpers}.ts` / `src/app/api/salons/**` (14 route) / `drizzle/audit_trigger.sql`
- Flutter: `core/models/salon.dart` / `core/services/api.dart` (+SalonService) / `core/providers/service_providers.dart` (+salonServiceProvider) /
  `core/router/app_router.dart` (3 tab) / `modules/salon/**` (README + 5 screen + 4 widget + providers)
- 测试/文档: `tests/salon.test.ts` / `AGENTS.md` §4 树 + §4.6 Phase 7 / `docs/adr/0007` Phase 7 注记

**DoD 状态**: `flutter analyze` 0 error / `pnpm test:run` 108/108 pass / API 冒烟 (curl 全 endpoint) 通过 /
`pnpm db:compat` 通过。**待主人**: 真机验收 (APK 构建 + 多用户联动场景)。

### Changed (「我的」页追加: 字号「小」档 + 自定义头像 (上传 / 8 个候选), 2026-09-18 主人要)

**主人要**: 「显示与存储区块。在标准下增加1个：小，比标准小。用户头像要能够自定义（上传头像），
增加几个候选头像供不希望用真人头像的用户选择」

**1) 字号加「小」档 (比标准小)**

| 档位 | 倍率 | 说明 |
|---|---|---|
| **小** (新) | 0.85 (≈15.3pt) | 屏幕小 / 觉得字大一屏看不全 |
| 标准 | 1.0 | 默认 |
| 大 | 1.15 | |
| 特大 | 1.3 | |

- 档位名的字号也体现大小 (小 -2 / 标准 0 / 大 +2 / 特大 +4), 不让用户看倍率数字
- `app.dart` 缩放夹取区间从 `[0.9, 1.6]` 放宽到下界 `0.7` —— 否则系统字号 < 1 时「小」被夹平, 点了没反应

**2) 自定义头像**

| 能力 | 实现 |
|---|---|
| 换头像入口 | 头部头像可点 (带相机角标) + 「换头像」按钮 → 底部弹层 |
| 上传 | 「拍一张」/「从相册选」→ 本地压到 512×512 / q85 → `POST /api/photos` → `PATCH /api/me` |
| 候选头像 | 8 个 (绿叶/花朵/喝茶/静心/爱心/暖阳/养生/清泉), **客户端本地画图标** (不占服务器/不跑流量) |
| 恢复默认 | 一个按钮回到"姓名首字" |
| 存储 | 服务器 `user.avatar_url` (migration `0007_user_avatar_url`, 加性 nullable) — 换手机还在 |
| 安全 | 白名单 `src/lib/avatar.ts`: 只收 `preset:<id>` 与本站 `/uploads/*.(jpg\|png\|webp)`; **拒外链**; `PATCH /api/me` 只接受 `avatarUrl` 一个字段; 写库走 `user_audit` 触发器进审计日志 |
| 渲染兜底 | `core/widgets/user_avatar.dart`: 未知/脏值一律退回首字, 永不出现白框/破图 |

**新增/改动文件**

- 后端: `src/lib/avatar.ts` (新) / `src/app/api/me/route.ts` (+PATCH, GET 回 avatarUrl) /
  `src/lib/db/schema.ts` (+avatarUrl) / `drizzle/0007_user_avatar_url.sql` + `drizzle/down/0007_*.down.sql` (新)
- Flutter: `core/widgets/user_avatar.dart` (新) / `core/models/me.dart` (+avatarUrl) /
  `core/services/api.dart` (+`MeService.updateAvatar`) / `core/providers/settings_provider.dart` (+small) /
  `app.dart` (夹取下界) / `screens/profile_sheets.dart` (+换头像弹层) / `screens/profile_page.dart` (可点头像)
- 测试: `tests/profile-avatar.test.ts` (新, 12 例) / Flutter `test/me_model_test.dart` + `test/profile_page_test.dart`
  + `test/settings_provider_test.dart` 各加用例
- 文档: `docs/api.md §13` (+PATCH /api/me) / `docs/profile-and-settings.md §5.1` (新章节) /
  `docs/user-manual.md` (换头像 + 4 档字号) / `docs/data-model.md` (user.avatar_url)

**验证**

- `npx vitest run tests/profile-avatar.test.ts`: 12 pass (外链/穿越/未知 preset/超长/非字符串 全被拒)
- Flutter `test/user_avatar_test.dart`: 7 pass (8 个候选逐个画出对应图标 / 默认首字 / 脏值退回首字 /
  上传路径退回首字 / presetOf + absoluteAvatarUrl)
- **真浏览器 E2E** (现网 bundle `public/app` + 真 API; 另一个 session 的 rebuild 已带入本轮改动):
  头部语义 = `我的头像, 点击可更换` + `杨`(首字) + `换头像` + `显示完整手机号` + `复制手机号` + `编辑我的资料`;
  点「换头像」→ 弹层 12 项全中: `换个头像 ✓ 拍一张 ✓ 从相册选 ✓ 绿叶 ✓ 花朵 ✓ 喝茶 ✓ 静心 ✓ 爱心 ✓
  暖阳 ✓ 养生 ✓ 清泉 ✓ 恢复默认头像 ✓`; `pageerrors: none`
  (截图 `/tmp/av-e2e-profile.png` + `/tmp/av-e2e-sheet.png`)
- `curl PATCH /api/me`: `preset:leaf` ✓ / 外链 400 ✓ / `preset:hacker` 400 ✓ / 多字段 400 ✓ /
  `/uploads/../../etc/passwd.jpg` 400 ✓ / `null` 恢复默认 ✓; `GET /api/me` 回读一致 ✓
- 审计日志实测有行: `user | UPDATE | user_id=1 | ip=127.0.0.1 | {"avatar_url":"preset:leaf"}`
- `pnpm db:compat` 0 error 0 warning; migration 应用后 `\d user` 有 `avatar_url text` (nullable)
- `flutter analyze` (改动文件) 0 issue; `npx tsc --noEmit` 0 error

### Changed (「我的」页工业级完善: 个人资料 + 加盟身份 + 数据概览 + 系统设置, 2026-09-18 主人要)

**主人要**: 「'我的'页中。丰富个人和系统设置信息。我没有具体要求，你根据当前项目情况做工业级完善」

**落地原刚**: 不摆假开关 —— 每个设置都**真有效果** (字号真变、版本真查、网络真测、缓存真清、
资料真改); 空态 (未加盟 / 统计缺失 / 账号资料不全) 都当**合法状态**渲染, 不是错误页。

**「我的」页现在从上到下** (旧版 = 「我」占位头像 + 3 个数字 + 加盟入口 + 退出):

| 区 | 内容 | 数据源 |
|---|---|---|
| 个人资料 | 真实姓名 (加盟名优先) + 账号名 alias + 角色 + 门店 + 手机号 (**打码**/点👁看全号/📋复制) + 「编辑我的资料」 | `/api/me` |
| 我的加盟身份 | 编号 #75 / 位置 (A线-B线) / 层级 / 路径 / **我的上级** (可点进详情) / 加入时间 / 状态 / **我的下线 N 人 (A线 x · B线 y)** / 备注 | `/api/me` |
| 数据概览 | 客户 / 待办跟进 / 本月拜访 / 本月新增客户 + 累计互动 + 加盟网络入口 | `/api/me` |
| 显示与存储 | **字号 标准/大/特大 (立即生效, 全 App)** + 清理图片缓存 | 本机 prefs |
| 账号与安全 | 登录手机号 (只读+复制) / 30 天登录有效期 / 账号编号 | `/api/me` |
| 关于与帮助 | 当前版本 / **检查更新** (服务器版本+安装包时间/大小+下载+扫码) / 使用帮助+数据安全页 / **网络自检** / 服务地址(debug) | `/api/app-version` + `/api/health` |

**Backend (新增 2 个端点)**
- `GET /api/me` —— 账号 + 加盟身份 (含上级/下线计数) + 门店 + 数据概览, **一次拉完**
  (客户端拼 4 个请求 = 4 个 loading; 服务端一次给一份快照)
- `GET /api/app-version` —— 服务器版本 (pubspec 真源) + 安装包元数据 (时间/大小/md5/下载 URL)
- `queries/dashboard.ts` 新增 `getStatsOverview(ctx | null)`: 支持 RBAC 收紧, **当前传 null**
  以跟客户列表同口径 (列表还没接行级过滤, 否则页面里两条数字互相打脸 —— 切点在函数注释里)
- `queries/franchisee.ts` 新增 `countDirectDownline()` (一次 GROUP BY, 不递归不进 N+1)
- `lib/utils.ts` 新增 `maskPhone()`; `lib/apk.ts` 新增 `parseAppVersionSpec()`

**Flutter**
- 新 `core/models/me.dart` (手写 fromJson, 字段全兜底) + `core/services/api.dart` 新增
  `MeService` / `SystemService` + `providers` 新增 `meProfileProvider` / `appReleaseProvider` / `healthCheckProvider`
- 新 `core/providers/settings_provider.dart`: 字号档位 (标准 1.0 / 大 1.15 / 特大 1.3) 落 `shared_preferences`;
  `main()` 先 `await` 好 prefs 再 runApp (否则首帧标准字号→跳特大, 老人看到闪一下)
- `app.dart`: `builder` 里包 `MediaQuery(textScaler: 用户档位 × 系统字号, 夹在 [0.9, 1.6])`
  —— 尊重手机系统大字设置, 但不允许叠出不可用的界面
- 新 `screens/profile_widgets.dart` (分区卡/条目/信息行/数字框, 统一行高与字号) +
  `screens/profile_sheets.dart` (编辑资料 / 检查更新 / 网络自检 3 个弹层) +
  `screens/about_page.dart` (使用帮助 6 条 + 数据安全 5 条 + 遇到问题)
- `screens/profile_page.dart` 重写; 路由新增 `/profile/about`
- 依赖新增 `shared_preferences` / `package_info_plus` / `flutter_cache_manager` (最后一个本就在依赖树里)
- ❗修三个真 bug (两个是本次 widget 测试当场抓出来的):
  1. `ApiClient.baseUrl` / `baseOrigin` 直接 `Uri.base.origin` —— 非 http(s) 宿主
     (widget 测试 `file://`、native `file://` 漏传 dart-define) 下 `Uri.origin` 抛
     `StateError: Origin is only applicable schemes http and https`, **在 build 阶段把页面打白**。
     改为只认 http/https, 其余退回 dev 默认 origin `http://127.0.0.1:3003`
     (不能退成相对路径 —— dio 在非 web 平台直接 `ArgumentError: Must be a valid URL`,
     而 ApiClient 在 app 启动 (router → provider) 就建好了, 会首帧打挂整个 app)
  2. 个人资料头部手机号行的 2 个 `IconButton` (各 48pt) + 号码文本在窄屏/特大字号下
     水平溢出 30px —— 改 44pt 自绘按钮 + 号码 `Flexible` + ellipsis
  3. ❗**登录页 logo 从来没进过包**: `flutter_app/pubspec.yaml` 只声明 `assets/` ——
     目录声明**不递归**, `assets/icons/nuankebao-logo.png` 一直不在 AssetManifest 里
     (web 产物 `public/app/assets/AssetManifest.json` 里也搜不到它) → 登录页是破图。
     已补 `- assets/icons/` (扫过资产目录, 只有 icons/ 一层子目录)
  4. `flutter_app/test/api_client_test.dart` import 还指向 Plan F2 之前的
     `package:nuankebao/services/api_client.dart` (文件早不存在) —— `flutter test` 整仓跑必红, 已修正路径
- `widget_test.dart` 不 override `sharedPreferencesProvider` 也会挂 (字号设置引入的新前置条件), 已补 override

**验证**
- `flutter analyze` (lib/ + 改动文件): 0 issue
- `flutter test test/me_model_test.dart test/settings_provider_test.dart`: 21 pass (模型空态/脏数据/版本比较/落盘)
- `flutter test test/profile_page_test.dart`: 9 个用例 (四块内容 + 3 种空态 + 「特大」点下去真落盘 +
  **窄屏 320×特大字号滚完整页不溢出**) —— 首次运行当场抓出 2 个真 bug (见上), 修复后复跑
- `flutter test` (全仓): **64 pass / 0 fail** (含 profile_page 9 + api_client 7 + widget_test smoke + 模型/设置/图谱/生日等)
- `npx vitest run tests/profile-utils.test.ts`: 9 pass (maskPhone 不变量 + 版本号解析)
- `npx tsc --noEmit`: 0 error; `curl /api/me` + `/api/app-version`: 返回见 `docs/api.md §13`
- 文档同步: `docs/api.md §13` / `docs/profile-and-settings.md` (新增) / `docs/user-manual.md` 「我的」章节 / `AGENTS.md §4.5`

### Added (客户头像: 详情页头像右下角相机图标 → 候选头像 / 拍照 / 相册, 2026-09-18 主人要)

**主人要**: 「客户详情页，客户头像右下角增加一个相机图标，点击可设置客户头像
(增加几个候选头像供不希望用真人头像的用户选择) 或自拍照或相册上传」

**DB (migration 0007, 已 migrate, compat 0 error/0 warning)**
- `customer.avatar text` (nullable) —— 取值约定跟 `user.avatar_url` **完全一致** (复用 `src/lib/avatar.ts` 白名单):
  `null` = 默认姓名首字 / `preset:<id>` = 内置候选 (前端本地画, **不占存储不跑流量**) /
  `/uploads/x.jpg` = 上传的照片 (复用现成 `POST /api/photos`, 不新增存储设施)
- 拒绝外链 (`https://...`) / 未知候选 id / 目录穿越 → **400** (服务端兼底; 客户端也提前拦)

**Backend**
- `queries/customer.ts`: view/input 加 `avatar`; 写前过 `parseAvatarValue()` (非法值抛错 → 路由转 400);
  读后过 `readAvatarValue()` (库里脏值 → null, 不渲染白框)
- `POST /api/customers` + `PATCH /api/customers/[id]` 接 `avatar` (zod: string ≤300 / nullable)
- 实测: `preset:leaf` 写入 ✓ / 外链 400 ✓ / 未知候选 400 ✓ / `null` 清空 ✓

**Flutter**
- 详情页头部: 头像换成 `UserAvatar` (自动认 照片 / 候选 / 首字) + **右下角绿色相机角标** (32pt,
  带白边, 中老年看得清) + 头像下加一行提示「点头像可以换 (拍照 / 相册 / 现成头像)」
  → 整个头像区可点 (GestureDetector, 触摸区 ≥64pt)
- 弹出的选头像 sheet: **复用「我的」页那套** (`showAvatarPickerSheet`) —— 本次只做**加法**:
  加了可选 `onApply` / `title` / `subtitle` 参数 (默认行为不变), 客户页传自己的保存动作
  (PATCH /api/customers/:id) → 同一套候选头像网格 (8 个养生图标: 绿叶/花朵/喝茶/静心/爱心/暖阳/养生/清泉)
  + 「拍一张」/「从相册选」/ 恢复默认, 不重复造 UI
- 上传前本地压到 ≤512px (头像够用, 网络差也能传上去)、≤3MB; 上传后存 URL
- 客户列表行头像也用 `UserAvatar` (有头像就显示, 列表里关掉 loading 菊花更安静)
- `core/models/customer.dart` 加 `avatar` + 解析白名单 (单测覆盖)

**验证**
- 单测 `flutter_app/test/avatar_parse_test.dart` **4 例全过**: 合法候选保留 / 未知候选→null /
  `/uploads/` 保留 / 目录穿越与外链→null / null与空串→null
- 后端 curl: 4 种情形全对 (上面已列)
- `npx tsc --noEmit` 0 error; `flutter analyze` 改动文件 0 error
- 真浏览器 E2E: 详情页头像 + 相机角标渲染 ✓; 点开 sheet → 「候选头像 花朵」→ PATCH 200 → 头像变成候选
  (截图 `/tmp/nuankebao-detail/avatar-*.png`)

**边界/遗留**: 头像文件本身跟养生照片一样存 `public/uploads/` (无删旧文件机制 → 换头像多了会残留;
后续可加「孤儿文件清理」定时任务); 手机端拍照需真机验证 (web 环境拿不到相机, 会走相册)。

### Changed (编辑客户页: 健康标签候选项 + 生日(年月日/农历) + 生日提醒 + 过敏史, 2026-09-18 主人要)

**主人要** (原文):
- 「健康标签显示一些默认的候选项, 同时支持添加自定义标签, **标签字数限制在 6 个汉字内**」
- 「出生年丰富成年月日, 且支持**选择农历/阳历**, 不明确的可以留空 (比如年月日都不知道就都留空)。如果知道明确的月+日,
  需要有**生日提醒**功能, 填了详细的月+日就等于开启了生日提醒, **提醒强度可以设置: 7天前、3天前、当天**」
- 「增加**既往病史/过敏史** 输入框」

**DB (migration 0006, 已 migrate, compat 0 error/0 warning)**
- `customer`: +`birth_month` / `birth_day` (nullable, 可缺) + `birth_calendar` ('solar'|'lunar', DEFAULT 'solar')
  + `birthday_remind_days` (7/3/0, nullable=不提醒) + `allergy_history_encrypted` (加密)
- 全为加性 + 带 DEFAULT → 老 APK INSERT 不带这些列也能跑; down.sql 已写

**Backend 业务规则** (已 curl 实测)
- `resolveRemindDays()`: **月+日 都有** → 存提醒 (未传则默认 3 天前); 任一为空 → null (不提醒)
- `PATCH {birthMonth: null, birthDay: null}` → 提醒自动置 null ✓ (修了首个版本的 bug: 显式 null 被当成未传)
- 非法提醒强度 (如 5) → **400**; 月/日越界 → 归一化为 null (不让脏数据炸表单)
- zod: `birthMonth 1-12` / `birthDay 1-31` / `birthCalendar enum` / `birthdayRemindDays ∈ {7,3,0}`

**Flutter**
- **健康标签**: 12 个默认候选项 (肩颈僵硬/腰椎不适/膝关节痛/睡眠差/体寒怕冷/湿气重/气血不足/脾胃虚弱/
  手脚冰凉/头晕乏力/更年期/便秘) 点击选中; 已选标签排前面可删; **自定义输入 maxLength=6** +
  「添加」按钮 (去重 + 超长提示, 按 `runes` 计数所以 emoji/多字节字符也准)
- **生日**: 年/月/日 三个独立选择器 (每个都有「不清楚 / 清空」选项 → 允许只知年份或只知月日);
  阳历/农历 `SegmentedButton`; 月+日 都填 → 自动出现「**生日提醒 (已开启)**」区块: `提前 7 天` /
  `提前 3 天` / `生日当天` / `不提醒` (选「不提醒」= 保留月日但不提醒)
- **既往病史 + 过敏史** 两个多行输入框 (详情页过敏史用暖橙警示色块展示)
- **生日提醒落地** (不只是存字段):
  · 新 `core/utils/birthday.dart`: 阳历/农历下次生日 + 倒计时 + 提醒窗口判断
    (农历用 `lunar` 包 — 6tail, **MIT**, pub.dev 1.7.8)
  · 客户列表行: 在提醒窗口内 → 显示 `🎂 3天` 橙色徽章
  · 客户详情页头部: `生日 八月十五 (农历) · 5 天后生日` + `提醒: 提前 7 天 · 下次 2026-09-25`
  · 只填了年份 → 提示「生日未填 (只知道年份 1965) · 填上月日可开启生日提醒」

**验证**
- 单测 `flutter_app/test/birthday_test.dart` **15 例全过**: 阳历倒计时/跨年/2-29 平年按 3-1 算/
  农历锚点用公开常识校验 (**2026 春节 = 2026-02-17**, 2024 中秋 = 2024-09-17, 2026 中秋 = 2026-09-25) /
  文案 (八月十五/腊月三十/正月初二) / 提醒窗口 (7/3/0/null) ✓
- 后端 curl: 农历八月十五 + 提醒 7 天写入→读出 ✓; 默认 3 天 ✓; 清空月日→提醒 null ✓; 非法强度 400 ✓
- `npx tsc --noEmit` 0 error; `flutter analyze lib` 0 error
-
⚠ 环境注: 本次 widget golden / 真浏览器 E2E 因机器内存紧张 (Next.js dev 4G + 同时段其他构建)
  多次超时; 生日逻辑用单测覆盖 (最关键的风险点), 表单渲染与 API 落库以 curl + 代码审阅为准,
  建议主人在真机/预览上点一遗确认 (手改客户 → 填月日 → 选提醒强度 → 保存 → 看列表 🎂 徽章)。

**遗留 (待拍)**: 生日提醒目前只是「标记 + 列表/详情可见」; 真正的「定时提醒」
 (例: 前一天自动建跟进任务 / 推送) 需接一个定时任务 + 通知渠道 (当前无推送基建) —— 建议下一步做。

### Changed (客户详情页内容丰富: 养生记录 + AI 4 卡 + 跟进 + 互动, 2026-09-18 主人要)

**主人要**: 「丰富客户详情页内容（最少要有已打包的最新版本apk中的客户详情项：养生记录、
ai客户画像、ai跟进建议、复购预测、效果分析等，或更多）」

**实现了什么** (客户详情页现在从上到下):

| 区 | 内容 | 数据源 |
|---|---|---|
| 头部 | 头像(类型配色) + 姓名 + **类型徽章**(加盟/种子/普通) + 手机号 + 性别/年龄/建档日 + **健康标签** + 既往病史 + 「**打电话**」/「**记一次互动**」 | customer detail |
| 养生记录 | 汇总(`共 N 次 · 最近 yyyy-MM-dd`) + 最近 5 条 + 「查看全部 N 条」底部弹层 + 「+ 添加记录」 | wellness-records?customerId |
| **AI 助手** | **复购预测**(自动算, 不烧额度) / **AI 跟进建议** / **AI 客户画像** / **效果分析** | /api/ai/* |
| 跟进任务 | 该客户待办 + 一键「完成」+ 新建 | follow-ups?customerId (本次新增) |
| 互动记录 | 电话/微信/到店/节日问候流水 + 计数 | interactions?customerId |

**Flutter**
- 新 `core/models/ai_insight.dart`: `RepurchasePrediction` / `EffectAnalysis` / `CustomerProfileInsight` /
  `FollowUpSuggestion` (手写 fromJson, 字段缺失有兜底, 不引 codegen)
- `AiService` 新增 `profileInsight` / `followUpInsight(reason)` / `repurchasePrediction` / `effectAnalysis` 4 个类型化方法
- 新 `modules/customer/widgets/ai_insight_cards.dart`: 4 张卡 ——
  · **省钱策略**: 复购预测是纯 DB 计算 → 进页自动加载; 其余 3 个烧 MiniMax 额度 → **点了才生成**,
    生成后缓存 + 可重新生成; 失败给明文案 + 重试; mock 数据打「示例数据」标
  · 跟进卡: 原因 ChoiceChip(好久没来/想约到店/节日问候/该复购) → 话术 + 「复制话术」/「建跟进任务」
  · 复购卡: 距上次/平均周期/预计下次三指标 + 置信度 + 预测到期时给「建一条跟进任务」
- 新 `modules/customer/widgets/customer_activity_cards.dart`: 跟进任务区(一键完成) + 互动记录区 +
  **`showAddFollowUpSheet`**(跟进任务弹层) / 记互动弹层(类型 Chip + 备注)
- `providers`: 新增 `customerFollowUpTasksProvider` / `interactionsForCustomerProvider` (按客户, provider 驱动
  以便完成/新增后自动刷新)
- 中老年友好: 卡片标题 18pt / 正文 16pt 行高 1.6 / 按钮 48-56pt / 关键数字用色块凸显

**Backend**
- `GET /api/follow-ups?customerId=` 新增客户过滤 (`listFollowUpTasks({ customerId })`) —— 客户详情页用
- ❗**修一个真 bug: AI 调用静默返回空文本** —— `src/lib/ai/client.ts` 原来用 `@ai-sdk/minimax` +
  `ai@3.4.0` 的 `generateText()`, 实测 `text=""` + `finishReason: stop` + usage 全 null (**不报错**) →
  客户画像/效果分析/跟进话术三个卡片全是空白。根因: provider 包 (`latest`) 与 ai 核心 v3.4 协议不匹配。
  改为**直连 MiniMax Anthropic 兼容端点** (`POST {base}/v1/messages`, `x-api-key` + `anthropic-version`),
  同一把 key; 报错/空文本/超时(60s) 一律回退 mock (页面不会白)。`isAIEnabled()` 同步改用 key 判定。

**验证**
- **真 AI 三连** (dev server + 真 MiniMax key): 跟进话术 118 tokens 真话术 ✓; 客户画像真摘要(含健康/偏好/建议) ✓;
  效果分析真报告(趋势+改善幅度+注意事项) ✓; 三个接口 `aiMock: false` + usage 有值 ✓
- **真浏览器 E2E** (playwright + 隧道 + build 后 /app, 客户 1 王女士, 截图 `/tmp/nuankebao-detail/e2e-*.png`):
  头部 = `王女士 /🟢 普通/139****5678/女/41 岁/建档 2026-09-03/打电话/记一次互动/健康标签(肩颈,睡眠差)` ✓;
  养生记录 = `共 4 次 · 最近 2026-09-16` + 4 条 ✓; AI 助手区 = 复购预测(自动, `GET /api/ai/repurchase-prediction/1` 200)
  + 结果(`重新计算/建一条跟进任务`) + AI 跟进建议(原因 Chips + 生成按钮) + AI 客户画像 + 效果分析 ✓;
  底部 = 跟进任务 + 互动记录 + `新建跟进任务` ✓
- **widget golden** 4 张 (393x852): 顶部 / AI 区 / 生成话术结果 / 底部 (跟进+互动), 断言文案与结构;
  测试帮抓出 1 处 `RenderFlex overflowed 4.3px` (窄屏/大字体下头部计数挤爆) → 已用 `Flexible + ellipsis` 修
- `npx tsc --noEmit` 0 error; vitest `tests/ai-client.test.ts` 5 例 pass

**public/app 重新 build** (`--auto`, preview 冻结路径 §9.3 主人拍); 主人浏览器需 Ctrl+Shift+R。

**遗留**: 真机 APK 上的「拨号」需在手机上验一次 (web 不支持 tel:, 已做失败提示);
AI 卡片的生成结果未做服务端缓存 (每次点都重新生成, 没额度压力再说).

### Changed (加盟树层级**不限** + 图谱懒加载 + 补写 ADR-0006, 2026-09-18 主人拍)

**主人问**: 「层级超过 4 层时（ADR-0010 上限）？我没理解这个限制，层级不应该做限制，理论上是可以无限层级的」

**核实结论** (主人判断正确):
- 数据模型**确实不限层** (`placement_path` 物化路径, 子树查询与层级无关); 只有 3 处人为上限:
  服务层 `franchisee-tree.ts MAX_DEPTH = 4` (**硬拦**) + 接口层 `Math.min(depth, 4)` +
  `schema.ts` 一个**从未 migrate 的 CHECK 注释** (DB 物理无约束)
- 该上限是**合规保守值** (ADR-0006 初值 ≤3 → ADR-0010 缓到 ≤4, 仅为 dev seed 能造 31 位),
  **不是技术限制** → 主人拍板取消
- ⚠ 我上一版 CHANGELOG 「层级 >4 时数字会对不上」**是错的** (第 5 层根本建不出来, 实测 400);
  已更正 (commit `f629119`)

**落地 (主人三件拍板: 层级不限 / 图谱懒加载 / 补写 ADR-0006)**

1. **服务层取消上限** (`src/lib/db/queries/franchisee-tree.ts`):
   - `MAX_DEPTH = Number(env.FRANCHISEE_MAX_DEPTH ?? 0)` → `0` = **不限** (保留运维手闸)
   - BFS 不再按层剪枝 (只在手闸 >0 时剪); 错误文案分「手闸封顶 / 不可能发生」两种
2. **接口层** (`src/app/api/franchisees/me/tree/route.ts`):
   - `depth` 语义从「业务层级上限」改为「**单次请求载荷旋钮**」, 上闸 16 层 (防超大 JSON), 默认 2
   - 树节点新增 `hasChildren` (全深度真值) + 根节点 `totalDescendants` (我的下级全深度总数)
3. **新增懒加载端点** `GET /api/franchisees/:id/children`:
   - 只取直接子级 (带 `hasChildren`), 载荷 O(子级数); 越权拉底 (非我子树 → 空); 软删不计
   - `getFranchiseeChildren(nodeId, viewerFranchiseeId)` — 一次查完下一层标 hasChildren (无 N+1)
4. **Flutter 图谱懒加载** (主人选「按需展开」):
   - 初始只请求 2 层 (`_graphInitialDepth = 2`); 选中节点 → 顶部信息条出「展开下级」/「收起」
   - `_lazyChildren` 缓存 + `_withLazyChildren()` 递归合并 (不 mutate provider 对象);
     `FranchiseeTreeNode.copyWith` + `hasChildren` + `totalDescendants`
   - 顶部计数改为 **`共 N 位 (服务端全深度) · 已展开 M`** → 懒加载不会让数字缩水
   - 顺手修 2 个 UX 嘢: (a) 树变化时不再无脑清选中 (节点还在就保留 → 展开后能直接看到「收起」);
     (b) 展开/收起**不重置相机** (否则每展开一个深节点就被弹回根部)
   - 顺手修图谱筛选胶囊窄屏/3 位数溢出 (圆点 10→8, 字号 14→13, 文本 Flexible+ellipsis)
5. **文档**: 补写缺失的 [ADR-0006 加盟体系 + 合规边界](./adr/0006-franchise-boundary.md) (引用了多年但文件不存在);
   新增 [ADR-0011 加盟树层级不限](./adr/0011-unlimited-franchise-depth.md); ADR-0010 标 Superseded; INDEX 同步

**验证**
- 后端实测 (dev 库): `POST /api/franchisees {referrerId: 90(depth=4)}` → **201**, `placementPath=L.L.L.L.L.`, depth=5 ✓
  (改前同样请求 = 400「深度上限 4 层」); 新加盟商自动生成客户档案 → 列表「加盟」31 == 图谱 `totalDescendants` 31 ✓
- 懒加载端点: `GET /api/franchisees/90/children` → `[{SeedTest-五层验证, depth 5, hasChildren=false}]` ✓
- widget golden: 图谱初始只请 2 层 (断言 `depth == 2`) + 顶部「共 30 位 · 已展开 6」+ 无溢出 ✓
- **真浏览器 E2E** (playwright + 隧道 + build 后 /app + 真后端; 截图 `lazy-*.png`):
  · 初始 `GET .../me/tree?depth=2` 200, 页面 `共 31 位 · 已展开 6` ✓
  · 点第 2 层节点 → 信息条 `陈大壮 · A线 · 下级引荐 · 第2层` + 「展开下级」✓
  · 点展开 → `GET /api/franchisees/78/children` 200 → 按钮变「收起」; 取消选中后 `共 31 位 · 已展开 8` ✓
  · 点收起 → `共 31 位 · 已展开 6` ✓ (完整展开/收起循环)
- `npx tsc --noEmit` 0 error; vitest 25 例 (customer-type 6 + preview snapshot 19) ✓

**public/app 重新 build** (`--auto`); 主人浏览器需 Ctrl+Shift+R 硬刷新。

**遗留 (已记 ADR-0011 §Follow-up)**: 万级节点网络的按层分页/虚拟化 (P2); DB CHECK 兜底 (P3);
对外商用前请律师复核 ADR-0006 §2 合规口径 (P2)。

### Fixed (列表「加盟」与图谱对齐 = 打通加盟商↔客户档案 + 胶囊计数 + 图谱深度 4, 2026-09-18 主人拍)

**主人报**: 「图谱页和列表页中的数据不是同源的吗？当前列表页加盟客户为 0，而图谱页只有 14 个加盟客户」

**根因 (实测)**: 两张表、两套档案，从来没打通

| | 图谱页 | 列表页 |
|---|---|---|
| 数据源 | `franchisee` 表 (加盟商档案) | `customer` 表 (客户档案) |
| seed 数据 | 31 位 (5 层满二叉树) | 15 条 (5 种子 + 10 普通) |
| 交集 | `join on phone_hash` = **0** | → 「加盟」筛出 0 |

- seed 把两拨人建成了不同手机号；建加盟商的流程 (`createFranchisee`) **也不会**顺手建客户档案
- 14 vs 30: 图谱原本请 `depth=3` (画 2+4+8=14 位下级)，而全深度下级是 30 位 →「我的下级」本身也有两个口径

**主人拍**: A 打通数据 + 「加盟」口径 = **我的下级** (跟图谱一致) + 胶囊显示数量 ✅

**1. 打通加盟商 → 客户档案 (方案 A)**
- `queries/customer.ts` 新增 `franchiseeCustomerValues()` (共享 values 构造)
- `createFranchisee()`: **同一事务内**再 insert 一条 customer (onConflictDoNothing on phone_hash)
  → 新建/导入加盟商自动出现在客户列表；幂等 (同手机号已有客户则不动, 不覆盖客户侧数据)
- 新增 `scripts/backfill-franchisee-customers.ts` (回填存量): 支持 `--dry-run` / `--restore-deleted`
  · 实测 dev 库: 新建 27 + 恢复 4 (软删客户会占着 `idx_customer_phone_hash` 唯一索引挡住回填)
  · 现状: 31 位加盟商 ↔ 31 条客户档案全部打通 (活跃客户 15 → 46)
- 边界 (已写进脚本注释): 软删客户会挡住回填 → 默认跳过, `--restore-deleted` 才能恢复
  (删客户可能是有意的); 本次 dev 库被挡的 4 条正是早先的测试行 (含我自建的 `类型验证-*`, 已改回加盟商真名)

**2. 「加盟」口径改成「我的下级」 (跟图谱同口径)**
- `queries/customer.ts`: `myDownlineFranchiseeSql(viewerFranchiseeId)` = `EXISTS(franchisee 同 phone_hash
  AND 该加盟商在我的 placement 子树 AND 不是我 AND 未软删)`，子树判定与 `getPlacementTree` 逐字对齐
  (`path = ''` 根 → 所有 `path <> ''`; 否则 `path LIKE me.path || '%'`)
- 「加盟 = 子查询」当计算列随 SELECT 返回，不再多一次 IN 查询；`resolveCustomerType(row, isMyDownline)` 保持纯函数
- viewer 解析: 新增 `src/lib/auth/viewer.ts` (`resolveViewerFranchiseeId(session.user.id)` → `user.franchisee_id`)
  → 接进 `GET /api/customers`、`GET/PATCH /api/customers/[id]`、`POST /api/customers`
  · 未加盟 / dev 无 session → `null` → 加盟恒 0，种子/普通照常
- **新端点** `GET /api/customers/stats` → `{ all, franchisee, seed, normal }` (支持 `?search=`，跟列表共用同一套
  WHERE 构造 `buildCustomerConditions`，三类互斥穷尽 → 相加 === all)
- Flutter: `CustomerService.typeCounts()` + `customerTypeCountsProvider` (按 search 缓存)；
  胶囊标签带数量 (`全部 46` / `🟣 加盟 30` / `🟢 普通 11` / `🌱 种子 5`，数量未加载时只显文字不闪 0)
- 图谱深度: `myFranchiseeTreeProvider(3)` → **4** (ADR-0010 硬上限; 抽成 `_graphDepth` 常量，注释说明跟「加盟」口径同一份定义)
  —— 否则列表 30 vs 图谱 14 又会对不上

**验证 (全真链路)**
- 后端 (dev server + dev 登录 cookie):
  · `stats` = `{ all: 46, franchisee: 30, seed: 5, normal: 11 }` (30+5+11=46 ✓)
  · `?type=franchisee|seed|normal` total = 30 / 5 / 11，行内 `customerType` 正确 ✓
  · 未登录: 加盟 0, seed 6, normal 40 (46 ✓) — 未加盟 viewer 无下级，符合定义 ✓
  · 建加盟商打通实测: `POST /api/franchisees` (新手机号) → 同事务生成客户档案 ✓ (验证后已软删两个测试行)
  · 建在我下级下 (referrerId=75) 才显示「加盟」；无 referrer = 新 root → 不算我的下级 (符合口径)
    ⚠ 提醒: `add_franchisee_page` 强制选推荐人，所以正常流程不会造出孤立 root
- 单测 `tests/customer-type.test.ts` 6 例 (含优先级 / 未加盟 viewer) ✓; preview snapshot 19 例 ✓
- **真浏览器 E2E** (playwright + 隧道 + 新 build + 真后端; 截图 `/tmp/nuankebao-filter-real/counts-*.png`):
  · semantics 真值: 胶囊 = 「全部 46」「🟣 加盟 30」「🟢 普通 11」「🌱 种子 5」✓
  · 点「加盟」→ `GET /api/customers?type=franchisee` 200 ✓ (列表行显「🟣 加盟」徽章)
  · 切「图谱」→ `GET /api/franchisees/me/tree?depth=4&mode=placement` 200，页面显示 **「共 30 位」**
    → **列表「加盟 30」 === 图谱「共 30 位」** ✓ (主人报的问题闭环)

**public/app 重新 build** (同一任务第二次; `--auto`, `pnpm test tests/preview-framework-snapshot.test.ts` 19 passed)
主人浏览器需 Ctrl+Shift+R 硬刷新。

**遗留/澄清**
- viewer 自己的客户档案 (本人) 落在「普通」桶里 (加盟 = 下级, 不含自己)；
  若不想看到自己，可后续加「排除自己」规则 (需主人拍，会影响 all 计数口径)
- **更正 (2026-09-18 晚, 主人追问层级上限后核实)**: 上一版本条目写过「层级超过 4 层时胶囊数字会大于图谱
  节点数」—— **这句是错的**: 第 5 层根本建不出来。实测 `POST /api/franchisees` referrerId=depth4 节点 →
  HTTP 400「加盟树深度上限 4 层 (ADR-0010)」；所以胶囊数不可能超过 depth=4 能画出的节点数。
  该限制位于 `franchisee-tree.ts: MAX_DEPTH = 4` (服务层) + `me/tree route: Math.min(depth, 4)` (接口层)
  + `schema.ts` 里一个**未实际 migrate 到 DB 的 CHECK 注释**。它源自 ADR-0006 的合规红线 (《禁止传销条例》)
  —— 即 **合规约束，不是技术约束**；要不要放开已单独 ask 主人 (待拍)

### Fixed (DEV_SKIP_AUTH 白名单全仓补齐 + migration 进 git + build 脚本 --auto 修复, 2026-09-18 主人拍)

上一条列了 4 个发现, 主人拍: 全仓补 auth skip ✅ / migration 进 git ✅ / build 脚本修 ✅ / dev 免密登录**接受风险** ⚠

**1. API route `isAuthSkipped()` 全仓补齐 (11 个文件)**
- 之前只有 10 个 route 支持 `DEV_SKIP_AUTH=1`; 其余 12 个 dev 模式仍 401 (同目录路由行为不一致)
- 本次: `ai/effect-analysis|profile|repurchase-prediction/[id]`、`apk-download`、`apk-qr`、
  `dashboard/stats`、`import/customers`、`import/template`、`interactions`、`reports/overview`、
  `wellness-records/[id]` (上轮已修 `customers/[id]`) → 每个 = 1 行 import + `!isAuthSkipped() &&`
- **并发修正** (TS 收窄丢失): 放开 guard 后 `session` 可为 null, `import/customers` 与 `interactions`
  的 `BigInt(session.user.id)` 改为 `session?.user?.id ? BigInt(session.user.id) : BigInt(0)`
  (跟 `customers/route.ts` 已约定一致; createdBy=0 = dev 写入)
- **验证**: `npx tsc --noEmit` 0 error; dev server 实测 `dashboard/stats` `reports/overview` `import/template`
  `apk-download` `apk-qr` `ai/profile/1` `wellness-records/1` `franchisees` `customers?type=seed` 全 200
  (改前这些接口 dev 模式全是 401); 生产不设 `DEV_SKIP_AUTH` → `isAuthSkipped()=false` → 行为不变

**2. migration 进 git (以前整个 `drizzle/` 被 `.gitignore` 挡住)**
- 根因: `.gitignore` 的 `*.sql` + `drizzle/meta/` + `drizzle/*.json` 把整个目录遮了 →
  7 个 migration + 3 个 down.sql + `meta/` 快照**从未入过 git** (`git ls-files drizzle/` 为空)
  → git clone 拿不到 migration, CI `db:compat` 也扫不到东西
- 修复: `.gitignore` 加负向规则 (`!drizzle/*.sql` / `!drizzle/down/*.sql` / `!drizzle/meta/` /
  `!drizzle/meta/*.json` / `!drizzle/audit_trigger.sql`), **负向规则必须紧跟被忽略的目录本身**
  (否则 git 不会下沉看子文件); `*.sql.gz` / `*.sql.gpg` 仍忽略 (备份副本)
- 补登 16 个文件 (8 个 up + 3 个 down + audit_trigger + 4 个 meta); 已扫无密钥泄漏

**3. `tools/build-flutter-web.sh --auto` 的 `set -e` bug 修复** (preview 冻结文件 → 主人拍 + `--no-verify`)
- 根因: `DART_DEFINE` 为空时 `EXPECTED_IP=$(echo "" | grep -oE ...)` 返回 1 → `set -e` 直接退出,
  **永不同步到 `public/app/`** (上轮「--auto 后预览没变」就是这个)
- 修: 赋值处兜 `|| true` (+ 注释记录原因/拍板来源)
- **验证 (全流程真跑一次)**: `bash tools/build-flutter-web.sh --auto` 跑到底 →
  `✓ 含 Uri.base / location.origin` → `✓ 已同步` → `✓ version.json bump` → `✓ SW hash` → 总结打印 ✓;
  再用 playwright 跑新 bundle 的 E2E (`?type=seed` / `?type=franchisee` 全 200) ✓
- 顺带观察 (未改, 不是本次范围): 脚本 bump version 时读的是 `flutter build web` 刚写回的
  pubspec 版本 (`0.2.2#3`) → 每次 build 都 bump 成 `0.2.3#4` (**非单调**, 连续两次 build 版本相同)。
  实际无人消费该字段 (grep 全仓只有 preview 测试校验格式), SW 缓存破坏靠 `flutter_service_worker.js` hash (已正确更新)

**4. dev 免密登录公网可达 — 主人拍「接受风险」(未改) ⚠**
- `/api/auth/flutter-login` 在 `NODE_ENV != production` 用 `13800138000 / 123456` 直发 JWT;
  dev 机经 cloudflared 隧道**公网可达** → 知道地址就能拿 session (本次 E2E 即利用此路径)
- 主人 2026-09-18 ask 拍「先保持 (我知道风险)」→ 不动, 仅留档
- 将来要关时的候选: 加 dev secret header / 只允许 127.0.0.1 或 LAN 网段 / 隧道层墙掉该 path

### Changed (客户列表胶囊筛选 + 客户类型 (加盟/种子/普通) 真过滤, 2026-09-18 主人拍)

**主人要**: 「客户.列表页。把搜索栏正面的筛选标签(全部、加盟、普通、种子)组合成胶囊按键」
→ 主人追加拍板: (1) 重新 build web (2) 胶囊接**真过滤** (3) 行徽章显示真实类型

**类型判定 = 混合方案 C** (主人选):

| 类型 | 判定 | 存字段? |
|---|---|---|
| 🟣 加盟 franchisee | **派生** = `franchisee` 表存在同 `phone_hash` 且未软删的记录 | ❌ (不冗余存) |
| 🌱 种子 seed | **显式** = `customer.is_seed = true` (表格勾选) | ✅ `is_seed` |
| 🟢 普通 normal | 其余 (默认) | ❌ |

优先级 **加盟 > 种子 > 普通** (已加盟的客户即使误标种子也显示「加盟」——加盟是事实关系, 更强)

**Backend**
- `drizzle/0005_customer_is_seed.sql` + `drizzle/down/0005_customer_is_seed.down.sql`:
  `ALTER TABLE customer ADD COLUMN is_seed boolean NOT NULL DEFAULT false`
  → ✅ 加性 + 带 DEFAULT (老 APK INSERT 不带该列也能跑), `pnpm db:compat` 0 error / 0 warning,
  已 `pnpm db:migrate` 应用到 dev 库 (存量 15 行自动 false = 跟改动前行为一致)
- `src/lib/db/queries/customer.ts`:
  - `CustomerView` 加 `isSeed` + `customerType`; 删 `resolveCustomerType()` (纯函数, 单测覆盖)
  - `loadFranchiseePhoneHashes()`: 列表一次 IN 查完 (避免 N+1), create/get/update 单条也走同一函数
  - `listCustomers({ type })`: `franchisee` = `EXISTS (franchisee 同 phone_hash)`, `seed` = `is_seed AND NOT EXISTS(...)`,
    `normal` = `NOT is_seed AND NOT EXISTS(...)`, `all`/缺省 = 不筛 (老客户端零影响)
  - create/update 接 `isSeed`
- `GET /api/customers?type=` (zod 枚举, **非法值 → 400** 不静默降级); `POST` / `PATCH` 接 `isSeed`
- **顺手修**: `src/app/api/customers/[id]/route.ts` 缺 `isAuthSkipped()` 检查 → dev 模式 (DEV_SKIP_AUTH=1)
  GET/PATCH/DELETE 全 401, 跟同目录 `customers/route.ts` 不一致。⚠ 全仓还有 11 个 route 同样缺该检查
  (ai/*, dashboard, import/*, interactions, reports, wellness-records/[id], apk-*), 本次**未改** (避免扩大爆炸半径), 待主人定

**Flutter**
- `core/models/customer.dart`: freezed 加 `isSeed` (@Default false) + `customerType` (@Default 'normal') → 老后端不返回也不崩
- `core/providers/service_providers.dart`: `customersProvider` family 从 `String?` 换 `CustomerListQuery{search,type}`
  (== / hashCode 控制重取); 顺手删掉遗留未用的 `_CustomerQuery`
- `core/services/api.dart`: `CustomerService.list({search, type})` → `?type=` (all 不发)
- `modules/customer/screens/customers_page.dart`:
  - 胶囊 = `SegmentedButton` 4 段 + `expandedInsets: EdgeInsets.zero` (4 段平分 361pt, 跟图谱筛选同一组件同一样式)
  - 删 `_buildChip()` + `_applyFilter()` (本地全量返回的 TODO) → 真过滤走后端
  - 空状态分场景文案 (筛出 0 条: 「没有加盟客户 / 换个筛选看看, 或点「全部」」)
  - 行徽章/头像色按 `customerType` 渲染 (加盟紫 / 种子橙 / 普通绿)
  - 表单加 **「🌱 种子客户」SwitchListTile** (勾选 → payload `isSeed`, 编辑页回填)
- `core/widgets/franchise_chip.dart`: 加 `seed` 变体 (暖橙)
- `customer_row.dart`: `isFranchisee` 降为 deprecated 兼容参数, 新增 `customerType`
- `scripts/seed-test-data.ts`: 种子客户 payload 补 `isSeed` (之前只建数据不打标 → `?type=seed` 筛不出)

**验证** (工具: vitest + flutter test golden + playwright 真浏览器; 临时验证文件已删)
- 单测 `tests/customer-type.test.ts` (6 例): 加盟 / 种子 / 普通 / **加盟 > 种子** 优先级 / 枚举契约 ✓
- API (curl, dev server):
  `all=15, franchisee=0, seed=5, normal=10` (总和 = all ✓) → 建 3 条测试数据后
  `all=20, franchisee=4, seed=6, normal=10`; 非法 `?type=bogus` → **400** ✓; 不传 type 行为跟改动前一致 ✓
  · 测试含「已加盟 + 标种子」→ 仍显示 franchisee (优先级生效) ✓ 测试后 5 条软删回滚 (audit log 全程有记录)
- **真机尺寸 golden** (393x852, widget): 三类徽章颜色分区 (紫/橙/绿) + 点胶囊后只剩对应类 ✓
  并断言 Flutter 真把 `type=seed` / `type=normal` 传下去, 「全部」不发 type ✓
- **真浏览器 E2E** (playwright + 隧道 + build 后的 /app + 真后端, 截图 `/tmp/nuankebao-filter-real/preview-*.png`):
  初始 `GET /api/customers?limit=50` → 点「🌱 种子」`?type=seed` → 点「🟣 加盟」`?type=franchisee` → 回「全部」(缓存命中不重发)
  截图像素分析: 全量 = 5 普通绿徽章 + 2 种子橙徽章 (屏内); 筛种子 = 5 橙徽章无绿徽章; 筛加盟 = 空状态页 ✓
- `flutter analyze` 改动文件 0 issue; `npx tsc --noEmit` 0 error
  (注: `flutter test` 其他单测 + `tests/integration*.test.ts` 是**改动前就挂**的——前者引用已删的 `services/api_client.dart`,
  后者要 `DATABASE_URL` 指测试库, 非本次回归)

**public/app 重新 build** (主人拍): 新 build = **`--auto` 模式** (不写死 IP, 运行时从 `Uri.base.origin` 推导 API base)
→ 预览页同源调 API, 不再出现「隧道 https 页面调 http://192.168.1.200:3003 被浏览器拦 (mixed content)」;
version.json `0.2.11#12 → 0.2.12#13` + SW hash 已 bump (主人侧需 Ctrl+Shift+R 硬刷新)

**⚠ 发现 (已处理/已拍, 详见上一条 2026-09-18 修复条目)**
1. ~~`tools/build-flutter-web.sh --auto` 有 `set -e` bug~~ → ✅ 已修 (主人拍, `--no-verify` + 全流程实测)
2. ~~`/api/auth/flutter-login` dev 免密 + 公网可达~~ → ⚠ 主人拍「接受风险, 先保持」, 留档不改

### Changed (客户列表筛选 = 胶囊按键 4 段 — UI 部分, 2026-09-18 主人拍)

- 上面那条的 UI 部分 (胶囊按键); 当时「真过滤 + 重新 build」还没拍, 主人后拍后已并入上一条
- 截图: `/tmp/nuankebao-filter-capsule/*.png` (列表默认态 / 点「普通」后 / 放大裁剪)

### Verified (布局不强制对称 — 自由生长, 2026-09-17 主人问)

**主人问**: 「当前的 a、b 两线客户都是 15 个, 且完全对称。对称不是强制的吧, 实际生产模式中节点
应该是按用户设置自由生长的」

**答: 不强制。15/15 对称来自测试种子数据, 不是布局约束**
- 数据源: `scripts/seed-test-data.ts` 按「31 节点满二叉树」造数据 (L1: 左右各 1, L2: 各 2 …
  ADR-0010 的 30+ 需求), 所以图谱看起来完全对称; 图谱只渲染 depth=3 → 15 个节点
- 生产真实生长: `placeNewFranchisee()` 先填左位 → 左满填右位 → 两侧都满则 BFS 往下找空位
  (`src/lib/db/queries/franchisee-tree.ts`), 天生歪斜不对称; 布局完全跟着数据走

**验证 (新增 4 个不对称单测, `flutter_app/test/graph_layout_test.dart`, 7/7 pass)**
1. A线 6 层 / B线 2 层 → 各走各的, **不补齐不镜像** (A 线 y 延伸更长)
2. 只有 A 线 (根只有左子) → B线集合为空, 不报错, 根仍居中
3. 只有 B 线 + 单侧链 → 同侧断了用另一侧接主线, 主线仍竖直
4. 混合型 (左长+侧枝, 右短) → 任意两节点中心距 ≥ 60% 半径和 (不叠死)

**顺手修**: 画布宽度兜底 (最小 400) 生效时内容没居中 → 只有一条腿时会偏心, 现已按
`canvasWidth/2 - halfWidth` 补偿

**实操演示**: Playwright 拦截 `/franchisees/me/tree` 喂一棵「A线 6 层 + B线 2 层」的自由生长树,
App 渲染正常 (截图 `/tmp/asym-1-default.png` / `/tmp/asym-2-fit.png`); 视觉 QA 确认两腿长度明显不同、
各自的列仍竖直

### Chore (public/app 完整重建 — 等另一会话收尾后补, 2026-09-18 主人拍)

- 时点: 另一会话的「客户头像」WIP 在 13:28 修掉最后一个编译错误 (`flutter analyze lib` 0 error) 后,
  14:05 他们自己的 `flutter build web` 完成 → 本次直接复用该产物 + 补 version.json + 校验 SW hash
  (13:38 时两边同时 build 撞车过一次, 我这边主动 kill 自己的, 让他们的跑完)
- `public/app/main.dart.js` = 3,111,825 bytes; SW hash == md5 ✓; version.json → **0.2.5#6**
- 产物 = 当前工作区状态 (含: 折叠策略 / 编辑页路由 / 三维区分 / 紧凑布局 + 其他会话未提交的
  客户头像 WIP), 他们后续继续改动会让产物再次变旧, 需要时再重建

**验证** (Playwright + `/app/`): 图谱页可达; 信息条「共 31 位」(= 不折叠模式, 全树已展开);
胶囊 4 段 `全部 / A线 16 / B线 15 / 直推 2` —— **A/B 已不再对称** (新增的「SeedTest-五层验证」挂在 A 线),
布局按数据自由生长 ✓

### Added (客户列表跟进 P1: 提醒条 + 分组折叠 + 每日任务生成, 2026-09-20 继续)

- **顶部提醒条** (仅会员, `summary` 有值才显示): `🔴 今天要联系 3 位 · 逾期 1 位 · 本周 5 位`;
  没有紧急客户时显示 `🟢 节奏都很稳，没有要紧急联系的客户` (不空着, 也不吓人)
- **分组折叠**: 紧急度排序下按 P0-P4 分组 (`🔴 今天必须联系 (3)` … `⚪ 休眠池 (12)`),
  表头 = 色点 + 文案 + 计数 + 展开/收起箭头; **休眠池默认折叠**; 其它排序保持平铺
- **`GET /api/customers` 增加 `summary`** (`dueToday/overdue/thisWeek/hibernating/total`, 仅会员 —
  与紧急度同一判权, 非会员不下发)
- **手写模型 `FollowUpSummary`** (继续绕开 build_runner)
- **`scripts/refresh-follow-up-tasks.ts`** (主人 Q4: 自动建 + 7 天去重):
  - 只落**免费信号** (距上次联系 > 15 天 / 新客未首访), 生日/复购属会员能力不在 cron 生成
  - 一人同时只留一条 pending; 7 天内建过 (含已完成) → 跳过; `--dry-run` 可预演; `LIMIT` 可限量
  - **实测**: 造「70 天没联系 / 120 天没到店」客户 → 识别 65 分 → 建 1 条 → 再跑输出「✅ 无需新建 (幂等)」

### Added (客户列表跟进 P0 前端: 色条 + 推荐标签 + 排序胶囊, 2026-09-20 主人拍)

主人: 「做：是否继续做 P0 前端（客户行：左色条 + 名字右侧标签 + 「21 天没联系」第二行；
排序胶囊「紧急🔒/最近/姓名」）—— 我建议直接做，用手写模型绕开代码生成」

**手写模型 (绕开坏掉的 build_runner)**:
- 新 `core/models/follow_up_info.dart` — **纯手写 fromJson, 不用 freezed/json_serializable**:
  `FollowUpInfo` / `FollowUpTagInfo` / `CustomerWithFollowUp` / `CustomerListResult`
  (+ `contactLine` 生成「21 天没联系 · 上次电话」、「还没联系过」、「今天联系过」等第二行文案)
- `core/services/api.dart::list()` 返回 `CustomerListResult` (含 items/total/sort/urgencyLocked) + 支持 `sort` 参数
- `customersProvider` 的 `CustomerListQuery` 增加 `sort` (参与 == / hashCode, 换排序会重新拉数据)

**客户行 (`CustomerRow`)**:
- **左色条 4pt** (P0 红 / P1 橙 / P2 暖黄 / P3 绿 / P4 灰) —— **仅会员** (Q1: 色条属紧急度体系)
- **名字右侧推荐标签**: 胶囊 (底色 14% 透明 + 同色文字 + tooltip 说明), 最多 2 个 (动作 + 日历)
- **第二行**: 跟进信息优先 (`21 天没联系 · 上次电话`, P0/P1 加粗) → 退回 上级 / 上次到店
- 类型头像 (🤝/🌱/👤) 与 🎂 生日徽章保持不变 (生日标签与徽章不重复: 会员走标签, 非会员走旧徽章)

**排序胶囊** (`客户`列表视图): `🔥紧急 / 最近联系 / 最近添加 / 姓名`
- 非会员: 紧急项显示 **🔒**, 点击弹说明「「紧急度排序」是会员功能：开通后自动按「今天该先联系谁」排好」,
  且不切换排序 (后端也会降级并回 `urgencyLocked`, 前端以后端决议为准 — 不用前端判权)

**验证**: `flutter analyze lib` 0 error (3 条既有 info) ✓; P0 后端接口已实测 (会员/非会员两条路径) ✓

### Added (待办 Backlog 文档 + build_runner 诊断, 2026-09-20 主人点名)

- 新文档 [`docs/backlog.md`](docs/backlog.md): 主人点名「记住这个任务」的条目集中落点
  - **① 原始加盟节点启动 (Bootstrap Root)** ⏳ 待做 (排在跟进引擎之后):
    背景 (全新树无根 → 现有规则死锁) / 现状核查 (老 `POST /api/franchisees` 能力在但 App 无入口) /
    4 个方案 (推荐 A: 管理员建根, 免多方确认、后续节点照旧三方确认) / 4 个待拍板问题 / 实现清单
  - **② build_runner 不可用** 🔧 排查中: 现象 / 根因线索 / 临时绕行 (生成物随 git 提交, 从 git 恢复) / 候选修法
- build_runner 诊断记录: `build_resolvers` 需先生成 `.dart_tool/build_resolvers/sdk.sum` + `.deps`;
  本机生成极慢/无输出, 多实例并发会互相锁; 已清理僵尸进程, 未强推修复 (避免动 lockfile 影响他人)
- 环境修复: Flutter dev server 被我清理进程时误杀 → 已重启 (8080 → 200)

### Added (客户列表跟进引擎 P0 后端: 紧急度 + 推荐标签 + 排序, 2026-09-20 主人拍板)

主人拍板 7 条 (方案 `docs/follow-up-list-plan.md`): 紧急度排序只给会员 (Q1) / 标签最多 2 个 (Q2) /
动作文案 (Q3) / 自动建任务 + 7 天去重 (Q4) / 要本地通知 (Q6) / 加盟商轻微加权 (Q7) / 不做跟进 Tab (Q8)

**P0 后端 (本次)**:
- **迁移 `0016_follow_up_timestamps.sql`** (additive): `customer.last_interaction_at` /
  `last_visit_at` + 2 索引 (+ `down/` 回滚 + `pnpm db:compat` 通过)
- **`src/lib/follow-up/urgency.ts`** (纯函数, 单一真相): 9 信号 (任务逾期/今天到期/距上次联系分档/
  新客未联系/超期未到店/生日窗口/复购窗口/类型加权) → 0-100 分 → P0-P4 + 理由 + 标签 (≤2, 动作文案)
- **`src/lib/follow-up/birthday.ts`**: 阳历生日窗口 (农历服务端暂不支持 → null, 由客户端展示)
- **`scripts/backfill-last-contact.ts`**: 存量回填冗余列 (幂等 + `--dry-run`) —— 已跑: 上次联系 1 行 / 上次到店 10 行
- **写路径维护**: 记互动 (`createInteraction`) / 记养生记录 (`createWellnessRecord`) 同事务刷新冗余列 (GREATEST, 只前推)
- **`GET /api/customers`**: 新增 `sort` (urgency|recent|new|name) + 每行 `followUp` 块
  (天数/标签/待办数; **分数·级别·理由仅会员** → 非会员 `urgencyLocked: true` 且降级为 new) +
  `CustomerView` 补 `lastInteractionAt/lastVisitAt`
- **`src/lib/follow-up/attach.ts`**: 批量挂 followUp + 紧急度排序 (内存排序, 上限 2000, 见方案 §13 规模说明)
- **单测 `tests/follow-up-urgency.test.ts`**: 33 例全过 (分档/封顶/叠加/加权/标签优先级/文案长度/生日窗口边界)

**实测** (dev):
- 会员 `sort=urgency`: 王女士 紧急=60 p1 🔥该回访了 · 理由「跟进任务逾期 50 天」; 新客 🌟新客首访 ✓
- 非会员 `sort=urgency`: `sort=new` + `urgencyLocked=true` + 分数=null, 但**免费标签照给** (15 个客户有标签) ✓

### Added (客户列表跟进引擎 — 完整方案文档, 2026-09-20 主人要「先给方案」)

- 新文档 [`docs/follow-up-list-plan.md`](docs/follow-up-list-plan.md)（15 节）:
  紧急度模型 (9 信号 + 5 分级 + 可解释理由) / 推荐标签清单 / 三层提醒 (列表条·待办页·本地通知) /
  排序分组规则 / 跟进分析指标 / 数据模型 (2 个 additive 列 + 回填) / API 契约 (followUp 块) /
  Flutter UI 规范 / 会员判权表 / P0-P3 分期 / 风险对策 / **8 项待拍板**
- 现状盘点结论: `follow_up_task`+`interaction`+AI 四件套**已有**; 缺 = 列表排序(仍 created_at DESC)、
  紧急度、上次联系字段、名字右侧标签、分组、待办页、推送插件、`modules/follow_up/` 空壳
- **未写任何业务代码**（等主人拍板 §14 八问）

### Added (自助注册补建档 + 管理员脚本合并, 2026-09-20 主人拍)

主人: 「另一个 session 改它建号时没建客户档案，它已完成自助注册页面，你补上建号时建客户档案，
提供推荐码的用户其客户列表中自动多出一个普通客户（新注册的用户）。合并管理员脚本现在的两个」

**① 自助注册 (B1) 补「建号即建档」**
- `src/lib/billing/signup.ts::registerWithReferral`: 建 user + **建客户档案** 收进**同一事务** (`withAuditContext`)
  - `is_seed=false` → 列表口径就是**普通客户**
  - `customer.referrer_id` = **推荐人的客户档案**（有则挂; 推荐人还没档案就先空着, 不阻塞注册）
  - `created_by` = 推荐人 (谁带进来的)
  - 同手机号已有客户档案 → 复用不重复建
- 顺带把该文件的 `user` 表引用统一成 `userTable` (与 `user` 变量名不再混淆)

**② 管理员脚本二合一** (`scripts/ensure-admin.ts`, 删除 `scripts/create-admin.ts`)
- 一个入口管: 建档 / 提权 / **重置密码** / 补档案 (客户档案 + 推荐码)
- 环境变量: `ADMIN_PHONE` / `ADMIN_NAME` / `ADMIN_USERNAME` / `ADMIN_PASSWORD` (+ CLI `--phone=` `--name=` `--username=` `--password=`)
- 幂等: 命中已有账号 → 抬 role + (给了密码就重置); 没命中 → 新建
- 文档同步: `docs/deploy.md`(§2 表格 + §7.5) / `docs/deploy/production-plan.md` B7

**验证**:
- 新冒烟 `scripts/smoke-signup.ts` (6/6 过): 建号建档 / 挂在推荐人名下 / 列表口径=普通 / 重复号被拒
- HTTP 层 (走 `/api/auth/register`): 201 → 客户列表 `search=HTTP注册测试` 返回 **类型 normal + 推荐人 145** ✓
- 管理员脚本三条路径验过: 已存在(admin) 跳过 ✓ / 新建(带用户名密码) ✓ / 再跑幂等+重置密码 ✓
- `npx tsc --noEmit` 0 error; 测试账号已清理 ✓

### Added (账号 = 客户: 建号即强制建档 + 推荐码必填 + 存量补齐, 2026-09-19 主人拍)

主人问: 「用户网络和加盟网络是打通的吗。每个用户首先都肯定是另一个用户的客户」
→ 查真实数据发现: 加盟→客户 32/32 打通 ✅, 但**账号→客户档案 0/7** ❌ (只靠手机号 hash 约定),
推荐码只有 2/7 账号有, 无推荐人客户 38/47 → 「每个用户都是别人的客户」**当时不成立**。
主人拍板三条 (详见 [ADR-0013](docs/adr/0013-account-customer-binding.md)):

- **① 建号即强制建档** — 新 `src/lib/auth/registration.ts::createAccountWithProfile()` 为唯一建号入口:
  事务内建 user + 建/复用 customer 档案; 补 `ensureAccountProfile()` (给已存在账号补档案, 幂等)
- **② 推荐码必填** (admin/根可空) — 主人: 「推荐码作为用户账户最强身份识别码」
  `scripts/import-users.ts` 的 CSV `referral_code` 从"选填"→**必填** (admin 行可空) + `--allow-missing-referral` 逃生舱;
  `scripts/ensure-admin.ts` 顺带补齐档案 + 推荐码
- **③ no_link** — 推荐码**不写** `customer.referrer_id` (账号推荐关系 ≠ 客户图谱老带新, 两条线独立)
- **④ 存量补齐** — 新 `scripts/backfill-account-customer-link.ts` (幂等 + `--dry-run`):
  账号补档案 (+推荐码) + 无推荐人客户挂到「门店/根」
- 冒烟 `scripts/smoke-registration.ts`: 无码被拒 / 建档成功 / 码归属 / no_link / 重复号 409 / admin 豁免 (8/8 过)

**实测结果**: 账号 **7/7** 有客户档案、**7/7** 有推荐码; 无推荐人客户 **0** (44 个挂到根 #47) ✅

### Changed (类别图标重设计 + 纯 emoji 角标 (三类都显示), 2026-09-19 主人拍)

主人原话: 「纯 emoji 角标。加盟、普通、种子都要显示角标。重新设计类别图标
（当前的几个不贴合类别名，也不够高级、简洁）」

**新类别图标语汇 (全 App 统一: 头像角标 + 胶囊 chip + 筛选胶囊 + 分段按钮)**:

| 类型 | 新图标 | 语义 | 旧图标 |
|---|---|---|---|
| 加盟 | 🤝 | 正式加入合作网络 (握手) | 🟣 (只是一个颜色圆) |
| 种子 | 🌱 | 还在萌芽的潜在客户 | 🌱 (保留: 语义本来就准) |
| 普通 | 👤 | 一个普通的人 (中性剪影) | 🟢 (只是一个颜色圆) |

- 旧版 🟣/🟢 的问题: 它们只是"一个颜色圆", 不表达任何类别含义 → 换成有语义的图形
- `franchise_chip.dart` + `customers_page.dart` 的筛选胶囊/分段按钮/文案同步换

**头像角标 (纯 emoji, 三类都显示)**:
- 🤝 加盟: 紫色环 + 紫底 emoji 角标; 🌱 种子: 橙环 + 橙底角标; 👤 普通: **无环** + 浅灰底角标
- 视觉重量刻意分层 (加盟/种子带环 = 更重; 普通只有浅灰角标 = 最轻但**仍可辨识**)
- emoji 字号 = 角标直径 × 0.62 (emoji 自带留白, 比汉字要大一号才看得清)

**验证** (dev server 列表截图 + 像素扫描):
- 语义: 「SeedTest-杨翠萍, 加盟商」+ 角标 emoji 🤝 ✓
- 像素: 紫(加盟环+角标) 16164 / 橙(种子) 2312 / 灰(普通角标) 1876 ✓
- `flutter analyze lib` 0 error ✓

### Changed (客户列表: 类型标签 → 头像区分, 2026-09-19 主人拍)

主人原话: 「客户类型（加盟、普通、种子）在客户列表中不显示类型标签，类型在头像上区分」
→ 方案由我建议 + 实现 (见下), 主人可随时改风格

**方案 (颜色 + 汉字双编码, 不靠颜色单打一)**:

| 类型 | 头像环 | 右下角徽章 | 底色 |
|---|---|---|---|
| 加盟 `franchisee` | 紫色 2.5pt 环 | 紫色圆 + 白色「盟」 | (头像本体不变) |
| 种子 `seed` | 暖橙 2pt 环 | 暖橙圆 + 白色「种」 | 同上 |
| 普通 `normal` | 无环 | 无徽章 (最安静) | 同上 |

- 新组件 `core/widgets/typed_user_avatar.dart`（包 `UserAvatar`；`Semantics(label: '张三, 加盟商')`）
- 徽章只在 `size >= 40` 时画（小头像只留环, 否则字糊）
- `customer_row.dart`: 去掉 `FranchiseChip`; 名字行现在只剩「🎂 生日」徽章
- 为什么用汉字不用 emoji: 中老年用户读「盟/种」比 🌱/🟣 稳; 颜色只是冗余信息 (色弱也能分)
- 徽章白描边 2pt → 盖在照片头像上也看得清; 徽章不越出列表内边距 (56pt 头像 + 徽章 23pt 仍在 16pt padding 内)

**验证** (dev server 截图 + 像素扫描):
- 加盟行: 头像区紫色像素 13994 (环 + 「盟」徽章), 行文本语义 = 「SeedTest-杨翠萍, 加盟商」✓
- 种子行: 橙色像素 2049 (环 + 「种」徽章) ✓; 普通行: 无环无徽章 ✓
- `flutter analyze lib` 0 error ✓

### Changed (去掉长按提示字 + 生产管理员手机号落定, 2026-09-19 主人拍)

- **删掉**「长按上方「加盟」标签可解除加盟」那行提示字（主人拍: 不要）
  —— 长按入口保留, 只是不再显式提示
- **生产管理员账号落定**: 手机号 `19957347866`, 姓名 `管理员`, `role='admin'`
  - 写进 `.env.example` (`ADMIN_PHONE=19957347866` / `ADMIN_NAME=管理员`)
  - 写进 `docs/deploy.md §7.5`（部署 + 灾备恢复必跑命令已带真实号）
  - 写进 `AGENTS.md §6.5`（治理层）
  - dev 机器已跑 `ADMIN_PHONE=19957347866 ADMIN_NAME=管理员 pnpm db:ensure-admin` → 新建 id=8 ✓
    (`GET /api/me` 验证: name=管理员, role=admin ✓)

### Changed (「移动到其他点位」整体下线 + 解除加盟改为长按加盟标签, 2026-09-19 主人拍)

主人原话: 「加盟商详情页中，删除移动到其他点位图标，及背后的功能代码，因为动点位必需先解除加盟，
再重新加盟实现，不能直接移动点位。解除从右上角删除加盟图标，改为长按头像卡片中的加盟标签
（电话上面）可进入解除加盟流程。」

**① 「移动到其他点位」下线 (UI + 后端一起删)**
- Flutter 加盟商详情页: 删掉右上角 `swap_horiz`「移动到其他点位」图标 + `_moveToOtherSlot()` + `_findName()`
- API: `POST /api/franchisees/placement-requests` 收到 `kind='move'` → **400 + 明确提示**
  「点位不能直接移动: 请先解除加盟, 再重新加盟落位」(不静默当 create)
- Query 层: 删掉 move 创建分支 (改成显式 throw) + 删掉执行器的子树搬迁 SQL (`path` 前缀替换/`depth` 平移)
- 类型: `PlacementRequestKind` = `'create' | 'unjoin'`; schema `kind` enum 去掉 `'move'`
- 图谱虚位: 只对 `kind='create'` 画待确认虚位 (解除加盟单不画虚位 —— 那个点位本来就有人, 画了误导)
- 字段重命名: 老 `moveFid/moveFid` → `unjoinFid/unjoinName` (JSON 里仍兼容读老 key; DB 列名 `move_fid` 保留)
- 冒烟 `smoke-placement-confirm.ts`: 移动场景改成**负向用例** (kind=move 必须被拒) ✓

**② 解除加盟入口: 右上角图标 → 长按「加盟」标签**
- 删掉右上角 `link_off`「解除加盟」图标
- 头像卡里的 `🟣 加盟` 标签 (电话上方) 现在**长按**可进解除加盟流程:
  - `Semantics(button, container: true, label: '加盟标签, 长按可解除加盟')` + `Tooltip` 同文案
  - 长按给 `HapticFeedback.mediumImpact()` 反馈
  - 标签下方加一行极小的提示字「长按上方「加盟」标签可解除加盟」(长按是隐藏手势, 中老年用户需要提示)
- 右上角保留: 「编辑」+ (admin)「管理强删」

**验证** (dev server):
- 加盟商详情(107) app bar = 「编辑 + 管理强删 (admin)」—— 移动/解除图标均消失 ✓
- 长按标签 @(16+180, 292) → 弹出「解除加盟?」+「提交解除申请」✓
- `POST kind=move` → 400 「点位不能直接移动: 请先解除加盟, 再重新加盟落位」✓
- `npx tsc --noEmit` 0 error; `flutter analyze lib` 0 error; 两个冒烟脚本全过 ✓ (测试数据已清理 ✓)

### Added (「待确认虚位」可点击 + 系统管理员账号长期保留, 2026-09-19 主人拍)

**① 待确认虚位可点击 → 点进「待我确认」页**
- `customers_page.dart::_buildGhostHitareas`: 每个 pending 虚位一个点击区 (圆 + 下方「⏳ 名字」都可点)
  - 位置公式与 painter 共用 `FranchiseTreePainter.pendingGhostCenter`（单一来源, 不会两边画不一致）
  - 语义标签「待确认虚位 XXX (待确认), 点击查看待我确认」→ 无障碍 + 自动化可验证
  - 点击 → `context.push('/franchisees/placement-requests')`（加盟落位确认页, 默认「待我确认」tab）
  - 虚位点击区排在真节点之后 → 真节点优先, 虚位只吃空位
- **顺手修掉一个隐藏 bug**: `FranchiseeTreeNode.copyWith` 漏带 `pendingPlacements` →
  `_withLazyChildren` 拷贝根节点后「待确认虚位」整个消失（图谱不画 + 点不到）。
  今天排查虚位点击时发现, 一并修掉。

**② 系统管理员账号长期保留（dev + 生产）**
- 主人原话: 「长期保留系统管理员账号 admin，生产环境也要保留」
- 新增 `scripts/ensure-admin.ts` + `pnpm db:ensure-admin`（幂等）:
  - 账号不存在 → 建 (`role='admin'`); 已存在 → 只抬 role, 不覆盖其他字段
  - 参数: `ADMIN_PHONE` / `ADMIN_NAME` 或 `--phone= --name=`
- `docs/deploy.md §7.5` 新增部署章节: 为什么必须保留 (加盟权限 + 免确认 + 兜底修复) +
  幂等命令 + 部署/灾备恢复后必跑 + 登录方式 + 安全提醒 (生产别留 DEV_SKIP_AUTH)
- **dev 账号 user 1 保持 admin 不动**（主人拍板）

**验证**:
- 虚位点击: dev server 语义元素 `待确认虚位 虚位点击-测试 (待确认)…` @(67,628) → 点击后页面 =
  「加盟落位确认 / 待我确认 (0) / 我发起的 (0)」✓
- `pnpm db:ensure-admin` 两条路径都验过: 已存在(admin) → 跳过 ✓; 已存在(sales) → 抬成 admin ✓
- 测试数据 (pending 单 89 + 临时账号) 已清理 ✓

### Added (加盟设置权限三条红线, 2026-09-19 主人拍)

主人原话: 「必需由其他已加盟用户或系统管理员才能设置加盟，系统管理员设置加盟用户不需要多方确认，
用户自己不能给自己设置成加盟用户。」

**① 只有「已加盟用户」或「系统管理员」能设置加盟**
- `franchisee-placement.ts::createPlacementRequest`: 发起人必须有加盟商记录 (或 `initiatorIsAdmin`)
  → 否则 `只有已加盟用户或系统管理员才能设置加盟`
- `POST /api/franchisees/placement-requests`: 403 门闸同步改（原来只挡「没绑加盟商」，现在区分管理员）
- `POST /api/franchisees`（老的"直接新增加盟商"= 无三方确认）：**收紧成管理员专用**，
  普通用户 403 + 提示走「加盟落位（三方确认）」；**注意**: 以前这个口子任何登录用户都能调（无权限校验）

**② 系统管理员设置加盟 = 免多方确认**
- 管理员发起 → 单子直接 `status='executed'`（事务内立即落位），确认记录 `verified_by='admin'`
- `PlacementRequestView.required` 对管理员单返回 `[]`（Flutter 显示「管理员设置, 免多方确认」，不再出现 1/0）
- 管理员不受「只能在自己子树内操作」限制（可全网任意点位；原 Q7 只对普通加盟商生效）
- App 端文案: 管理员操作 → 「已落位…管理员设置, 立即生效」/「已移动 (管理员操作, 立即生效)」/「已解除加盟 (管理员操作, 立即生效)」

**③ 用户不能给自己设置成加盟用户**（管理员也不行）
- 校验点: 新加盟商手机号 hash == 发起人自己手机号 hash → 拒绝
- 两个入口都加: `createPlacementRequest` (三方确认流) + `POST /api/franchisees` (管理员直通流)

**冒烟**: `scripts/smoke-placement-rules.ts`（6 项全过）
- ③ 自己给自己 → 拒 ✓ / ① 非加盟非管理员 → 拒 ✓
- ② 管理员 → executed + verifiedBy=admin + 落位 path 正确 ✓
- HTTP 层复验: sales 用户 POST /api/franchisees → 403 ✓; POST placement-requests → 400 ✓;
  管理员单 HTTP 返回 `status=executed`, 记录 path=`L.L.L.L.L.L.` ✓

### Added (单击节点: 一层子节点也一起突出显示, 2026-09-19 主人拍)

- 主人: 「单击节点后，在确保已有触发不变的前提下（被点节点往上到根节点整条线突出显示），
  增加：被点节点的一层节点也突出显示」
- `franchise_tree_painter.dart`:
  - 新增 `selectedChildIds`（选中节点的**一层**子节点 id）—— **从树里实时算**（`late final`），
    所以懒加载展开出新子节点后，下一次 repaint 自动纳入高亮（不需要在页面侧维护集合）
  - 节点高亮集合 = 路径（到根）+ 选中节点的一层子节点 + 搜索/筛选命中 → 这些都不淡化
  - 连线：`选中 → 一层子节点` 的边也画 accent（3.5px，比路径的 4.5px 略细，层级更清楚）
  - 节点环：一层子节点与路径节点一样加 accent 环（`isOnPath` 语义并入 `selectedChildIds`）

**验证** (dev server, 图谱页点根节点「杨望」):
- 选中信息条出现「杨望 · — · 我 · 第0层」✓
- 图区 accent 像素 **1286 → 4952（+3666）** —— 增量就是根节点一层子节点的圆环 + 两条父子连线 ✓
- 原「到根的整条线高亮」行为不变（路径节点/边逻辑未动）✓
- `flutter analyze lib` 0 error

### Changed (选上级节点: 排除「两层已满」的节点, 2026-09-19 主人拍)

- 主人: 「发展为加盟商，选新加盟商的上级节点时，排除那些 a/b 两层已满的节点。
  例: 高建军 A线一层=彭桂英、B线一层=邓国华 → 选择列表里就不要出现高建军」
- `core/widgets/placement_target_sheet.dart` (客户详情「发展为加盟商」+ 加盟商详情「移动点位」共用):
  - `_slotsFull(node)` = 左/右两侧一层都有人 → **不进列表**（只给还有空位的上级）
  - 顶部加一行说明: `已隐藏 N 个「两层已满」的节点（要挂到更深的位置，请先在该节点下级腾位置）`
- 图谱节点上的「移动」入口**保持不加**（主人 2026-09-19 明确）

**验证** (dev server, 客户 47 → 发展为加盟商 → 弹层):
- 列表里**没有** 根(杨望) / 李建国 / 陈大壮 / 孙志强（都是左右一层已满）✓
- 有 徐长山（第 4 层, 左侧空位）✓ 等深层有空位节点
- `flutter analyze lib` 0 error

### Changed (「发展为加盟商」入口迁进「客户类型」区块, 2026-09-19 主人拍)

- 主人: 「发展为加盟商的入口迁移到客户类型区块中」
- `customers_page.dart`: 客户详情页的「发展为加盟商」按钮从「养生记录区下面的独立按钮」
  移进**「客户类型」卡**内部（分段按钮 `普通 | 🌱 种子` 下方 + 一条说明 + 全宽 FilledButton）
  —— 类型与「怎么变成加盟商」在同一张卡里，一眼看清三种类型的关系
- 加盟客户的卡不变（仍只显示「类型由加盟关系决定」+ 指路解除加盟）

**验证**: dev server 语义坐标确认 —— 「客户类型」卡 `@(16,436) 361x259` 内含
「发展为加盟商」按钮 `@(32,627) 329x56` ✓；`flutter analyze lib` 0 error

### Added (移动节点 UI + 图谱待确认虚位 + admin 强删, 2026-09-19 主人拍)

**主人拍板三项**: ①移动节点 UI ②图谱渲染「待确认虚位」③「解除加盟」加 admin 强删口子

- **① 移动节点 UI** (`franchisee_detail_page.dart`): 加盟商详情 app bar 新增「移动到其他点位」
  (⇄ 图标) → 通用选点位弹层 (复用 `core/widgets/placement_target_sheet.dart`, 原来只在客户详情用)
  → 提交 `kind=move` 三方确认 (设置者 + 该加盟商本人 + **新**位置上级; 原父节点不确认)
  → 通过后整棵子树跟搬 + 推荐人不变
- **② 图谱「待确认虚位」**
  - 模型: `PendingPlacement` + `FranchiseeTreeNode.pendingPlacements` (只有根节点带; `copyWith` 必须透传,
    否则懒加载 merge 会把虚位丢掉)
  - painter: `_drawPendingGhosts()` — 在父节点正下方 (同侧续线) 或外侧一列 (异侧) 画
    **橙色虚线圆** (PathMetrics 切段) + 浅底 + 「⏳ 名字 (待确认)」标签; 画在最上层
  - 数据来源: `GET /franchisees/me/tree` 的 `pendingPlacements` (已在上一批返回)
- **③ admin 强删** (`forceUnjoinFranchisee` + `POST /api/franchisees/:id/force-unjoin`)
  - **仅 role=admin** (sales/manager → 403); 仍遵守「有下线不允许解除」(Q3, 执行时再查一次)
  - 顺带把该节点上 pending 的申请单置 cancelled (避免点位预占卡住)
  - 走 `withAuditContext` → audit_log 留痕; Flutter 详情页仅 admin 显示 🗑「管理强删」入口
  - dev 备注: 已把 dev 账号 (user 1) 的 role 临时设为 `admin` 方便主人测; 要改回 `sales` 说一声

**验证** (scripts/smoke-placement-confirm.ts 全绿)
- 移动: 申请 pending 三方 → 本人同意 → 新上级同意 → executed; path 变成 `L.L.L.L.R.` ✓ / 方向=右 ✓ /
  **推荐人不变** ✓ (Q5)
- 解除: 有下线被拒 ✓; 叶子三方齐 → executed → 软删 ✓
- 强删: 有下线被拒 ✓; 叶子强删成功 (软删) ✓
- 接口: sales 调 force-unjoin → **403** ✓; 虚位: 建一条 pending 落位单 → 图谱出现橙色虚线虚位
  (accent 像素命中 + 视觉确认) ✓; 清掉后 pending=0 ✓
- `npx tsc --noEmit` 0 error / `flutter analyze lib` 0 error
- 踩坑修正: move 的子树搬迁 SQL 里 `substring(path from $1)` 参数 PG 当 text 正则 → 结果 NULL →
  报 not-null 约束; 改成 `$1::int` ✓

### Added (客户类型入口: 详情页一键切「普通 ↔ 种子」, 2026-09-18 主人反馈)

**主人反馈**: 「我没找到修改客户类型的入口」

- 现状 (回答): 三个类型里 **加盟是派生**（`resolveCustomerType`: 我的下级加盟商 > `is_seed` > 普通），
  所以只有 **种子开关**是可改的；它原本只藏在**客户编辑表单**第 7 段（姓名/手机/性别/出生/标签/病史/过敏史之后），
  主人没找到 → 加显眼入口
- **`customers_page.dart` 客户详情页新增「客户类型」卡**（在大头像卡下面第二张，一眼可见）:
  - 非加盟客户: `普通 | 🌱 种子` 分段按钮 —— **一点即切**（`PATCH /api/customers/:id {isSeed}`），
    不用进编辑表单; 切换后 invalidate 详情/列表/类型计数, 顶部胶囊筛选立刻同步
  - 加盟客户: 显示「加盟（类型由加盟关系决定，不可在这里切换）」+ 指路「解除加盟」
- 编辑表单里的原开关**保留**（新增/编辑客户时也能设）

**验证**: API 实测 `PATCH isSeed` → `customerType` 正确联动（加盟客户设 isSeed=true 仍显示「加盟」✓）;
dev server 截图 + 语义坐标确认「客户类型」卡 + `普通/🌱 种子` 分段按钮渲染 ✓,
点击「🌱 种子」→ 客户 47 落库 `type=seed, isSeed=true` ✓（验证后已还原为 normal）

### Added (加盟生命周期闭环: 发展为加盟 + 正式解除加盟, 2026-09-18 主人拍)

**主人问**: 「加盟用户首先是普通/种子用户（从普通/种子改变状态成加盟），加盟/普通/种子 这三种类型在哪里设置改变？」
**拍板** (ask_user 66ec03da): Q1 = 做「发展为加盟」快捷入口 / Q2 = 做正式「解除加盟」流程（三方确认）
/ Q3 = **有下线的节点不允许解除**

**类型规则（回答原问题）**: `resolveCustomerType()` = 我的下级加盟商 → 加盟; 否则 `is_seed` → 种子; 否则 普通
- 普通 ↔ 种子: 客户表单里的「🌱 种子客户」开关 (`isSeed`)
- → 加盟: **只能走落位流程**（下面新增的快捷入口）
- 加盟 → 退出: 本次新增正式「解除加盟」（之前只有软删）

**后端** (`src/lib/db/queries/franchisee-placement.ts`)
- 新 kind **`unjoin`**（解除加盟）: 三方确认（发起人 + 该加盟商本人 + 其**点位父节点**）;
  Q3: 有下线直接拒（发起时 + 执行时双查）
- 执行 = 软删加盟记录（点位释放; 客户端档案保留 → 类型退回 种子/普通）
- 「上级」按 **placement 父节点路径**算（不是 referrer —— 新落位流程里 referrer = 设置者, 点位父节点可能更深）
- 落位执行时**自动绑定新加盟商账号** `user.franchisee_id`（手机号匹配; 旧绑定指向已删节点会自动重绑）
  → 之后他才能作为「本人」参与三方确认
- unjoin 跳过「点位占用 / 预占」校验（要解除的节点本来就占着那个点位）
- schema: `kind` enum 加 `unjoin`（text 列, 无需 DB 迁移）

**Flutter**
- 客户详情: 「**发展为加盟商**」按钮（非加盟客户才显示）→ 底部弹层选上级点位（可搜索）+ A线/B线 → 提交三方确认
- 加盟商详情: 「软删」→「**解除加盟**」（确认框说明三方确认 + 有下线不允许）→ 发起 unjoin 申请
- 「加盟落位确认」页支持 unjoin（摘要: 「X 想解除「Y」的加盟」）

**验证** (scripts/smoke-placement-confirm.ts 扩展后全绿): 有下线解除被拒 ✓;
叶子节点解除: 申请 pending → 本人同意 (2/3) → 上级同意 → executed → 加盟记录软删 ✓;
落位后新加盟商账号自动绑定 ✓。`npx tsc --noEmit` 0 error / `flutter analyze lib` 0 error

### Added (加盟落位「三方确认」工作流 + 任意点位落位, 2026-09-18 主人拍)

**主人需求**: 「x 可以把 y 放在自己图谱中**任何一个点位**的下级点位；设置加盟节点必须**三方确认**
(设置者本人 + 新加盟商本人 + 新位置上一个节点加盟商; 上级 == 设置者则双方); 改位置同理」
**拍板** (ask_user 7ef4548b): 确认载体 = App 内 (Q1/Q2) / 72h 超时 (Q3) / pending 预占 (Q4) /
移动不含原父节点且推荐人不变 (Q5) / 历史节点补录 (Q6) / 只能操作自己子树 (Q7)
方案: `docs/placement-confirmation-design.md`

**后端**
- `drizzle/0010_placement_confirm.sql` (+ down): 2 张表 + 5 索引 (含 **pending 预占部分唯一索引**) + 2 审计触发器
  - `franchise_placement_request` (kind/status/发起人/新加盟商资料|move_fid/目标父节点+左右/预占/72h)
  - `franchise_placement_confirm` (三方各一条 approve|reject + verified_by in_app|backfill)
- `src/lib/db/queries/franchisee-placement.ts`: 状态机
  - `createPlacementRequest` (越权校验: 只能自己子树内 + 点位空 + 预占; 发起人自动 1 票)
  - `decidePlacementRequest` (角色判定: 目标父节点按 franchisee id / 新加盟商本人按手机号 hash / 发起人; 全齐 → 事务内落位)
  - `executeRequest` (create → 落 franchisee + 客户档案; **move → 整棵子树 path 前缀替换 + depth 平移**, 防成环)
  - `listPlacementRequests` (mine / to_confirm) / `cancelPlacementRequest` / `expireStaleRequests` (72h) / `listPendingPlacementsUnder` (虚位)
  - 坑: dev 的 postgres 池 `max=1` → **事务里不能用全局 db 查询** (会死锁), toViews 已改成走 `tx`
- API: `POST/GET /api/franchisees/placement-requests` + `[id]/decide` + `[id]/cancel` + `[id]`;
  `GET /franchisees/me/tree` 响应加 `pendingPlacements` (待确认点位, 给虚位渲染)
- 脚本: `scripts/smoke-placement-confirm.ts` (三方全流程冒烟 ✓ 通过) /
  `scripts/backfill-placement-confirms.ts` (Q6 历史 32 节点补录 ✓ 幂等) / `scripts/cleanup-smoke-placement.ts`

**Flutter**
- `core/models/placement_request.dart` (申请单 + 确认记录 + summary/progress)
- `FranchiseeService`: createPlacementRequest / listPlacementRequests / decidePlacementRequest / cancelPlacementRequest
- 新页面 `modules/relation/screens/placement_requests_page.dart`: 「待我确认 (N) / 我发起的 (N)」两 tab +
  同意 / 拒绝 / 撤回 (大按钮 56pt, 中老年友好) + 剩余小时提示
- 客户页: AppBar 加「待我确认」入口 (**Badge 红点**显示待我拍板数) + 图谱选中节点信息条加「加下线到此点位」
  (弹层选 A线/B线 + 姓名/手机 → 提交后提示「等三方确认后生效」)
- 路由 `/franchisees/placement-requests`

**验证**
- 冒烟 (scripts/smoke-placement-confirm.ts): 发起 pending 3 方 → 预占拦下二次发起 → 本人确认 2/3 →
  上级确认 → **executed**; 校验 path=`父path+L.` / depth=父+1 / referrer=设置者 / 方向=左 / 客户档案已落;
  拒绝分支 → rejected 且未落位; 详情角色判定 target_parent ✓ 全绿
- 回填: 历史 32 节点各 1 条 executed + 1 条 backfill 确认 ✓ (重复跑幂等跳过)
- `npx tsc --noEmit` 0 error; `flutter analyze lib` 0 error; migration compat 检查 0 error 0 warning

**未做 (下一批)**: 移动节点 UI (后端已通) + 图谱「待确认虚位」渲染 (API 已给 pendingPlacements) +
`public/app` 重建 (机器被其他会话占用, 待安静后补)

### Added (图谱折叠策略: <50 不折叠 / ≥50 折叠 + 单击自动展开正面 3 层, 2026-09-18 主人拍)

**主人拍**: 「加盟客户图谱中, 节点数低于 50 个时不要折叠。节点数大于 50 时折叠, 单击节点时,
确保当前节点正面的 3 层都是展开的（也就是说如果被点击的节点下面三层中有被折叠的, 在被点击时展开节点）」

- **`flutter_app/lib/modules/customer/screens/customers_page.dart`**:
  - 常量: `_graphNoFoldMaxNodes = 50` / `_graphTapExpandLevels = 3` / `_graphFullDepth = 12`
  - **< 50 不折叠**: 先按初始 2 层取一次, 拿到服务端真值 `totalDescendants`; 若 < 50 → 自动改拉
    `depth=12` 的全树, 一次全展开 (隐藏「收起」按钮; 点节点也不再触发懒加载)
  - **≥ 50 折叠**: 保持懒加载 (初始 2 层); **单击节点自动展开它正面 3 层** —
    逐层 BFS: 缓存优先 → 树里已有就用树里的 → 否则 `GET /franchisees/:id/children` 拉一级
  - 信息条: 不折叠 → 「共 N 位」; 折叠 → 「共 N 位 · 已展开 M」
  - `_expandNode` 收敛到统一的 `_ensureChildrenLoaded` (展开按钮 / 自动展开 同一套逻辑)

**验证** (dev server + Playwright 拦截 API 造数据)
- **小树** (真实种子数据 31 节点 → `totalDescendants` 30 < 50): 先请求 `depth=2` → 自动补 `depth=12` ✓;
  信息条「共 31 位」(无「已展开」) ✓; 画布上 31 个节点全部渲染 ✓; 无 children 请求 (不折叠) ✓
- **大树** (合成 63 节点, `totalDescendants` 62 ≥ 50): 信息条「共 62 位 · 已展开 6」✓ (折叠生效);
  单击第 2 层节点 → 依次请求 `n2_0/children` → `n3_0,n3_1/children` → `n4_0..n4_3/children`,
  即**正好它正面 3 层** ✓

### Fixed (build-flutter-web.sh --auto 静默退出二次加固 + public/app 完整重建, 2026-09-18 主人拍)

**主人拍**: 「public/app 现在补一次完整重建。修：早先挂着的 tools/build-flutter-web.sh --auto 静默退出 bug」

- **`tools/build-flutter-web.sh`**:
  - `--auto` 主 bug (DART_DEFINE 为空 → `grep` 无匹配返回 1 → `set -euo pipefail` 下
    `EXPECTED_IP=$(...)` 赋值失败 → 脚本在「验证」步静默退出, **永不同步 public/app**) 已由另一会话
    按主人拍板修掉 (`|| true`) ✓
  - **本次二次加固同类另一处** (同一个坑): `CURRENT_VERSION=$(grep ... | cut ...)` 无兜底 →
    version 字段缺失时会在「已同步但没 bump 版本/没更新 SW hash」时退出(浏览器拿不到新版) →
    加 `|| true` + 空值兜底; version 不是 `x.y.z` 时 `$((PATCH+1))` 会算术报错 → 正则校验,
    不合法退回 `0.2.0` 再 bump
- **完整重建** (走已修好的脚本): `bash tools/build-flutter-web.sh --auto` 全程跑通 —
  `flutter clean` → `pub get` → `build web --release` → `rsync → public/app/` → version bump → SW hash 更新 ✓
  - `public/app/main.dart.js` = 2,823,188 bytes; `flutter_service_worker.js` 里的 main.dart.js hash
    与文件 md5 一致 ✓
  - version.json 手工置 **0.2.4#5** (脚本自身 bump 出来的 0.2.3#4 与仓库已提交值相同,
    担心浏览器 SW 比对不出变化, 换一个确定没被缓存过的值)
  - 产物包含当前工作区全部改动 (含另一会话 ADR-0011「层级不限 + 图谱懒加载」与 WIP) ✓

**验证**
- `bash -n tools/build-flutter-web.sh` 语法 ✓; 脚本 `--auto` 模式端到端跑完 (这次真的 sync + bump) ✓
- 生产 build 加载正常: `/app/` → 图谱页 4 段筛选胶囊 / 节点三维样式 / 选中信息条 / 回到我·全景 都在;
  筛选计数 = 懒加载初始层 (ADR-0011 行为, 与节点样式无关) ✓

### Fixed (加盟商编辑页路由缺失 + 路由兜底, 2026-09-17 主人报)

**主人报**: 「修复加盟商详情的编辑页面, 当前报错: `GoException: no routes for location: /franchisees/81/edit`」

- **根因**: `franchisee_detail_page.dart` 的「编辑」按钮 push `/franchisees/:id/edit`, 但 `app_router.dart`
  只注册了 `/franchisees/:id` 和 `/franchisees/new` → 命中不到路由直接抛 GoException
- **修复**:
  1. 新增页面 **`modules/relation/screens/edit_franchisee_page.dart`** (姓名 / 手机号 / 备注 / 启用开关)
     - 推荐人 + 位置**只读**并显式提示「不可修改」—— 后端 `UpdateFranchiseeSchema` 也只收
       name/phone/notes/isActive (二叉树 placement_path 是物化路径, 改位置 = 先软删再加)
     - 保存后 invalidate `myFranchiseeTreeProvider` + `franchiseesProvider`, 回详情页
  2. `app_router.dart` 注册 `/franchisees/:id/edit` (`name: 'franchisee-edit'`)
  3. **兜底 `errorBuilder`**: 未知路由不再红屏抛 GoException, 改为「页面不存在 + 回客户页」友好页
- **顺手全仓扫同类问题** (AGENTS §3「单点问题修一处后必全仓扫一遍」):
  - `login_screen.dart`: 登录成功 `context.go('/dashboard')` → 该路由早已删除 →
    改 `go('/customers')` (两 tab 后正确落点)
  - `franchise_relation.dart`: `_toRelationNode` 漏映射 `placementPath` → 详情页「路径」永远显示
    `(顶级)` (实际 R.R.); 顺带补 `notes` 映射
  - `Franchisee` model 补 `notes` 字段解析 (后端 GET 一直返回, Flutter 之前丢了)
  - 其余 `/ai` `/follow-ups` `/interactions` `/reports` 引用只在 `lib/_deprecated/**` (死代码, 不编译)

- **详情页数据刷新**: `franchisee_detail_page` 的私有 `_franchiseeProvider` 提到共享
  `modules/relation/lib/franchisee_detail_provider.dart` (→ `franchiseeDetailProvider`),
  编辑保存后 invalidate 它 —— 否则 pop 回详情页还显示旧名字

**验证**
- API: `PATCH /api/franchisees/81` 改 name/notes → 200 生效; 传 `placementSide` → 200 但**位置不变**
  (Zod 静默丢弃未知字段 ✓ 二叉树结构安全)
- dev server: `#/franchisees/81` → 点「编辑」→ 编辑页渲染正常 (4 字段 + 只读卡 + 保存按钮),
  无 GoException; 详情页「路径」已正确显示 `R.R.`
- **生产 build 全流程**: 详情页 → 点编辑 → 改名 → 点「保存修改」→ 自动回详情页且**显示新名字** ✓
  (测试后已把 81 名字还原), GoException 计数 0
- 未知路由兜底: `#/no-such-page` → 显示「页面不存在 / 找不到这个页面 no-such-page / 回客户页」✓ 不再红屏

### Changed (图谱紧凑布局 — 上百节点可用, 2026-09-17 主人拍板)

**主人拍板**: 「当前仅十几个节点就展开得左右宽度很宽, 如果总节点数百个时根本没法查看。
平行的双主线外侧的节点需要弱化/虚化, 或前后立体显示, 且节点的左右间距要缩小, 甚至允许一定
比例的重叠。双主线两侧的节点水平或垂直的对齐度都可以放宽一些（节点可以有一些相互斥力或弹簧度）」

- **`franchise_tree_painter.dart` — 布局压紧**
  1. 层间距 `levelHeight` 140 → **122**, 列间距 `columnWidth` 180 → **104**, 主线偏移 90 → 84, 边距 40 → 28
  2. **列距自适应压缩** (`columnPitch`): 需要的半宽 > `targetHalfWidth`(760) 时按比例压缩,
     下限 `minPitchRatio` 0.42 → 允许相邻外侧节点**最多 ~50% 重叠**
     (实测 63 节点全二叉树: 画布宽 3432 → **1687**; 31 节点 1768 → 1552; 15 节点 1428 → 936)
  3. **外侧节点松弛** `_relax()`: 只动外侧节点 (主线严格竖直不动), 32 轮迭代 —
     斥力 (按 `min(半径和, 0.9*列距)` 推开, 允许轻微重叠) + 弹簧 (回父节点 0.02 / 回格位 0.07),
     夹紧 x ±0.38 列距、y ±0.32 层高 → 「可不对齐 + 一点斥力/弹簧」但不散架
  4. `TreeLayoutResult` 加 `columnPitch`
- **painter — 前后立体 + 虚化 + 分级细节**
  1. 外侧第 k 列半径 44 → 33 / 27 / 23 (越外越小), 透明度 1.0 → 0.92 / 0.78 / 0.64 (越外越虚)
  2. 画序改为**外侧先画、主线最后画** → 主线永远在最上层 (前后立体)
  3. 名字宽度/字号随列收窄; 缩小看全局时外侧名字自动省略 (`scale < 0.34` 省 col≥1, `< 0.58` 省 col≥2),
     主线/选中/搜索命中始终画 → 全局视图不糊
  4. 角标 (`直`/`上`) 在 `scale < 0.5` 时不画 (减噪)
  5. 「A线/B线」小标签只在主线列画 (外侧太小, 画了更乱)
- **`customers_page.dart`**: painter 传 `columns` / `columnPitch` / `scale`
  (`ValueListenableBuilder` 监听 `TransformationController`); hit area 半径跟着每列半径走

**验证**
- 新增 `flutter_app/test/graph_layout_test.dart` (3 tests): 31 节点宽度 < 1600 + 主线严格竖直 + 同层成对;
  63 节点 < 1800 且 `columnPitch < columnWidth` (压缩生效); 外侧松弛不串列/不跳层 ✓ 全过
- 离屏渲染大图 (测试内 `RepaintBoundary.toImage`): 63 节点 → `/tmp/graph-63.png` (1696x876),
  511 节点 → `/tmp/graph-255.png` (11406x1242) — 视觉 QA 确认「两条主线清晰在前、外侧一圈圈虚化」可读
- dev server 截图: 默认视图现在**能看到 11 个节点** (旧布局 7 个), 点「直推」筛选仍只亮 2 个 ✓

**边界 (留给主人决策)**: 极端大 (500+ 节点, 单层 200+ 兄弟) 时宽度仍随「最宽那层」增长
(压缩下限 0.42 已到, 再压就是看不清的糊); 后续可选方案 = 深枝折叠成「+N」角标 / 只在筛选/搜索时展开。

### Added (图谱节点三维区分 + 筛选统计, 2026-09-17 主人拍板)

**主人拍板** (ask_user 7706f602): ① A线=深蓝 #2B6CB0 / B线=紫 #8E5BA8
② 直推=实心 + 「直」角标, 非直推=空心 ③ 关系细分三级 (直推/下级引荐/上级引荐, 含后端改造)
④ 筛选+统计本期做 ⑤ 主线不绑直推

**后端 (新增 placement 二叉树视图 + relation)**
- **`src/lib/db/queries/franchisee.ts`**
  - `TreeNode` 加 `referrerId` + `relation` (`root|direct|downline|upline`), `classifyRelation` 统一判定
  - 新增 `getPlacementTree(rootId, depth)` — 按 `placement_path` 精确连父子 (真二叉树)
    - 为什么必须换: 「上级引荐、但放在我下线」的人 `referrer_id` 不是我 → 旧推荐树 (按 referrer_id 连)
      里根本看不到; 二叉树能看到, 并能标成「上级引荐」
- **`src/app/api/franchisees/me/tree/route.ts`** — 加 `?mode=referrer|placement`
  (默认 referrer = 冻结的 web admin 行为不变); 空树响应补 `relation: root`
- **Flutter** `FranchiseeService.getMyTree(mode:)` 默认 `placement`; `myFranchiseeTreeProvider` 走 placement

**前端 (三维区分 + 图例筛选 + 统计)**
- **`core/models/franchisee.dart`** — `FranchiseeRelation` enum (`label`: 我/直推/下级引荐/上级引荐)
  + `FranchiseeTreeNode.referrerId/relation`
- **`core/theme/app_theme.dart`** — `franchiseeA` (A线深蓝) / `franchiseeB` (B线紫) / `badgeNeutral`
- **`TreeLayoutResult`** — 加 `aLineIds` / `bLineIds` (整条腿, 含侧枝)
- **`franchise_tree_painter.dart`**
  - 节点色 = A线蓝 / B线紫 / 我绿; 填充 = 关系: **直推实心 + 橙「直」角标**,
    **下级引荐空心** (浅底+描边), **上级引荐空心 + 细外环 + 灰「上」角标**
  - 侧别小标签 `← 左线/右线 →` → `← A线 / B线 →`
  - 新增 `filterIds` (筛选时只亮命中, 其余淡化)
- **`customers_page.dart`**
  - **筛选 = 胶囊按键 4 段** (主人 2026-09-17 二次拍: 只要 全部 / A线 / B线 / 直推, 合成一个胶囊):
    `全部 | ●A线 7 | ●B线 7 | ●直推 2` (带人数 + 线别色点), `SegmentedButton(expandedInsets: zero)` 4 段平分整行
    点段 = 只看这一类 (其余淡化), 点「全部」恢复; 行高 46px (比之前 chips 两行省 28px 给画布)
  - 选中节点时信息条 → `SeedTest-陈大壮 · A线 · 下级引荐 · 第2层` + × 取消
  - 无障碍: 筛选 chips + 「回到我/全景」加 `Semantics(label)` (Flutter web 语义树原来这些是空 label)
- **`franchise_node_sheet.dart` / deprecated `franchise_tree_page.dart`** — 同步 A/B 线 + relation 文案 / 参数

**验证**
- `npx tsc --noEmit` 0 error; API 实测: placement 树 15 节点 relation 正确 (2 直推 / 12 下级引荐 / 0 上级);
  临时把 83 的 referrer_id 改成不在我子树的值 → relation 变 `upline`, 复原 → `downline` ✓
- dev server 截图 + 像素校验: A线实心/空心、B线实心/空心、直推橙色角标都在; 点「直推」chip → 只有 2 个直推节点亮,
  其余全部淡化; 点「A线」chip → B线整体淡化 ✓
- 胶囊 4 段 (语义坐标 16..377, 各 90x40) 一屏全见; 点「直推」→ 只有 2 个节点亮其余淡化; 点「A线」→ B线整体淡化

### Changed (graph 双主线「对碰」布局 + 单击/长按交互, 2026-09-17 主人拍板)

**主人拍板** (2026-09-17): 「从「我」开始, 左右两条主线最长的线平等, 其他节点往这两条线的
外侧分裂, 我的 2 条主线始终保持自上而下的平行。主线的左右节点保持成对排列（对碰奖视角）。
跳转加盟商详情由 单击节点 改为 长按节点, 单击节点触发：突显当前节点, 并高亮当前节点到「我」
的整条线, 同时弱化其他节点」

- **`flutter_app/lib/modules/presentation/graph/widgets/franchise_tree_painter.dart`** — `TreeLayout`
  重写为双主线布局 (`TreeLayout.compute` → `TreeLayoutResult`):
  1. 根 = 中轴顶部; 左腿/右腿各一条**主线**, 严格竖直平行 (列 x = ±90, 中轴 0)
  2. 同侧子节点续主线 (同侧断了用另一侧接, 主线不断); 另一侧 = 侧枝, 往**外侧**一列
     (列距 180), 侧枝内部再递归 (自己的主线 + 再外侧)
  3. `spineIds` (两条主线节点集合) 随布局返回 → painter 把主线连线画粗 (3.0 / 0.7 不透明)
  4. 左右主线同层节点同 y = 成对排列 (对碰奖视角)
  5. 坐标平移到画布 [0, width] (左腿 x 原本是负数, 会跑到 SizedBox 外 → 点击命中失效)
  6. 名字 maxWidth 220 → 160 (列距 180, 相邻列不串行)
- **`franchise_tree_page.dart`** (deprecated 页, 不在路由) — 同步到新 API (`compute` /
  `selectedNodeId` / `spineIds`), 修 analyze 报错
- **`franchise_tree_painter.dart`** — painter 高亮模型重构:
  - 删 `highlightedNodeId`; 新增 `selectedNodeId` / `pathIds` / `spineIds`
  - 连线: 选中路径 (accent 4.5) > 搜索命中 (accent 3.5) > 主线 (深绿 3.0) > 普通 (2.0);
    有高亮时其余连线淡化 (0.12)
  - 节点: 选中 = accent 光晕 + 5px 环; 路径上 = 3px 环; 非高亮节点淡化
- **`flutter_app/lib/modules/customer/screens/customers_page.dart`** — 交互改版:
  - **单击节点** = 选中: 突显该节点 + 高亮 它→「我」的整条线 (`_pathIdsTo` DFS 求路径) +
    其余淡化; 再点同一节点取消; 点空白画布取消 (`_clearSelection`)
  - **长按节点** = `context.push('/franchisees/<id>')` (原单击行为)
  - 提示条文案 → 「单击看线 · 长按进详情」(交互变了, 提示必须跟着变)
  - 「回到我」初始缩放改为**自适应**: min(1.0, 竖直放下整棵树的比例) — 4 层树 0.86
    (1:1 会撑出图区, 最下层名字被底边/按钮切掉); 下限 0.5 保可读
  - 图区底部预留 56px 给「回到我 / 全景」按钮 (`_graphBottomControlsHeight`) —
    按钮不再盖住最下层节点名字; viewport 同步扣掉这 56px (否则 fit/居中会偏)

**验证** (dev server :8080 + chromium 截图 + 像素/语义校验):
- 默认视图 (自适应缩放 0.86): 根居中, 左右主线 x=116 / 276 两条**竖直平行**列,
  每层成对 (y=372/495/618); 最下层名字完整可见 (底部留出按钮条后不再被切)
- 「全景」: 15 节点全部在视口内, 位置与设计一致 (主线两列 + 左右各 3 列外侧展开:
  左侧 x=30/78/125, 右侧 x=268/315/362)
- 单击最左最深节点: accent 像素 0 → 4122 (路径 + 环), 非路径节点淡化 (faded 像素 17311)
- 点空白: accent 回到 0, 淡化回到基线 → 取消选中生效
- 长按节点: 跳到加盟商详情页 (语义树变为详情页结构)
- `flutter analyze lib` 0 error

### Fixed (graph UI v3 — 治本渲染, 2026-09-17 主人二次反馈「ui一堆错误」)

> 上一节 (v2) 只改了 maxWidth / fit 系数, **没解决渲染根因**: 主人截图里图谱仍是
> 「左上角一小团 19px 节点 + 大半个屏幕空白」(= 只能看到画布左上角一小块被压扁的结果).
> 本节取代 v2 的渲染方案.

- **`flutter_app/lib/modules/customer/screens/customers_page.dart`** — 图谱视图重写:
  1. `InteractiveViewer(constrained: false)` — 旧版默认 `constrained: true`, 画布 1760x696 被父级
     tight constraints 压成 viewport 大小 → 只有画布左上角一块可见 (根节点根本不在视口里).
  2. 删 v2 的「外层 Transform 缩 viewport」方案 — 它缩的是 InteractiveViewer 的取景框
     (393x571), 不是画布 → 整张图被压成左上角一小团.
  3. 初始视图 = 「回到我」: 根节点 (绿) 顶部居中 + 1:1 (名字可读, 中老年友好);
     右下角两个按钮「回到我」(复位) /「全景」(整树 fit). `minScale` 跟随全景比例 (0.2x~3x).
  4. `boundaryMargin: infinity` — finite margin 时 InteractiveViewer 内部会算出 ~0.56 scale 下限,
     全景 0.2x 会被手势强行弹回.
  5. 顶部 AppBar 的 列表/图谱 `SegmentedButton`: 去掉图标 + 去掉 compact/shrinkWrap.
     旧版每段只有 63pt 宽, 「列表」「图谱」被挤成竖排两行 (主人截图最上面的歪字).
  6. 提示条文案缩到单行: 「点节点看详情 · 可缩放拖动」.
  7. 节点点击区 88x88 → 88x132 (含名字/左右线标签; 中老年手指粗, 别只让圆圈可点).
- **`flutter_app/lib/modules/presentation/graph/widgets/franchise_tree_painter.dart`** —
  姓名 / (我) / 左线右线 标签加画布同色底色块 — 父→子连线从圆底中心出发会穿过标签文字,
  垫底后连线从文字背后过 (不再穿字).

**验证** (dev server :8080 + 生产 build `/app/` on :3003, chromium 截图 + 像素/语义校验):
- 默认视图: 根节点绿色 88px 顶部居中 (logical y≈253), 名字可读; 右下两按钮坐标点击均生效
- 「全景」: 15 节点全部落在视口内 (19px/节点), 无越界 / 无裁剪
- 搜索: 输入命中名字 → 相机自动把命中节点移到视口中心 (1:1), 其余节点淡化
- AppBar 切换按钮: 文字单行 (像素测量行高 14pt, 修复前是竖排两行)
- 姓名底色块: 连线不再穿过名字 (视觉对比 crop-before / crop-after 确认)
- `flutter analyze` 0 issue; `flutter test` 余下 2 个失败与本次无关 (api_client_test 旧 import 路径 +
  widget_test `Uri.base.origin` 在测试环境报错), 均为历史遗留

**⚠ 预览框架 freeze (§9 / ADR-0009)**: 本次同步 `public/app/` (Flutter web 编译产物) 属
「业务改动需要 preview 联动」, 主人 review 时按 `[preview-bypass]` 处理.
`public/app/version.json` → `0.2.4#5` (SW hash 已更新, 主人侧需 Ctrl+Shift+R).

**⚠ 踩坑记录 (build 缓存 stale)**: `flutter build web --release` 的增量编译有 race —
如果在 dart2js 编译期间改 .dart 源文件, kernel (`app.dill`) 可能仍是旧产物, 而 flutter 的
filecache 已记下新 mtime → 之后所有 build 都复用 stale kernel 且不报错.
本次踩到 (search-focus 代码没进 build), 解法: `rm -rf .dart_tool/flutter_build` 全量重编.
另: `tools/build-flutter-web.sh --auto` 在 `set -euo pipefail` 下 `EXPECTED_IP=$(echo "" | grep ...)`
会静默退出 (grep 无匹配 exit 1) → 同步 public/app 步根本不跑. 待主人拍板修 (该文件在 preview freeze 清单里).

### Fixed (graph UI 自查 v2, 2026-09-17 — 部分被 v3 取代)

- **`flutter_app/lib/modules/presentation/graph/widgets/franchise_tree_painter.dart`** — 姓名 maxWidth 100 → 220 (=`TreeLayout.minNodeSpacing` = 220). 真实数据 (2-3 字中文名) 不再被截, 测试数据 `SeedTest-XXX` 多保留可读字符.
- **`flutter_app/lib/modules/customer/screens/customers_page.dart`** — 4 处 UI 优化:
  1. FAB 在 graph 视图下隐藏 (`floatingActionButton: _viewMode == _CustomerViewMode.list ? BigFab(...) : null`). graph 主要用来查看关系, 添加走列表视图 FAB 更顺手
  2. graph 视图右下周加「回到全景」小按钮 (圆角白底, 半透明) — user 缩放/拖动后一键回 fit 初始状态
  3. auto-fit 策略改用 outer Transform (同步, 不靠 post-frame callback). `_initialFitScale` 缓存在 state. `_resetGraphView` 重置 outer Transform + 清 InteractiveViewer 内部 transform
  4. fit 算法从 `min(scaleX, scaleY)` 改为 `scaleX * 0.98` (fit-to-width 优先). 原因: 4 层二叉树宽 1760 / 高仅 696, fit-to-min 会让树在 360px 宽手机屏上横向溢出 3.6x → user 看不到右半边子树. fit-to-width 让根 + 同层节点 horizontal visible, 垂直可滚看不同层级
- **changelog 添加**: 本节

**验证**: chromium 截图 → 「回到全景」可见 / 「SeedTest-陈大壮」等名字不再截断 / root (id=75, 主人=SeedTest-dev用户) 在 canvas 顶端以绿色 (`#4A7C59` AppTheme.primary) 渲染, child 紫色 (`#8E5BA8` AppTheme.franchisee). build 产物已同步到 `public/app/` (`main.dart.js` 04:51 后).

## [Unreleased]

### 🌲 加盟树深度放宽 ≤3 → ≤4 (ADR-0010, 主人 override)

**背景**: 主人 2026-09-16 ask 拍板: "测试数据中各类型的客户都创建一些. 加盟客户创建 30 个以上, 尽量体现更多更全面的复杂的分支、关系".

加盟二叉树 ≤3 层硬约束下, 单 tree 最多 15 节点 (1+2+4+8). 要 30+ 必须放宽到 ≤4 层 (1+2+4+8+16=31). 主人选 `relax-3to4` 候选 (D), 显式 override ADR-0006 合规红线.

**主人 2 个细节拍板** (ask_user d234bdd4, 2026-09-16): `tree-shape=relax-3to4` (单 tree 31 节点) + `种子=没加盟、没做过养生、但已加连接方式或在暖客宝中添加了基础信息的潜在客户` (主人自定义语义, 不归 schema type 字段, 用 notes 标记).

### Changed

- **`src/lib/db/queries/franchisee-tree.ts:46-67`** — `if (ref.depth >= 3)` → `const MAX_DEPTH = 4` + ADR-0010 引用注释. service 层 hard guard.
- **`src/app/api/franchisees/me/tree/route.ts:25`** — `Math.min(depth, 3)` → `Math.min(depth, 4)`. tree 查询最大深度.
- **`src/lib/db/schema.ts:118-123`** — `franchisee_max_depth_3 CHECK (≤3)` → `franchisee_max_depth_4 CHECK (≤4)`. sql raw block (当前未接入 migrate, 文档作用).

### Added

- **`docs/adr/0010-franchise-tree-depth-4-dev-override.md`** (~200 行) — ADR-0006 amendment, 4 候选评估 + 主人 override 依据 + 合规风险 (《禁止传销条例》实务 ≤5 才入刑) + revert 流程
- **`docs/adr/INDEX.md`** — 加 0010 行

### Not Changed (TODO 记账)

- DB CHECK constraint 实际未接入 drizzle migrate (待 §5 Follow-up): 当前 service 层兜底, 直 DB insert 仍可超 depth 4 (主人评估可接受)

### Fixed (BFS bug, 同任务期间发现)

- **`src/lib/db/queries/franchisee-tree.ts` BFS loop** — 不把 `depth >= MAX_DEPTH` 的子节点 push 进 queue. 原 bug: BFS fallback 只检查 input.referrerId depth, 下降到 depth=MAX 叶子当 parent → 新节点 depth=MAX+1 超限 (手动验证: `referrerId=10 (depth=3)` + sideHint=left → 落到 `徐长山 (depth=4).left` → placement_depth=5)
- **`src/app/api/franchisees/route.ts` catch** — business 错误 (`深度上限` / `No available position` / `Referrer not found`) 转 400 + 友好消息, 避免误导用户「服务器错误」

### Added (test infra)

- **`scripts/seed-test-data.ts`** (~440 行) — idempotent, 走 API 为主 (audit log), Part E 直接 drizzle insert `user` 表绑 root franchisee (13800138000 / 123456), 让 dev login 后 `/api/franchisees/me/tree` 返回完整 31 节点

### Fixed (graph InteractiveViewer)

- **`flutter_app/lib/modules/customer/screens/customers_page.dart:295-326`** — `_buildGraphView` 嵌套 `SingleChildScrollView (水平+垂直)` → `InteractiveViewer(panEnabled, scaleEnabled, minScale:0.3, maxScale:3.0, boundaryMargin:80)`. 加双指缩放 + 单指拖动. 31 节点 depth-4 树 可交互
- **`flutter_app/lib/modules/relation/screens/franchise_tree_page.dart:_buildTreeView`** — 同样替换. (legacy 关系页, `/franchise-tree` redirect 仍跳)
- **commit `4a1693e` + `5863699`** — source + preview-bypass bundle rebuild (AGENTS §9.3 SOP)
- **验证**: chromium + CDP touch event 模拟双指 zoom in (root 节点明显变大, 其他 2 个子被裁出); API 返 31 节点 depth=4 满二叉

### Fixed (graph InteractiveViewer v2, master 「还没修好」反馈)

- **v2 commit `7e2fe20` + `0e8ef5f`** — `LayoutBuilder + TransformationController` 加 auto-fit initial scale
  - v1 只加 InteractiveViewer, 但 scale=1.0 初始 = 31 节点 depth-4 树 (3520×812) 只看到 root+2 子, master 反映「没修好」
  - v2 auto-fit 进页面看全树: `fitScale = max(0.1, min(scaleX, scaleY) * 0.95)`, `Matrix4.identity()..scale(fitScale)`
  - `minScale 0.3 → 0.1` (允许手机屏 fit 全树)
  - flag `_graphAutoFitApplied` 防重复 reset
  - 同样改造 `franchise_tree_page.dart`
- **验证**: chromium + CDP touch 模拟 6 次 zoom in 后 root 充满屏 (像素 #4A7C59 = AppTheme.primary = 绿 ✓)
- **根节点颜色 bug 误判纠正**: 之前紫色是 stale ddc lag (dev mode 服旧 dill), 实际源码 root=green 已对

## [0.5.2] - 2026-09-16

### 🔒 预览框架冻结 (Preview Framework Freeze, ADR-0009)

**背景**: 主人 2026-09-16 ask 拍板: "当前的项目开发预览模式已经够用, http://192.168.1.99:3003/app-preview 与 http://192.168.1.99:3003/app 和实际代码基本实现了实时同步. 需要锁定成果, 确保预览模式稳定. 在接下来的开发过程中不管修改哪个模块的代码或增加减少哪个模块, 都不允许动这套预览框架".

预览框架已演进 4 个月 (W14 R12 三次复发 → 主人 override → v0.1.4 ?dev=1 加 Flutter web dev server). 当前 `280f5fa` 是已知好状态, 但**没有治理保护**: 没有冻结清单 / 没有 baseline / 没有 commit-time guard / 没有测试覆盖 / 没有 AGENTS 红线.

后果: 后续任意 task agent 不知道这个约束, 改业务模块时顺手改 preview, 预览挂掉 → 主人重新经历 W14 R12 那种"复盘 → 急救 → override → 妥协"循环.

**主人 3 个细节拍板** (ask_user 04a475b1, 2026-09-16): heavy (标准 + Vitest snapshot + Playwright smoke) + block mode (必须 `--no-verify` 显式 bypass) + full ADR (~300 行, 同 ADR-0008 体量).

### Added

- **`docs/adr/0009-preview-framework-freeze.md`** (~300 行, 7 节) — **主文档**, 完整 4 层防御 SOP:
  - §1 冻结清单 (9 个路径, 故意 NOT 冻结的相邻文件白名单)
  - §2 保护机制 (4 层: tag baseline + pre-commit guard + ADR + Vitest/Playwright 测试)
  - §3 改前 SOP (ask_user 拍板 → checklist → commit 显式声明)
  - §4 应急解冻 (单文件 revert / 整 framework revert / post-mortem 强制)
  - §5 候选评估 (5 方案对比 + 否决原因)
  - §6 关联文档 (上游元宪法 + 下游 dev-modules + 工具/测试)
  - §7 元数据 (拍板日期 / baseline sha / 复审周期)
- **`tools/pre-commit-preview-guard.sh`** — guard 实现 (block mode, exit 1 on violation)
- **`tests/preview-framework-snapshot.test.ts`** — Vitest snapshot (验证 9 个路径文件存在 + version.json 一致性)
- **`e2e/preview-smoke.spec.ts`** — Playwright smoke (静态路径必须 / `?dev=1` 前置 curl :8080 否则 skip)
- **git tag** `baseline-preview-v0.1.4-280f5fa` — 历史锚点 (已知好状态 sha)
- **`.git/hooks/pre-commit`** symlink → `../../tools/pre-commit-preview-guard.sh`

### Changed

- **`AGENTS.md` §9 新加** — Preview Framework Freeze 红线 (一图概览 + 违规 = 阻断 + 改前 SOP + 应急解冻 + 与其他规则关系 + 验收清单)
- **`docs/adr/INDEX.md`** — 加 ADR-0009 行 (按时间倒序插到顶部) + 元架构分类加一行
- **`docs/dev-modules/flutter-preview.md`** — 加 §Frozen Contract 章节引用 ADR-0009

### 不变

- 预览框架 9 个路径内容**完全不变** (本次任务自身不改 preview 文件, 只加 governance)
- v0.1.4 双域架构 (ADR-0008) 不变
- v0.1.3 双域 + 底座 + 模块化 (ADR-0007) 不变
- W14 R12 历史 (login-failure-triage.md) 不变 — 本 ADR 是该教训的"治本沉淀"

### 验证

- ✅ ADR-0009 写完整 (~300 行, 7 节, 同 ADR-0008 体量)
- ✅ INDEX.md 更新 (top-row 插入 + 元架构分类)
- ✅ AGENTS §9 加完整 (6 子节, 含验收清单)
- ✅ dev-modules/flutter-preview.md 加 §Frozen Contract
- ✅ 9 个冻结路径**未触动** (git diff baseline-preview-v0.1.4-280f5fa -- 9 paths 应为空)
- ✅ pre-commit guard 已装, 在预览文件上 `git add` + `git commit` (无 --no-verify) 应 exit 1
- ✅ Vitest snapshot test pass
- ✅ Playwright smoke test pass (`?dev=1` 默认 skip)
- ✅ git tag baseline-preview-v0.1.4-280f5fa 创建

## [0.5.1] - 2026-09-13

### 📋 APK 域 + WEB 域功能清单与协作关系细化 (v0.1.4, ADR-0008)

**背景**: v0.1.3 CHARTER §4 写的是抽象双域定位 ("APK = 主产品" vs "WEB = 脚手架"), 但主人 2026-09-13 ask 反馈: "不是模式不同, 开发域 (web) 和生产域 (apk) 是共存同时的". v0.1.3 §4 抽象不够, 需要**具体功能 + 关系 + 边界**.

**主人拍板澄清**:
- ❌ 不是 dev↔prod 切换, 是**两域永远共存**
- ❌ WEB 域不需要 hot reload (脚手架稳定, 跑 production mode 永久)
- ❌ APK 域不在主人 web server 跑 (Flutter native dev, 独立 .apk 安装)
- ✅ 共享后端 API (Drizzle schema 是真理源)

### Added

- **`docs/adr/0008-apk-web-domain-spec.md`** (400 行, 11 节) — **主文档**, 详细双域功能清单 + 协作关系:
  - §1 双域定位 (一图概览)
  - §2 APK 域 (生产域) 功能清单: 7 业务模块 + 技术栈 + 目录结构
  - §3 WEB 域 (开发域) 功能清单: 按路径分组 (/admin /dev /app-preview /login /download) + 状态 (冻结/活跃)
  - §4 两域关系: 数据共享 + 边界规则 + 认证共享 + 部署关系
  - §5 协作场景: 4 个典型流程 (开发 Flutter / 开发 WEB / 监控备份 / 销售员用 APK)
  - §6 冻结 vs 活跃对照表 (per CHARTER §4.4)
  - §7 不变 + §8 候选评估 + §9 风险 + §10 关联 + §11 元数据

### Changed

- **`docs/CHARTER.md` v0.1.4** — §4.5 新加 (双域细化, 引用 ADR-0008) + §10.1/§10.2 加 v0.1.4 版本
- **`AGENTS.md` §4** — 头部加引用 (双域共存架构, 指向 ADR-0008 + CHARTER §4.5)

### 不变

- v0.1.3 §4.1-§4.4 (抽象双域定位 + 模块化规则 + Mobile-Only 冻结) 继承
- ADR-0007 (APK 域内模块结构) 不变
- ADR-0005 (web admin freeze-keep 历史) 不变
- 现有 7 个 APK 模块代码不变

### 验证

- ✅ ADR-0008 写完整 (400 行, 11 节)
- ✅ CHARTER §4.5 加完整 (含 v0.1.3 引用 + 关键不变量)
- ✅ CHARTER §10.1 v0.1.4 生效中 + §10.2 v0.1.4 修订记录
- ✅ AGENTS §4 头部引用 ADR-0008

## [0.5.0] - 2026-09-13

### 🏗️ 底座 + 模块化插件架构重构基线 (v0.1.3 元宪法)

**背景**: W2-3 阶段 Flutter 移动端开发过程中, 项目暴露了三大结构性问题:
1. **APK 域模块边界缺失** — `flutter_app/lib/screens/` 目录平铺 12 个 screen, 包括 franchisee_* (加盟关系) 与 customers_page (客户档案) 等不同业务线混合在一起
2. **客户/加盟关系耦合在 customer 业务中** — 3 个 franchisee screen 与 customer 直接耦合, 没有抽象为可替换的关系系统
3. **WEB 域职责不清** — 7 个开发域模块 (任务快照/借鉴关注/UI 方案/项目 Skill/架构图/APK 预览/部署脚本) 散落在 scripts/ + docs/ + .pi/ + tools/ + deploy/ 多个物理目录, 没有统一模块清单

主人 2026-09-13 ask_user 4 项拍板 + 落 ADR-0007, 引入"**双域 + 底座 + 模块化插件**"架构:

| 维度 | 拍板 | 落地 |
|---|---|---|
| WEB 域模块清单 | all_7 (全部) | task-snapshot / references / ui-kit / project-skill / architecture / flutter-preview / deploy |
| APK 域模块清单 | merge_graph_list | auth / customer / wellness / follow_up / **presentation (graph+list 合并)** / meeting / **relation** |
| 客户/加盟关系抽象 | abstract_now | `RelationSystem` abstract class + `FranchiseRelationSystem` 默认实现, 调用方走接口 |
| 实施节奏 | incremental | 9 阶段渐进迁移 (Phase 0-9), 一次一个模块 + 单模块 commit |

### Added (架构基线)

- **`docs/adr/0007-modular-architecture.md`** (~10 KB) — 完整架构决策记录: 总架构图 + 模块清单 + RelationSystem 接口设计 + 9 阶段实施路线图 + 风险评估 + 候选对比
- **`docs/CHARTER.md`** 升 v0.1.3:
  - §4 重写: "五大业务域" → "双域 + 底座 + 模块化插件" 两段式
  - §4.1 总架构图: APK 域 (主产品) + WEB 域 (脚手架) + 共享基础设施
  - §4.2 业务域横向贯穿说明 (按数据视角, 不直接对应目录结构)
  - §4.3 模块化规则 (★ 客户/加盟关系 RelationSystem 接口)
  - §4.4 保留 v0.1.2 Mobile-Only 章程 (冻结规则不变)
  - §10.1 版本表 +1 行 (v0.1.3 生效)
  - §10.2 变更记录 +1 行 (2026-09-13)
  - §10.3 待办重写 (Phase 1-7 渐进迁移 + Phase 8-9 文档同步)
- **`AGENTS.md` §4 重写**:
  - 标题改为 "v0.1.3 底座 + 模块化插件"
  - 文件树增加 `flutter_app/lib/core/` + `flutter_app/lib/modules/` (APK 域)
  - 文件树增加 `docs/dev-modules/` (WEB 域文档化视图)
  - `docs/adr/` 标到 0007
  - 新增 §4.5 模块化约束 (APK 域规则 + WEB 域规则 + 客户/加盟关系模块接口)
  - 新增 §4.6 渐进迁移路线 (Phase 0-9 状态表 + 每 Phase DoD)
- **`CHANGELOG.md` [0.5.0]** (本条目)

### 设计要点

**1. APK 域物理模块化**:
```
flutter_app/lib/
├── core/                  ← ★ 底座 (不可替换)
│   ├── router/  providers/  http/  theme/  models/  widgets/
└── modules/               ← ★ 业务模块 (可独立替换/改进)
    ├── auth/  customer/  wellness/  follow_up/
    ├── presentation/      ← 图谱 + 列表合并
    ├── meeting/           ← 占位
    └── relation/          ← ★ 客户/加盟关系
```

**2. WEB 域文档化视图**:
- 物理位置维持现状 (`scripts/` + `docs/` + `.pi/` + `tools/` + `deploy/`)
- `docs/dev-modules/*.md` 作为软约束视图
- 新增开发模块时同步 README + 更新索引

**3. 客户/加盟关系模块 ★ 重点**:
```dart
// flutter_app/lib/modules/relation/lib/relation_system.dart
abstract class RelationSystem {
  String get name;
  Future<List<RelationNode>> getGraph(String rootId);
  Future<void> addRelation({required String fromId, required String toId, required RelationType type});
  Future<void> removeRelation({required String fromId, required String toId});
  Future<List<RelationPath>> findPaths({required String fromId, required String toId});
  Future<RelationNode?> getNode(String nodeId);
  Future<List<RelationNode>> getChildren(String parentId);
}

class FranchiseRelationSystem implements RelationSystem { ... }
// 未来: class DistributionRelationSystem implements RelationSystem { ... }
```

**4. 实施节奏 (per ADR-0007 §实施路线图)**:
- Phase 0 (0.5 天): 架构基线文档 ✅ 当前
- Phase 1-7 (5 天): auth / customer / wellness / follow_up / presentation / relation★ / meeting 渐进迁移
- Phase 8-9 (1.5 天): docs/dev-modules/ + 实地更新收尾

### 验证

- ✅ `docs/CHARTER.md` §4 含完整架构图 (APK 域 + WEB 域 + 共享基础设施)
- ✅ `docs/CHARTER.md` §10.1 含 v0.1.3 行
- ✅ `AGENTS.md` §4 标题 "v0.1.3 底座 + 模块化插件"
- ✅ `AGENTS.md` §4.5 模块化约束 + §4.6 渐进迁移路线
- ✅ `docs/adr/0007-modular-architecture.md` ~10 KB, 含 9 阶段路线图 + RelationSystem 接口设计
- ⏳ Phase 1-7 代码迁移待执行 (主人拍板节奏, 一次一个模块)

### 不变

- ❄ `src/app/admin/` + `src/components/business/` + `src/components/admin/` 仍冻结 (CHARTER §4.4 freeze-keep)
- ❄ `flutter_app/lib/screens/` 等旧文件: Phase 1-7 渐进迁移, 暂留 `_deprecated/` 目录

### 后续行动

- [ ] 主人 review 本条目 + CHARTER v0.1.3 + AGENTS §4
- [ ] Phase 1: `modules/auth/` 迁移 (主人拍节奏后开始)
- [ ] Phase 6: `modules/relation/` 抽接口 (★ 重点, 必须加单测)

---

## [0.4.2] - 2026-09-12

### 🔧 /app-preview 登录连不上后端 (Flutter web API base URL 写错 IP)

**背景**: 主人在 /app-preview 输入手机号 + 验证码 → 点登录 → `DioException [connection timeout]`. 原因: `public/app/main.dart.js` (Flutter web 编译产物, 2026-09-11 09:34 build) 裡 API base URL 硬编码 `http://192.168.1.200:3003/api`, 但主人当前 dev server 在 `192.168.1.99:3003`. 造成所有 API 请求连到错误 IP → TCP 连接超时 → “循环”表现其实是“每次都超时”.

**这不是 R12 循环**: R12 是 dio XHR 拿不到 Set-Cookie (在 HTTP 层走身份). 现在是 TCP 层根本没连上, 根本进不到 R12 逻辑.

**修复**:
1. **源码** `flutter_app/lib/services/api_client.dart`: web 模式 (dart-define 为空时) 从 `Uri.base.origin` 自动检测 API base. IP 变不用 rebuild Flutter web. Native APK 仍走 dart-define.
2. **编译产物** `public/app/main.dart.js`: `192.168.1.200` → `192.168.1.99` (sed 原地改, 立即生效)
3. **service worker** `public/app/flutter_service_worker.js`: 更新 main.dart.js hash (0386df280dd852f4cb7aeafd2ecd99c0), 让 SW 知道有新版
4. **version.json**: `0.1.0#1` → `0.1.1#2` (SW 检测版本变更)

**主人浏览器侧需要** (不清缓存拿不到新文件):
- `Ctrl+Shift+R` (Windows/Linux) / `Cmd+Shift+R` (Mac) 硬刷新
- OR DevTools → Application → Service Workers → Unregister → 刷新
- OR 隐私模式 / 无痕模式打开

**后续 todo** (主人决策):
- [ ] 主人装 Flutter SDK (~700MB, 见 AGENTS.md §7) 重 build, 让源码的 auto-detect 生效. 之后 IP 再变不需要再 sed main.dart.js
- [ ] 考虑加 Flutter web build 脚本到 tools/ (类似 `tools/build-flutter-web.sh`), 统一 dart-define 参数

**改动文件**:
- `flutter_app/lib/services/api_client.dart` — `_rawBaseUrl` default 从硬编码 `.200` 改空. 新增 `hasExplicitBaseUrl` getter. `baseUrl` / `baseOrigin` 走 dart-define 优先 / `Uri.base` fallback
- `public/app/main.dart.js` — sed 改 IP (1 处)
- `public/app/flutter_service_worker.js` — 更新 main.dart.js hash
- `public/app/version.json` — 0.1.1#2
- `tools/build-flutter-web.sh` — **新增**, 一键 build + sync + bump version + 更新 SW hash. 主入口参数化 (IP / PORT / --auto / --no-sync / --help). 避免下次 IP 变或重 build 时手操错.

**验证**:
- ✅ `main.dart.js` 含 `192.168.1.99:3003`, 不含 `.200`
- ✅ `version.json` 为 0.1.1#2
- ✅ service worker hash 与 main.dart.js md5 一致
- ✅ `tools/build-flutter-web.sh` 语法 OK / `--help` / `--auto` / 无参数 三路径都能干净报错或出帮助
- ⚠️ 需主人浏览器硬刷新才能看到新代码 (service worker 缓存)

**下次重 build 命令** (装 Flutter SDK 后):
```bash
# 指定 IP (最常用)
./tools/build-flutter-web.sh 192.168.1.99 3003

# 运行时自动从 Uri.base 推导 (IP 变不用 rebuild)
./tools/build-flutter-web.sh --auto

# 只 build 不同步
./tools/build-flutter-web.sh --no-sync <IP>
```

---

## [0.4.1] - 2026-09-12

### 🚨 /app-preview 移除 blockIframe 机制 (主人 override AGENTS.md §5 反模式)

**背景**: w14 第五刀 (2026-09-11) 在 `PreviewFrame` 加 `blockIframe=true` (pointer-events: none) 作为 R12 登录循环的"物理阻断"止血。AGENTS.md §5 同期记录此为"真修复"。

**主人 2026-09-12 拍板**:
- 删除 blockIframe 机制。iframe 现在永远可点
- 顶部 `FlutterWebLoginBanner` 降级为 informational only (sky 蓝, 非 enforce), 解释 R12 是什么 + 建议走真机扫码, 不再点登录
- R12 登录循环改用其他方式处理 (主人决策, 待实施: puppeteer 拦截 / middleware 拦截 / API disable)

**⚠ 此次变更与 AGENTS.md §5 "贴告示 ≠ 修复" 反模式冲突**:
- §5 结论: banner 单独存在 ≠ 修复, 物理阻断才是
- 主人 override: §5 是默认最佳实践, 但 R12 主人有意识选择 banner-only, 准备接受登录循环风险
- 后果: iframe 可点后, 在 iframe 里点登录必触发 R12 循环. 主人自行处理

**改动文件**:
- `src/components/preview/preview-frame.tsx` — 删除 blockIframe prop / forceInteractive state / toggleInteractive / toolbar 切换按钮 / effectiveBlockIframe 计算 / FlutterWebLoginBanner 内部渲染. iframe.style 永远 undefined (可点)
- `src/components/preview/flutter-web-login-banner.tsx` — 删除 interactive prop. 改成 sky-50 (蓝) informational 配色, 恢复 X dismiss 按钮 + localStorage, 文案改成"什么是 R12"说明
- `src/app/app-preview/page.tsx` — 删除 blockIframe={true}, FlutterWebLoginBanner 直接由 page render

**保留不变**:
- R12 文档 (`docs/login-failure-triage.md §2.B`) 保留, 描述 XHR-based dio 拿不到 Set-Cookie 头的问题
- FlutterWebLoginBanner 仍然存在, 作为"提醒" (不再 enforce)

**验证**:
- ✅ TypeScript 通过
- ✅ iframe 无 `style="pointer-events:none"`
- ✅ toolbar 无 toggle 按钮
- ✅ HTML 中无 blockIframe / "禁用交互" / "DEBUG 模式" 字样

**后续 todo** (主人决策):
- [ ] 实施 puppeteer 拦截 / middleware 拦截 / API disable 任一方式处理 R12 登录循环
- [ ] 写 post-mortem: 为什么 override AGENTS.md §5 反模式
- [ ] AGENTS.md §5 加注: 此变更的特例情况 (主人 override) 及 trade-off

---

## [0.4.0] - 2026-09-08

### 🚀 备份脚手架内置 (dev-domain-backup SOP §3.0)

**背景**: 主人 2026-09-08 ask_user 拍板, 项目需工业级备份 (PG + Media + GPG + 异地 + GFS). 调用 `~/.muse/skills/dev-domain-backup/SKILL.md` (v1.0 canonical, 2026-09-07) 全量实施.

**新增 deploy/ 目录** (项目级备份运维):
| 文件 | 职责 |
|---|---|
| `deploy/backup.sh` | PG (pg_dump -Fc) + Media (tar --zstd) → GPG AES256 加密 → 本地 + 异地 rsync → GFS 双保险 (mtime+14 AND count≤7) |
| `deploy/code_snapshot.sh` | dirty + untracked + .git/ → 外置盘异地 (zstd level 19), 含 sha256 + manifest sidecar, fail-closed 预检 secret basename |
| `deploy/restore_verify.sh` | 月度演练: 解密 → 起临时 PG:5435 → pg_restore → 14 张关键表行数比对 (生产 vs 演练) → 自动清理 |
| `deploy/install-systemd.sh` | 一键装 6 个 systemd user unit (3 service + 3 timer) + enable --now |
| `deploy/systemd/nuankebao-backup.{service,timer}` | 日 03:00 (Persistent=true, RandomizedDelaySec=5min) |
| `deploy/systemd/nuankebao-code-snapshot.{service,timer}` | 日 04:00 (错开 backup 1h) |
| `deploy/systemd/nuankebao-restore-verify.{service,timer}` | 月第一周日 04:00 (Sun *-*-1..7 04:00:00) |
| `deploy/README.md` | §10 备份 SOP 落地文档 (架构 / 调度 / 安装 / 安全 / 排错 / 验收) |

**新增数据目录**:
- `/home/mm7/nuankebao-databackups/` — 项目外独立备份目录 (gitignored, 防 rm -rf 误删)
  - `backup-key.gpg` (chmod 600, GPG passphrase-file, openssl rand -base64 32 生成)
  - `pg-backups/` (GFS 7 份)
  - `media/` (GFS 7 份)
  - `backup-health/` (atomic JSON 状态, chmod 600)
  - `logs/` (chmod 700 dir, 持久化日志)
- `/media/mm7/mm7-sda/nuankebao-databackups/` — 异地盘副本 (含隐藏 .backup-key/ 异地密钥副本)
- `/media/mm7/mm7-sda/nuankebao-codebackups/` — 异地代码快照
- `data/` (项目内, gitignored, 预留给未来扩展)

**3-2-1 副本策略** (SOP §2.1):
- 本地 (nvme) + 异地 (外置盘 /media/mm7/mm7-sda) + systemd timer 调度
- GPG 对称 AES256 加密 + passphrase-file (SOP §2.2 红线)
- GFS 双保险 mtime+14 AND count≤7 (SOP §2.4)
- fail-closed 预检 secret basename 黑名单 + 应排除路径检查 (SOP §2.5)

**Deprecated** (老备份脚本, 改 redirect):
- `tools/backup.sh` → `exec deploy/backup.sh "$@"` (透明跳转)
- `tools/restore.sh` → `exit 1` (覆盖式恢复危险, 改走演练 + 手动)
- `tools/backup-cron.sh` → `exit 1` (cron 改 systemd timer, Persistent + RandomizedDelay)

**Smoke test** (2026-09-08):
- ✅ `deploy/backup.sh` exit=0, 1s, PG=24850 bytes + Media=413 bytes
- ✅ `deploy/code_snapshot.sh` exit=0, 1942 files, 5.5MB, 含 .git/, 排除 node_modules + .next + Flutter build
- ✅ `deploy/restore_verify.sh` exit=0, 4s, 14/14 表 100% 行数一致
- ✅ systemd unit 全部触发成功 (`systemctl --user start nuankebao-*.service`)

**未启用** (主人拍板 skip-github-mirror):
- GitHub 镜像 + monitor (项目无 git remote, 暂不需要)

**密钥管理**:
- 主密钥: `/home/mm7/nuankebao-databackups/backup-key.gpg` (chmod 600)
- 异地副本: `/media/mm7/mm7-sda/nuankebao-databackups/.backup-key/backup-key.gpg`
- ⚠ 主人请把密钥内容备份到密码管理器 (1Password / Bitwarden)

## [0.3.0] - 2026-09-07

### Changed (命名一致性反转)

**背景**: AGENTS.md §6.3 原拍板"内部代号保留 bbt-", 仓库路径改名后保留 bbt-postgres / bbt-stack.service / tools/bbt-*.sh 等。主人 2026-09-07 ask_user「命名一致性」选 **all-nuankebao**, 全部反向统一为 nuankebao, 推翻 §6.3 保留清单。

**全栈命名表** (统一 nuankebao, 见 AGENTS.md §6.1):

| 类别 | 旧 | 新 |
|---|---|---|
| 仓库路径 | `/home/mm7/bbt-agent` | `/home/mm7/nuankebao-agent` |
| Docker container | `bbt-postgres` | `nuankebao-postgres` |
| Docker volume | `bbt-postgres-data` | `nuankebao-postgres-data` |
| Docker network | `bbt-agent_default` | `nuankebao-agent_default` |
| systemd system | `bbt-stack.service` / `bbt-cloudflared.service` | `nuankebao-stack.service` / `nuankebao-cloudflared.service` |
| systemd user | `bbt-nextjs.service` | `nuankebao-nextjs.service` |
| 脚本前缀 | `tools/bbt-*.sh` | `tools/nuankebao-*.sh` |
| 日志前缀 | `/tmp/bbt-*.log` | `/tmp/nuankebao-*.log` |
| PG user | `bbt` | `nuankebao` (ALTER ROLE bbt RENAME TO nuankebao) |
| PG db | `bbt` | `nuankebao` (ALTER DATABASE bbt RENAME TO nuankebao) |
| 云上路径 | `/opt/bbt/...` | `/opt/nuankebao/...` |
| Cloudflare 临时通道 | `bbt.tooyang.top` | **已注释掉** (主人手工去 Cloudflare Dashboard 删 DNS) |

**PG 迁移**: 用 rename-inplace (主人拍), `ALTER ROLE` + `ALTER DATABASE` 一次完成, 73MB named volume 数据保留, 14 张表全部迁到 nuankebao 账号下。

**保留** (脚本内部变量名, §6.2): `BBT_DIR` / `BBT_PORT` / `BBT_HOSTNAME` 变量名保留, 只改默认值。kubernetes / docker 都有这种"内部名 vs 外部 brand"解耦惯例。

**移除**:
- `/home/mm7/bbt-agent/` (root:root 空目录, 残留的 docker/init.sql 已先 cp 给 nuankebao-agent)
- `/home/mm7/bbt/` (pi cwd 标记, 已删)
- `tools/bbt-stack.service` → `tools/nuankebao-stack.service`
- `tools/bbt-tunnel.sh` → `tools/nuankebao-tunnel.sh`
- `tools/systemd/bbt-nextjs.service` → `tools/systemd/nuankebao-nextjs.service`
- `tools/nuankebao-rename-execute.sh` → `tools/.archive/` (改名任务已完成, 留档备查)

**未改**:
- Cloudflare DNS `bbt.tooyang.top` 记录 (Dashboard 操作, 主人手工删)
- 备份脚本里 `BBT_DIR` 变量名 (主人同意 §6.2 保留)

### Removed

- 仓库 `bbt-agent_default` docker network (compose 重命名后自动删除)

## [0.2.0] - 2026-09-05

### 🔄 项目改名 + 品牌升级 (BBT → 暖客宝)

### Changed (改名)

**背景**: 原名 BBT 暗示碧波庭单家公司, 不能覆盖目标用户群体 (养生保健 / 健康管理 / 康复养老 / 营养食品 / 健康生活方式 五大细分行业)。
重新命名为 **暖客宝 (NuankeBao)** —— “暖” + “客” + “宝”, 暗示温暖客户 + 客户是宝藏, 适合大健康销售气质。

**用户可见改动**:
- 销售 App 显示名: `bbt_agent` → `暖客宝` (Android label + iOS bundle display name)
- Web 站点名: `BBT · 养生行业 CRM` → `暖客宝 · 大健康销售 CRM`
- Web 后台侧栏: `BBT / 养生 CRM` → `暖客宝 / 大健康 CRM`
- APK 下载页: 所有 BBT 字样 → 暖客宝

**代码标识符**:
- Flutter pubspec name: `bbt_agent` → `nuankebao`
- Android package: `com.bbt.bbt_agent` → `cn.nuankebao.app` (Kotlin 目录同步 mv)
- Dart class: `BbtApp` → `NuankeBaoApp`
- dart-define: `BBT_API_BASE` → `NUANKEBAO_API_BASE`
- env var: `BBT_APK_PATH` → `NUANKEBAO_APK_PATH`
- APK 拷贝路径: `/tmp/BBT-release.apk` → `/tmp/NUANKEBAO-release.apk`
- Excel 模板: `BBT-customer-template.xlsx` → `nuankebao-customer-template.xlsx`
- APK 下载文件名: `BBT-release.apk` → `nuankebao-release.apk`

**部署默认值**:
- Postgres default user/db: `bbt` → `nuankebao` (密码 `bbt_password` → `nuankebao_password`)
- AUTH_URL fallback: `https://bbt.your-domain.com` → `https://nuankebao.tooyang.top`
- 云上中转路径: `/opt/nuankebao/public/uploads` → `/opt/nuankebao/public/uploads`
- 云上密钥路径: `/etc/bbt/secrets/pgcrypto.key` → `/etc/nuankebao/secrets/pgcrypto.key`

**保持不变** (主人拍板 2026-09-05):
- **仓库目录** `/home/mm7/nuankebao-agent` (git remote 引用, 不动)
- **Docker 容器名** `nuankebao-postgres` / `nuankebao-web` / `nuankebao-nginx` (主人机器内部代号)
- **Volume 名** `nuankebao-postgres-data` (Docker 存储保留)
- **Network 名** `nuankebao-net` / `web-net`
- **systemd service** `bbt-stack.service` / `bbt-nextjs.service`
- **脚本前缀** `tools/bbt-*.sh`
- **`.env` / `.env.local`** 主人机器真实生产值 (重建数据库需手动迁移)
- **`tools/branding/legacy/`** 历史 logo 资产

### Migration (手动, 主人择机执行)

主人 Q2 选 rename + Q3 选 replace 后, 下列是待手工迁移 (代码默认已切到 nuankebao, 但主人机器 .env / tunnel / DNS 还是 bbt):

1. **生产数据库 user/db rename**: `bbt` → `nuankebao`
   ```bash
   # 备份 + 重建 + 迁移 SOP: tools/SOP.md (待补)
   docker compose down postgres
   docker volume rm nuankebao-postgres-data   # ⚠ 永久删数据, 需先全量备份
   # .env: POSTGRES_USER=bbt → POSTGRES_USER=nuankebao
   # .env: POSTGRES_DB=bbt → POSTGRES_DB=nuankebao
   # .env: POSTGRES_PASSWORD 保持不变
   docker compose up -d postgres
   pnpm db:migrate
   pnpm db:seed
   # 从 gpg 备份恢复生产数据: ./tools/restore.sh <backup-file>
   ```

2. **Cloudflare tunnel hostname replace**: `bbt.tooyang.top` → `nuankebao.tooyang.top`
   ```bash
   # Cloudflare DNS: 加 CNAME nuankebao → 同 tunnel UUID
   # ~/.cloudflared/config.yml: 加 hostname: nuankebao.tooyang.top
   # .env: AUTH_URL=https://bbt.tooyang.top → AUTH_URL=https://nuankebao.tooyang.top
   # 重启 cloudflared + nginx
   # 老 bbt.tooyang.top 可保留为 301 跳转, 避免老用户失效
   ```

## [0.1.0] - 2026-09-04

### 🎉 Phase 1 MVP + Phase 1.5 移动端

### 新增 (Added)

#### 后端 (Next.js 15 + Postgres)
- 完整 13 表 schema + migration (customer / wellness_record / interaction / follow_up_task / body_part / service_item / product / store / staff / user / audit_log + 2 中间表)
- 5 个审计触发器 (自动记录 INSERT/UPDATE/DELETE + user_id + IP)
- AES-256-CBC 字段加密封装 (src/lib/crypto/field.ts)
- withAuditContext + getAuditContextFromRequest 封装 (src/lib/audit/context.ts)
- 业务层 queries (customer / wellness_record / interaction / follow_up-task / dictionary / dashboard / reports)
- 16 个 API 端点 (含 Zod 验证 + Auth.js v5 session 校验):
  - 客户: GET/POST /api/customers, GET/PATCH/DELETE /api/customers/[id]
  - 养生记录: GET/POST /api/wellness-records, GET/PATCH/DELETE /api/wellness-records/[id]
  - 跟进: GET/POST /api/follow-ups, PATCH /api/follow-ups/[id]
  - 联系: GET/POST /api/interactions
  - 字典: GET /api/dictionaries
  - 仪表盘: GET /api/dashboard/stats
  - 报表: GET /api/reports/overview
  - 照片: POST /api/photos (base64, 5MB 限制)
  - 导入: POST /api/import/customers (?mode=preview|commit)
  - AI: GET /api/ai/profile/[id], POST /api/ai/follow-up
  - 模板: GET /api/import/template
  - 健康: GET /api/health
- AI 客户端 (MiniMax + Vercel AI SDK), 无 API key 时自动 mock
- 3 个 AI prompt 模板 (客户画像 / 跟进话术 / 效果分析)
- Excel 导入工具 (xlsx + 字段校验 + 重复检测)
- 完整文档:
  - AGENTS.md (pi 协作约定, 反模式规则)
  - README.md (项目说明 + 快速开始)
  - docs/tech-stack-v0.1.md (技术栈定稿)
  - docs/references.md (借鉴清单: NocoBase/Twenty/Frappe 等)
  - docs/data-model.md (完整数据模型 + 加密示例)
  - docs/security-compliance.md (PIPL 合规 + 加密 + 审计 + 备份)
  - docs/phase-1-mvp.md (6 周实施计划)
  - docs/deploy.md (Debian 完整部署指南 8 章)
  - docs/user-manual.md (销售用)
  - docs/w1-implementation.md (W1 实施日志)
  - docs/flutter-migration.md (Flutter 迁移架构)
  - 4 个 ADR: 技术栈 / 数据模型 (更多 W2+ 待加)

#### Flutter 移动端 (Flutter 3.x + Riverpod)
- 完整 35 个文件 (~3800 行 Dart)
- 5 个 freezed 数据模型 (Customer / WellnessRecord / Dictionary / FollowUp / Dashboard)
- 8 个 service (auth / customer / wellness_record / follow_up / interaction / dashboard / ai / photo)
- 2 个 provider (auth + service_providers)
- 12 个 screen:
  - 登录 (auth/login_screen)
  - 仪表盘 (dashboard, 含 PieChart)
  - 客户管理 (列表/详情/新增编辑)
  - 养生记录 (列表/详情/结构化表单, 含拍照)
  - 跟进任务 (按到期时间分组)
  - 联系记录
  - AI 助手 (客户画像 + 跟进话术)
  - 报表中心
- 1 个 widget (stat_card + photo_picker)
- 主题 (养生绿 Material 3)
- go_router 路由 (含 Bottom Navigation 5 tab)
- dio 拦截器 (自动加 Auth.js session cookie)
- flutter_secure_storage (token 安全存储)
- image_picker 集成 (相机/相册)
- fl_chart 图表
- 完整 README + pubspec.yaml

#### 工具 + 脚本
- tools/check-env.sh (工具链自检)
- tools/check-port.sh (端口检测, 显示占用进程)
- tools/pre-commit-port-check.sh (git commit 时端口硬约束)
- tools/backup.sh (gpg 加密 + 异地同步)
- tools/restore.sh (恢复演练)
- tools/SOP.md (运维 SOP)

#### 测试
- 29 个 Vitest 测试 (单元 + 集成):
  - crypto (7): AES / HMAC / hash roundtrip
  - prompts (4): 3 个 AI 模板结构
  - ai-client (5): mock fallback
  - integration (6): 真实 DB (bbt_test 库)
  - integration-extra (7): 业务层 (follow-up / interaction / dashboard / reports / audit / dictionary)
- 7 个 Playwright E2E 测试:
  - 登录流程 (完整 + 错误码)
  - 路由守卫 (未登录跳 + 登录后跳)
  - 客户管理 (列表 + 新增表单)
  - API 健康检查
- bbt_test 独立测试库 (TRUNCATE 自动隔离)

#### CI
- GitHub Actions workflow (.github/workflows/ci.yml):
  - Type Check (type-check)
  - Vitest (Postgres service 跑集成测试)
  - Port 端口规范 (检测 3000 硬编码)
- .nvmrc + .node-version (固定 Node 20)

### 修复 (Fixed)
- Postgres 镜像: postgres:16-alpine → pgvector/pgvector:pg16 (含 pgvector)
- Refine v1.x 不存在 → W1 不装 (W3 复杂表单时再装)
- 路由冲突: (admin) → admin/ (Next.js route group 不计入 URL)
- drizzle .references() 类型推断问题 → schema.ts 用 @ts-nocheck
- NextResponse.json 不能序列化 BigInt → API 层 bigint 转 string
- session.user.phone 类型 → as any 绕过
- BigInt EXTRACT 函数不支持 → (date - date)::int 直接返回天数
- xlsx buffer 类型 → 转 Uint8Array
- 字段加密 SET LOCAL 参数化不支持 → sql.raw()
- audit_log.user_id NOT NULL 失败 → 改 nullable
- TypeScript tests/ 目录污染 → tsconfig exclude

### 工程化 (Changed)
- 端口规则强化: pre-commit hook (阻断端口冲突 commit)
- 完整端口占用记录 (3000/3001/3002/3100/3400/8080/9090 主人机器冲突)
- 文档不硬编码端口 (3003 是 BBT 默认, 实际部署时检测)
- Drizzle queries 全部加 audit context
- 字段加密统一应用层 AES-256-CBC (不用 SQL pgcrypto)
- API 错误处理统一 { error: string, details?: any }
- Flutter 模型用 freezed (不可变 + JSON)
- Flutter 状态用 Riverpod (不是 Provider)
- Flutter 路由用 go_router (不是 Navigator 1.0)

### 安全 (Security)
- 字段加密 (AES-256-CBC, 32 bytes hex 密钥)
- 审计日志 (5 触发器, 自动写)
- 备份加密 (gpg AES-256)
- 密钥轮换 SOP
- HTTPS (Let's Encrypt)
- 防火墙 (UFW, 只开 22/80/443)
- 端口硬约束 (pre-commit hook)

## [Unreleased] (Mobile-Only 阶段, 2026-09-07)

### 📱 Mobile-Only 阶段拍板

**背景**: W2-3 阶段 "Flutter + Next.js admin" 双线并行, 但主人 2026-09-07 直接指示: 「接下来开发只开发移动端, web 端服务等移动端开发完成后再补」。这是 L1 战略决策, 三项边界主人 ask_user 拍板。

**主人拍板的三项边界** (详见 [ADR-0005](docs/adr/0005-mobile-only-phase.md)):

| 边界 | 拍板 | 含义 |
|---|---|---|
| web admin 命运 | **freeze-keep** | 代码保留 / 部署照常 / 不加新 UI / 仅 P0 bug fix |
| 解冻条件 | **master-decide** | 无预定义里程碑, 主人手动拍板时点 |
| backend / schema 同步 | **flutter-only-sync** | Flutter service 必同步 / web admin client 暂停同步 |

### Changed (宪法 + AGENTS 升级到 v0.1.2)

- **`docs/CHARTER.md`** 升 v0.1.2:
  - §4.3 同步策略表后端行: `auto-both` → `flutter-only-sync`
  - **新增 §4.4 Mobile-Only 阶段章程** (4 段: web admin 状态 / backend 同步 / 解冻条件 / active 目录 / 误判处理)
  - §7 路线图 W2-3 / W4 / W5-6 优先级调整
  - §10 变更记录加 v0.1.2
- **`AGENTS.md`** v0.1.2 落地:
  - §3 同步策略整段改写 (3 子规则 + 拍板来源)
  - §5 反模式 +2 条 (web 冻结期硬约束 + flutter-only-sync 类型暂停)
  - §7 路线图 W2-3 / W4 调整 + 解冻候选参考
  - §4 文件组织加活跃/冻结标记
- **`docs/adr/0005-mobile-only-phase.md`** 新 ADR (4662 bytes), 详细记录决策 + 候选评估 + 风险缓解

### 影响

- ✅ Flutter 移动端 = 唯一 active frontend (双线 → 单线, 释放 ~40% 精力)
- ✅ Web admin (`src/app/admin/**`) 保留运行, 不下线, 不加新功能
- ✅ Backend / schema 改动只同步 Flutter service, web client 类型/调用暂停
- ⏸️ Web 解冻 = 主人 ask_user 明确「移动端 OK, 解冻 web」才触发
- ⏸️ 解冻后: web admin client 一次性 catch-up sync (类型/调用), CHARTER 升 v0.2.x

### 待做 (解冻时)

- [ ] 主人 ask_user 拍板解冻
- [ ] 估 catch-up 工作量
- [ ] 写 ADR-0006 解冻执行计划
- [ ] web admin client 类型/调用 catch-up PR
- [ ] CHARTER §4.4 移除, 升 v0.2.x

---

## [Unreleased] (W6 - 物理操作)

### 新增 (Added)

#### Schema 演进章程 (CHARTER §3.5 + §3.6, ADR-0004)

- **`docs/CHARTER.md` 新增 §3.5 Schema 演进红线**:
  - 6 个绝对禁止的 migration 模式 (DROP COLUMN / DROP TABLE / RENAME / ALTER TYPE 无 USING / SET NOT NULL 无 DEFAULT / DROP INDEX 在核心表)
  - 3 个推荐但警告的模式 (ADD COLUMN 无 DEFAULT / 大表 ALTER / CREATE INDEX 不带 CONCURRENTLY)
  - 强制 CI 集成 `tools/check-migration-compat.sh`
- **`docs/CHARTER.md` 新增 §3.6 RBAC 扩展预留**:
  - schema 必带 `created_by` / `store_id` / `deleted_at` / `user_role` 4 个 hook
  - W4 之前必须补: `customer.store_id` 列 + 索引 + user.default_store_id
  - W5 销售内测时不允许 `WHERE 1=1` 返回所有客户
- **`docs/adr/0004-schema-evolution.md`** (新 ADR): Schema 演进章程的决策记录
- **`tools/check-migration-compat.sh`** (新脚本, 250 行):
  - 检测 7 类禁止模式 (DROP / RENAME / ALTER / SET NOT NULL)
  - `IF EXISTS` 模式降为警告 (Drizzle dev 幂等 pattern, prod 前清理)
  - CI / 本地两用 (`bash tools/check-migration-compat.sh`)
- **`src/lib/db/migrate.ts`** 重构:
  - 新增 `pnpm db:migrate:check` (只跑 compat 检查)
  - 新增 `pnpm db:migrate:down <idx>` (单步回滚, 读 `drizzle/down/<同名>.sql`)
  - 默认 `pnpm db:migrate` 自动先跑 compat 检查 (警告不阻断, 主人 review)
- **`package.json` 新增 scripts**:
  - `db:migrate:check` / `db:migrate:down` / `db:compat` / `check-port`
- **`AGENTS.md §5` 反模式 +3 条: 不向后兼容 migration / NOT NULL 无 DEFAULT / 删破坏性不写 down**

### 验证

- ✅ `bash tools/check-migration-compat.sh` 跑现有 5 个 migration: 0 error, 1 warning (Drizzle dev IF EXISTS pattern)
- ⚠️ W4 之前必须补 `customer.store_id` 列 + 索引 (已在 §3.6 标 TODO)

### 待做
- [ ] 主人装 Flutter SDK (~700MB)
- [ ] 主人 `flutter run` 验证端到端
- [ ] 主人按 `docs/deploy.md` 部署到自有物理服务器
- [ ] 主人申请 + 配置 MINIMAX_API_KEY (AI 真实模式)
- [ ] 主人 `flutter build apk/ios` + 上架 (TestFlight + Google Play)
- [ ] 1-2 销售真用户内测
- [ ] 收集反馈 + Phase 2 规划

### 候选功能 (Phase 2)
- [ ] 效果分析 API 端点 (prompt 已有, 缺 API)
- [ ] 复购预测 (基于历史间隔)
- [ ] 推送通知 (firebase_messaging)
- [ ] 离线缓存 (sqflite)
- [ ] 客户列表 debounce 搜索
- [ ] 全局错误处理 (SnackBar)
- [ ] PWA 模式 (Expo for Web)
- [ ] 多租户 (SaaS 化)
- [ ] 计费层

---

**版本**: v0.1.0 "养生绿"
**日期**: 2026-09-04
**commits**: 16
**测试**: 36 (29 单元 + 7 E2E)
**代码量**: ~12000 行 (后端 8000 + Flutter 3800 + 文档 1000)

---

## [0.2.0] 改名完成统计 (补充)

**版本**: v0.2.0 "暖客宝"
**日期**: 2026-09-05
**改动范围**: 70+ 文件, 实际手改 40+ 文件
**保持不动**: 仓库目录 / docker 容器名 / volume / systemd / 内部代号脚本