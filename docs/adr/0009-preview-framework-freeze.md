# ADR-0009: 预览框架冻结 (Preview Framework Freeze)

**日期**: 2026-09-16
**状态**: ✅ Accepted (主人 2026-09-16 ask 拍板)
**决策者**: 主人 (虾王)
**影响范围**: WEB 域 dev-modules/flutter-preview + git governance + CI
**对应元宪法**: [`CHARTER.md`](../CHARTER.md) §7 反模式沉淀 + §3.4 治理红线

---

## 上下文

本决策对应:

- [`docs/CHARTER.md`](../CHARTER.md) §7 反模式沉淀 (主人立的"踩坑 → 立规"机制)
- [ADR-0007 底座 + 模块化插件架构](0007-modular-architecture.md) (APK 域内模块结构 + WEB 域 dev-modules 文档化视图)
- [ADR-0008 APK 域 + WEB 域功能清单](0008-apk-web-domain-spec.md) (§3 WEB 域功能清单中 `/app-preview` + `/preview` + `/dev-app` 是核心入口)
- [`docs/dev-modules/flutter-preview.md`](../dev-modules/flutter-preview.md) (当前预览模块文档, 本 ADR 在其上加 §Frozen Contract)

## 问题

主人 2026-09-16 ask 反馈: "**当前的项目开发预览模式已经够用** (`http://192.168.1.99:3003/app-preview` 与 `http://192.168.1.99:3003/app` 和实际代码基本实现了实时同步). **需要锁定成果, 确保预览模式稳定**. 在接下来的开发过程中**不管修改哪个模块的代码或增加减少哪个模块, 都不允许动这套预览框架**".

预览框架已演进 4 个月 (W14 R12 三次复发 → 主人 override → v0.1.4 ?dev=1 加 Flutter web dev server, 见 CHANGELOG [0.4.1] [0.4.2] + commit f82d356). 当前是**已知好状态**, 但**没有治理保护**:

1. **没有冻结清单** — 预览框架文件清单只在 `docs/dev-modules/flutter-preview.md` 描述, 没有 enforcement
2. **没有 baseline 标记** — 当前 `280f5fa` 是已知好状态, 但 git history 中没显式 marker
3. **没有 commit-time guard** — 任何 commit 都可以改预览框架文件, 没有阻断/警告
4. **没有测试覆盖** — 预览框架挂了 (e.g. iframe 不渲染 / banner 消失) 没有 smoke test 兜底
5. **没有 AGENTS 红线** — 改预览框架的 SOP 只在文档里, 没沉淀到 L2 操作层

后果: **下次 W15+ 任意 task agent 不知道这个约束, 改业务模块时顺手改 preview, 预览挂掉**. 主人要重新经历 W14 R12 那种"复盘 → 急救 → override → 妥协"的循环.

## 决策

主人 2026-09-16 ask 拍板: **引入 preview framework freeze 机制, 4 层防御**:

| 层 | 机制 | 触发 | 强度 |
|---|---|---|---|
| **L1 baseline** | `git tag baseline-preview-v0.1.4-<sha>` | 当前 commit 立即打 | 历史锚点 (事后查) |
| **L2 governance** | `tools/pre-commit-preview-guard.sh` + AGENTS §9 红线 + CHANGELOG [0.5.2] | commit 时 | 阻断 (必须 `--no-verify` 显式 bypass) |
| **L3 ADR** | 本 ADR-0009 (≈300 行) + dev-modules/flutter-preview.md §Frozen Contract | 文档查阅 | 改前 SOP |
| **L4 tests** | `tests/preview-framework-snapshot.test.ts` (Vitest) + `e2e/preview-smoke.spec.ts` (Playwright) | `pnpm test` / `pnpm test:e2e` | 验收兜底 (跑通 = preview 仍稳) |

主人 3 个细节拍板 (ask_user 04a475b1, 2026-09-16):

| 维度 | 拍板 | 落地 |
|---|---|---|
| **lock-tier** | heavy (标准 + Vitest snapshot + Playwright smoke) | §L2 + §L4 双重保险 |
| **guard-mode** | block (必须 `--no-verify` 显式 bypass) | guard exit 1, 强制声明 |
| **adr-style** | full (~300 行, 同 ADR-0008 体量) | 本文档 |

---

## 1. 冻结清单 (Frozen File Whitelist)

