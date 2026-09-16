# flutter-preview — APK 预览脚手架模块

> **职责**: 在 WEB 端预览 Flutter web 编译产物 (mobile-first 验收用)
> **物理位置**: `src/app/{app-preview,preview}/` + `src/components/preview/` + `public/app/`
> **入口**: <https://nuankebao.tooyang.top/app-preview> (部署后)
> **冻结状态**: ⚠ **预览框架已冻结 (2026-09-16, ADR-0009, baseline-preview-v0.1.4-280f5fa)**. 详见 [§Frozen Contract](#frozen-contract-adr-0009).

## 当前实现

### `src/app/app-preview/page.tsx` (主预览页)

主预览入口:
- iframe 嵌入 Flutter web 编译产物 (`/app/main.dart.js`)
- 显示当前 API base URL (诊断用)
- 显示 banner (R12 登录循环 informational, 主人 override 2026-09-12)

### `src/app/preview/` (旧路径, 准备并入 app-preview)

历史路径, Phase 9 实地收尾时并入 `app-preview/`.

### `src/components/preview/` (2 个组件)

| 组件 | 文件 | 用途 |
|---|---|---|
| `PreviewFrame` | `preview-frame.tsx` | iframe 容器 + FlutterWeb 嵌入 + 当前 API URL 显示 |
| `FlutterWebLoginBanner` | `flutter-web-login-banner.tsx` | R12 登录循环 informational banner (主人 2026-09-12 override, sky blue, 可 dismiss) |

### `public/app/` (Flutter web 编译产物)

git tracked 的 Flutter web build 产物:
- `main.dart.js` (~2MB, Flutter 编译的 Dart → JS)
- `flutter_service_worker.js` (SW 缓存)
- `version.json` (0.1.1#2)
- `flutter.js` + `flutter_bootstrap.js` + `manifest.json` + `assets/`

### `tools/build-flutter-web.sh` (一键 build + sync, 2026-09-12 加)

参数化主入口 (IP / PORT / --auto / --no-sync / --help):
- build Flutter web
- sync 到 public/app/
- bump version.json
- 更新 SW hash

## 当前问题 + 待办

### ⚠ R12 登录循环 (w14 三次复发, 详见 docs/login-failure-triage.md)

**症状**: Flutter web 的 dio XHR 在 HTTP 层拿不到 Set-Cookie 头 (cookie-based auth 在 XHR 行为下失效).

**2026-09-12 主人 override**:
- ❌ 删 `blockIframe` 机制 (之前 R5 加的"物理阻断"被否决)
- ✅ iframe 永远可点, banner 改为 informational (sky blue)
- ⚠ 后果: iframe 里点登录 = 必触发 R12 循环 (主人接受这个风险)

**AGENTS §5 反模式冲突**: "贴告示 ≠ 修复" — 但主人有意识选择 banner-only, 准备接受 R12 风险. 这是**特例**, 不外推到其他登录场景.

### 待办

- [ ] puppeteer 拦截 / middleware 拦截 / API disable 任一方式处理 R12 循环 (主人决策)
- [ ] 写 post-mortem: 为什么 override AGENTS §5 反模式
- [ ] AGENTS §5 加注: 此变更的特例情况
- [ ] `src/app/preview/` 并入 `app-preview/` (Phase 9)

## 扩展指南

**新增预览设备** (e.g. iPhone 14 Pro 真实尺寸):
1. 在 `src/components/preview/` 加新组件
2. 用 CSS `@media` 或 styled-jsx 控制 iframe 容器尺寸
3. 加设备切换 UI (e.g. dropdown 在 app-preview/page.tsx)

**升级 Flutter SDK**:
1. 主人装 SDK (~700MB, CHANGELOG [0.4.2] todo)
2. 重 build: `bash tools/build-flutter-web.sh <IP> <PORT>` 或 `--auto`
3. SW 自动更新 (硬刷新拿新版本)

**APK 真机预览** (替代 iframe):
- 当前只有 Flutter web 预览, APK 需真机扫码
- 未来: 加 USB / WiFi ADB 接入 (复杂, 暂不做)

## 相关 SOP

- [CHANGELOG.md [0.4.2] 修 /app-preview 登录连不上后端 (Flutter web API base URL 写错 IP)](../../CHANGELOG.md) (2026-09-12)
- [CHANGELOG.md [0.4.1] /app-preview 移除 blockIframe 机制](../../CHANGELOG.md) (主人 override)
- [docs/login-failure-triage.md](../../login-failure-triage.md) (R12 详细分析)
- [tools/build-flutter-web.sh](../../build-flutter-web.sh) (一键 build)

## 验证清单

部署后主人验证:
- [ ] <https://nuankebao.tooyang.top/app-preview> 可访问
- [ ] Flutter web 渲染正常 (中老年大字 + 养生绿主题)
- [ ] 显示当前 API base URL (诊断)
- [ ] ⚠ banner 显示 R12 提示 (informational only)

## Frozen Contract (ADR-0009)

> **完整决策**: [ADR-0009 §3 改前 SOP](../../adr/0009-preview-framework-freeze.md#3-改前-sop-justified-change-workflow) + [AGENTS §9](../../AGENTS.md#9-预览框架冻结-preview-framework-freeze-charter-7-反模式沉淀--adr-0009)
>
> **生效**: 2026-09-16 主人拍板. **基线 tag**: `baseline-preview-v0.1.4-280f5fa`.

### 9 个冻结路径 (本模块物理位置)

```
src/app/app-preview/             ← 本模块主页面 (Next.js page + iframe)
src/app/preview/                 ← /preview → /app-preview 307 redirect 兜底
src/components/preview/          ← PreviewFrame + FlutterWebLoginBanner (2 个组件)
public/app/                      ← Flutter web 编译产物 (git tracked)
```

加上 preview 框架生态 (跨模块但同冻结域):
```
tools/build-flutter-web.sh
tools/dev-app-proxy.py
tools/install-dev-app-proxy.sh
tools/install-flutter-dev-tunnel.sh
tools/start-flutter-dev.sh
```

### 改前 SOP (强约束)

1. **ask_user 拍板** — 不是 agent 自动决策. 触发场景: 主人显式升级 / W19+ 大版本 / 业务模块深度联动
2. **跑测试** — `pnpm test tests/preview-framework-snapshot.test.ts` 必须 pass (9 路径 + version.json)
3. **现场验证** — `bash tools/check-port.sh 3003` + `pnpm dev` 后浏览器开 `/app-preview` 看 preview 稳
4. **commit 显式声明** — 二选一:
   - `git commit --no-verify -m "fix(preview): ..."` (推荐)
   - `git commit -m "[preview-bypass] fix(preview): ..."` (留痕)

### ⚠ 故意 NOT 冻结 (本模块演进必要)

| 路径 | 不冻结原因 |
|---|---|
| `docs/dev-modules/flutter-preview.md` (本文件) | 治理文档 — §Frozen Contract 段本就需要演进, 自身不该被自己冻结 |
| `flutter_app/lib/**` | 业务源码 — 改业务 = 改 preview 显示什么, **不该被 preview freeze 拦** |

### 应急解冻 (preview 已挂)

```bash
# 单文件回滚
git checkout baseline-preview-v0.1.4-280f5fa -- src/components/preview/preview-frame.tsx
git commit --no-verify -m "fix(preview): 紧急回滚 preview-frame.tsx 到 baseline"

# 整 framework 回滚 (9 个路径全打)
git stash push -m "preview-emergency-$(date +%s)"
git checkout baseline-preview-v0.1.4-280f5fa -- \
  src/app/app-preview/ src/app/preview/ src/components/preview/ \
  tools/build-flutter-web.sh tools/dev-app-proxy.py \
  tools/install-dev-app-proxy.sh tools/install-flutter-dev-tunnel.sh \
  tools/start-flutter-dev.sh public/app/
git add -A
git commit --no-verify -m "fix(preview): 紧急回滚整个 preview framework 到 baseline"
```

**应急后强制**: 24h 内写 postmortem + 主人 review + AGENTS §X 加新反模式条目.

### 测试入口

```bash
# Vitest snapshot (CI 必跑)
pnpm test tests/preview-framework-snapshot.test.ts

# Playwright smoke (主人 dev server :3003 时跑; ?dev=1 路径默认 skip)
pnpm test:e2e e2e/preview-smoke.spec.ts
```
