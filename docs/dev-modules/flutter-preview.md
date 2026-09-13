# flutter-preview — APK 预览脚手架模块

> **职责**: 在 WEB 端预览 Flutter web 编译产物 (mobile-first 验收用)
> **物理位置**: `src/app/{app-preview,preview}/` + `src/components/preview/` + `public/app/`
> **入口**: <https://nuankebao.tooyang.top/app-preview> (部署后)

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