> **9 个路径, guard 用 glob prefix 匹配**. **完整 = 唯一真理源**; guard 脚本从本节读列表 (硬编码 + 注释引用本节), 改 guard 时**必须同步本节**, 反之亦然.

```
src/app/app-preview/             ← 主预览页 (Next.js page + iframe)
src/app/preview/                 ← /preview → /app-preview 307 redirect 兜底
src/components/preview/          ← PreviewFrame + FlutterWebLoginBanner (2 个组件)
tools/build-flutter-web.sh       ← 一键 build + sync (编译产物 → public/app/)
tools/dev-app-proxy.py           ← Flutter web dev server 反代 (?dev=1 路径核心)
tools/install-dev-app-proxy.sh   ← dev-app-proxy.py 一键安装 (systemd user)
tools/install-flutter-dev-tunnel.sh  ← cloudflared path rule 安装
tools/start-flutter-dev.sh       ← Flutter web dev server 启动器 (后台/前台/stop/status)
public/app/                      ← Flutter web 编译产物 (git tracked)
```

### 1.1 故意 NOT 冻结的相邻文件

| 路径 | 不冻结原因 |
|---|---|
| `src/app/(admin)/` 等 web admin 目录 | 已 freeze-keep (CHARTER §4.4 + ADR-0005), 主人 W6 后手动解冻 |
| `flutter_app/lib/**` | 业务源码 — 改业务 = 改 preview 显示什么, **不该被 preview freeze 拦** |
| `src/components/business/**` | WEB admin 业务组件 (与 preview 无关) |
| `src/app/api/**` | 后端 API (preview 消费方, 不是 preview 本身) |
| `docs/dev-modules/flutter-preview.md` | 治理文档 — §Frozen Contract 段本就需要演进, 自身不该被自己冻结 |
| `tools/install-guards.sh` | 守护安装 (systemd + cron), 与 preview 无关 |
| `tools/pre-commit-preview-guard.sh` | guard 自身 (改 guard 需走 §3 改前 SOP, 但不被 guard 拦) |
| `tests/preview-framework-snapshot.test.ts` | 测试自身 (改测试 = 改 §L4 验证, 不算 preview) |
| `e2e/preview-smoke.spec.ts` | 同上 |

> ⚠ **关键 invariant**: guard 脚本**只**对上面 9 个路径 glob match. 任何对 guard 逻辑的修改 (`tools/pre-commit-preview-guard.sh` 自身) 都不会被自身阻断——这是设计意图, 改 guard 必须 read §3 改前 SOP.

---

## 2. 保护机制 (4 层防御)

### 2.1 L1 — git baseline tag (历史锚点)

```bash
SHA=$(git rev-parse --short HEAD)
git tag -a "baseline-preview-v0.1.4-${SHA}" \
  -m "Preview Framework Baseline v0.1.4 (${SHA}, $(date +%Y-%m-%d))"
```

**何时打新 tag**:
- ✅ 主人拍板升级预览框架 (e.g. 加新组件 / 换 Flutter SDK)
- ✅ W19 / W20 大版本切换
- ❌ 不要每次 commit 都打 (tag 噪音)

**回查方式**:
```bash
git tag -l 'baseline-preview-*'        # 列出所有 baseline
git diff baseline-preview-v0.1.4-<sha>  # 看 baseline 之后改了哪些 preview 文件
git checkout baseline-preview-v0.1.4-<sha> -- src/app/app-preview/  # 单文件回滚
```

### 2.2 L2 — pre-commit guard (commit-time 阻断)

**位置**: `tools/pre-commit-preview-guard.sh`

**安装**: 见 `tools/install-guards-preview.sh` (后续可加; 当前在 commit message 注明, 主人手跑 `ln -s`)

**行为** (block mode, 主人 2026-09-16 拍):

```
检测到改动预览框架 9 个路径:
  - src/components/preview/preview-frame.tsx
  - tools/build-flutter-web.sh

预览框架已冻结 (baseline-preview-v0.1.4-280f5fa).
修改前必读: docs/adr/0009-preview-framework-freeze.md §3

如确认必要 (主人拍板后), 用 --no-verify bypass:
  git commit --no-verify -m 'fix(preview): ...'
```

**`--no-verify` bypass 流程**:
- bypass 不是"自由通行证", 是**显式声明**: commit message 必须以 `[preview-bypass]` 或 `fix(preview):` / `feat(preview):` 开头
- AGENTS §9 红线 (待加) 强制主人 review 所有 `[preview-bypass]` commit
- bypass 触发后, guard 仍把违规文件列表 echo 到 git reflog (后续 audit)

**特殊情况豁免**:
- `git commit --no-verify` 显式声明 → bypass
- `[ci-skip]` / `[no-guard]` 不会豁免 (避免 CI / agent 偷懒)
- commit message 含 `Merge` → 仍走 guard (避免 merge 把别人改动悄悄引入)

### 2.3 L3 — ADR + dev-modules 文档化 (§3 改前 SOP, 见下)

### 2.4 L4 — 测试覆盖 (验收兜底)

**Vitest snapshot test** (`tests/preview-framework-snapshot.test.ts`):
- 列 `git ls-files` 比对冻结清单 (硬编码期望列表, snapshot 形式)
- 验证 9 个路径每个都 ≥ 1 文件存在
- 验证 `public/app/version.json` 字段 `framework_version` 与 baseline 一致

**Playwright smoke test** (`e2e/preview-smoke.spec.ts`):
- 跑 `/app-preview` (静态路径, 需 `pnpm dev` 在 3003) → 断言 iframe 存在 + banner 出现
- 跑 `/app-preview?dev=1` (动态路径, 需 Flutter web dev server 在 8080) → **前置 `curl :8080` 检查, 不通就 `test.skip()`**
- 不污染主人默认 URL (用 `?path=/customers&frame=0` 参数化)

---

## 3. 改前 SOP (Justified Change Workflow)

> **主人 2026-09-16 拍板**: 改预览框架不是禁止, 是**强约束**. 任何改动必须走下面 3 步.

### Step 1: 必须 ask_user 拍板

**触发条件** (任一即触发):
- 主人显式要求升级 preview (e.g. 加新组件 / 换 Flutter SDK / 加新设备)
- W19+ 大版本切换需重新 baseline
- 业务模块深度改动要求 preview 显示规则联动 (e.g. 关系抽象重构后 graph 渲染需调)

**禁止 ask_user**:
- ❌ "我想顺手优化一下 preview frame 的 CSS" → 阻塞. 改 CSS 也算改.
- ❌ "agent 自动任务顺手改了 preview banner 文案" → 阻塞. 自动任务也算.

### Step 2: 走 §3.1 改前 checklist

```bash
# 1. 看 baseline tag 后改了哪些
git diff baseline-preview-v0.1.4-280f5fa -- \
  src/app/app-preview/ src/app/preview/ src/components/preview/ \
  tools/build-flutter-web.sh tools/dev-app-proxy.py \
  tools/install-dev-app-proxy.sh tools/install-flutter-dev-tunnel.sh \
  tools/start-flutter-dev.sh public/app/

# 2. 跑测试确认 baseline 状态干净
pnpm test tests/preview-framework-snapshot.test.ts

# 3. (主人真机验证) pnpm dev → 浏览器开 /app-preview → 看 preview 是否稳
bash tools/check-port.sh 3003
pnpm dev &
sleep 5
curl -sI http://127.0.0.1:3003/app-preview | head -1  # 应 200 OK
```

### Step 3: commit 时显式 bypass

```bash
# 改完, commit message 必须前缀 [preview-bypass] 或 feat/fix(preview):
git add src/components/preview/preview-frame.tsx
git commit -m "fix(preview): R12 banner 文案调整 (主人 2026-XX-XX 拍)

[preview-bypass]: 主人 ask 拍板 (commit message 含此 tag 才能过 guard)"
```

**或 `--no-verify`** (commit msg 不强求):
```bash
git commit --no-verify -m "fix(preview): ..."
```

---

## 4. 应急解冻 (Emergency Unfreeze)

> **适用**: preview 框架已挂, 主人需要立刻修, 来不及走 §3 流程.

### 4.1 单文件 revert (最常见)

```bash
# 找出最近一次改 preview 文件的 commit
git log --oneline -10 -- src/app/app-preview/ src/components/preview/

# 单文件回滚到 baseline
git checkout baseline-preview-v0.1.4-280f5fa -- src/components/preview/preview-frame.tsx

# 现场验证
pnpm dev &  # (如果没起)
curl -sI http://127.0.0.1:3003/app-preview

# commit 修复 (此时 guard 会 fire 因为改了 preview 文件, 用 --no-verify)
git commit --no-verify -m "fix(preview): 紧急回滚 preview-frame.tsx 到 baseline"
```

### 4.2 整 framework revert (灾难)

```bash
# 备份当前 dirty
git stash push -m "preview-emergency-$(date +%s)"

# 回滚整个 preview 框架到 baseline
git checkout baseline-preview-v0.1.4-280f5fa -- \
  src/app/app-preview/ src/app/preview/ src/components/preview/ \
  tools/build-flutter-web.sh tools/dev-app-proxy.py \
  tools/install-dev-app-proxy.sh tools/install-flutter-dev-tunnel.sh \
  tools/start-flutter-dev.sh public/app/

# commit + --no-verify
git add -A
git commit --no-verify -m "fix(preview): 紧急回滚整个 preview framework 到 baseline-preview-v0.1.4-280f5fa

WARN: 这条 commit 是 §4.2 应急解冻路径, 后续必须 post-mortem (见下)"
```

### 4.3 解冻后的 post-mortem 强制要求

任何应急解冻后:
- [ ] 24h 内写 `docs/preview-emergency-postmortem-<date>.md`
- [ ] 主人 review + AGENTS §X 加新反模式条目 (避免复发)
- [ ] 如果是 W14 R12 那种"贴告示 ≠ 修复" 类, 必须强化 §L2 guard (e.g. 加 lint rule / API disable)

---

## 5. 候选评估 (Alternatives Considered)

| 方案 | 描述 | 主人评估 | 否决原因 |
|---|---|---|---|
| **1. 完全禁止改** (no bypass) | guard exit 1, 不允许 `--no-verify` bypass | ❌ 太刚性 | 真要修时无路 (e.g. SDK 升级) |
| **2. 仅 warning** (warn mode) | guard echo ⚠ 但 exit 0 | ❌ 太弱 | 历史证明: w14 R12 三次复发就是"贴告示" 模式 |
| **3. 仅文档化** (no guard) | AGENTS §9 加规则, 无 enforcement | ❌ 不够 | agent 跑自动任务时不读 AGENTS, 历史证明 |
| **4. CI-only guard** (GitHub Action) | push 后 GitHub Action 检查 | ❌ 不可行 | 项目是 self-host Docker, 没 GitHub Actions 必有 |
| **5. 多层防御** (本次) | tag + guard + ADR + tests 四层 | ✅ 主人拍 | 防御深度够, 各层互补, 不冗余 |

---

## 6. 关联文档

### 6.1 上游 (元宪法 / 战略层)

- [`docs/CHARTER.md`](../CHARTER.md) §3.4 治理红线 + §7 反模式沉淀
- [ADR-0005 Mobile-Only 阶段](0005-mobile-only-phase.md) (web admin freeze-keep 先例)
- [ADR-0007 底座 + 模块化插件架构](0007-modular-architecture.md) (WEB 域 dev-modules 列表)

### 6.2 下游 (dev-modules + 操作层)

- [`docs/dev-modules/flutter-preview.md`](../dev-modules/flutter-preview.md) — 加 §Frozen Contract 章节引用本 ADR
- [`AGENTS.md`](../../AGENTS.md) §9 — 加"Preview Framework Freeze 红线"
- [`CHANGELOG.md`](../../CHANGELOG.md) [0.5.2] — 记录本次冻结

### 6.3 工具 / 测试

- `tools/pre-commit-preview-guard.sh` — guard 实现 (本 ADR §2.2 描述行为)
- `tools/install-guards-preview.sh` — 一键安装 guard (后续, 主人手跑 `ln -s` 也可)
- `tests/preview-framework-snapshot.test.ts` — Vitest snapshot (§2.4)
- `e2e/preview-smoke.spec.ts` — Playwright smoke (§2.4)

### 6.4 历史复盘 (避免复发)

- [`docs/login-failure-triage.md`](../login-failure-triage.md) — W14 R12 三次复发教训 (本 ADR 是该教训的"治本"沉淀)

---

## 7. 元数据

- **创建者**: 主人 + pi agent (2026-09-16)
- **首次拍板**: 2026-09-16 (主人 ask + ask_user 选层级)
- **首次 baseline**: `baseline-preview-v0.1.4-280f5fa` (commit `280f5fa`)
- **下次复审**: 2026-12-16 (3 个月后, 或 W19 大版本切换时)
- **关联 CHANGELOG**: [0.5.2] (2026-09-16)
- **关联 commit**: (本次提交, 单 commit "feat(governance): 预览框架冻结基线 (ADR-0009)")
