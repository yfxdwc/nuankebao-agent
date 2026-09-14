# 暖客宝 VS Code Remote-SSH:lk 桌面启 GUI, SSH 进 tc 改代码

> **写于**: 2026-09-13 (commit 见 git log `tc-full-deploy-2026-09-13`)
> **前提**: tc-full-deploy Phase 1-4 全部跑通 (PATH / systemd / SSH 桥)
> **目的**: 主人在 lk 桌面启 VS Code → Remote-SSH 连 tc → 改 `nuankebao-agent` 项目代码,HMR / Hot Reload 实时生效

---

## 1. 一次性准备 (我都做完了, 主人只需 verify)

在 **lk 上**, 以下都已就绪:

- ✅ `code` (VS Code 1.137.0) — `snap install code --classic`
- ✅ SSH config `Host tc` — 指向 `192.168.1.99` (tc 的 LAN IP)
- ✅ SSH 私钥 `~/.ssh/lk_for_tc_ed25519` — fingerprint `SHA256:8BoVYDIv8crHtibnlLWrLyFrwkyBcmTg9242xyfR9f8`
- ✅ 8 个 VS Code 扩展(在 lk 上装, GUI 启时自动可用):
  - `ms-vscode-remote.remote-ssh` + `ms-vscode-remote.remote-ssh-edit` + `ms-vscode.remote-explorer`
  - `dart-code.dart-code` + `dart-code.flutter`
  - `bradlc.vscode-tailwindcss`
  - `dbaeumer.vscode-eslint` + `esbenp.prettier-vscode`
- ✅ Desktop launcher `/var/lib/snapd/desktop/applications/code_code.desktop`
- ✅ `lk /etc/hosts`: `192.168.1.99 tc`
- ✅ `lk /etc/environment` NO_PROXY 含 `tc,nuankebao,192.168.1.99` (浏览器 / curl 直连不走代理)

在 **tc 上**:
- ✅ Node.js v22.23.2 (Remote-SSH server 依赖)
- ✅ 90G 空闲磁盘
- ✅ `loginctl show-user tooyan` Linger=yes (logout 后 user service 不停)
- ✅ `~/.nuankebao_env` PATH 配好 (login shell 拿 flutter/adb/java/javac/docker/pnpm/node)
- ✅ systemd user service `nuankebao-nextjs` active (Next.js dev 跑 3003, HMR 就绪)
- ✅ docker `nuankebao-postgres` Up (Postgres dev DB)

---

## 2. 主人在 lk 桌面启 VS Code + 连 tc (3 步)

### Step 1: 启 VS Code

在 lk 桌面 session:
- 应用菜单搜 "Visual Studio Code" → 启
- 或 terminal 跑 `code &`

### Step 2: 用 Remote-SSH 连 tc

`Ctrl+Shift+P` → 输入 `Remote-SSH: Connect to Host` → 选 `tc`

第一次会弹 2 个对话框:
1. **平台** → 选 `Linux`
2. **指纹信任** → 看 fingerprint 是不是 `glUAXf5NgKtUhmGKYnJ4F8TlVvBFhV+ZURv7xbFzTa8`(对,这是 tc 的),点 `Continue`

VS Code 自动装 `.vscode-server` 到 tc (~30 秒, 只第一次)。装完左下角显示 `SSH: tc`。

### Step 3: 打开 nuankebao 项目

`Ctrl+Shift+P` → `Remote-SSH: Open Folder` → 输 `/opt/nuankebao` (软链到 `/home/tooyan/nuankebao-agent`)

左边文件树看到:
```
flutter_app/        ← APK 域 (主产品)
src/                ← WEB 域 (开发脚手架)
deploy/             ← 备份 SOP
docs/               ← 设计文档 + ADR
tools/              ← dev 脚本
drizzle/            ← DB migrations
```

→ 成功 ✅

---

## 3. 装 5 个远程扩展 (在 tc 那边装, 跟本机独立)

VS Code 在 Remote-SSH 模式下,扩展分本机 / 远程。**远程扩展要在 SSH 那边装**:

左侧 Extensions (Ctrl+Shift+X):
- 搜 `Remote-SSH` → 看到已装的 `ms-vscode-remote.remote-ssh` (这是客户端, 已经在 lk 装好,不要重复)
- 搜 `Dart` → `dart-code.dart-code` → 看到 "**Install on SSH: tc**" 按钮 → 点它
- 搜 `Flutter` → `dart-code.flutter` → Install on SSH: tc
- 搜 `Tailwind CSS IntelliSense` → `bradlc.vscode-tailwindcss` → Install on SSH: tc
- 搜 `ESLint` → `dbaeumer.vscode-eslint` → Install on SSH: tc
- 搜 `Prettier` → `esbenp.prettier-vscode` → Install on SSH: tc

装好后每个扩展在 lk 列表里显示 `Installed on SSH: tc`。

---

## 4. ★ 主力体验验证

### 4.1 Next.js HMR (WEB 域)
1. 在 VS Code 打开 `src/app/admin/page.tsx`
2. 改任意一行 (例如加个 `console.log('HMR test')`)
3. `Ctrl+S` 保存
4. lk 浏览器开 `http://tc:3003/admin` → 1 秒内自动刷新(无需手动 reload)
5. terminal 跑 `ssh tc 'bash /home/tooyan/nuankebao-agent/tools/dev-logs.sh nextjs -f'` 看日志

### 4.2 Flutter Hot Reload (APK 域)
前提:真手机 USB 插 lk, `adb devices` 看到 `device`

1. 在 VS Code 打开 `flutter_app/lib/main.dart`
2. 改任意一行 dart 代码
3. `Ctrl+S` 保存 → 触发 VS Code 的 Hot Reload 按钮(或者装 `Run On Save` 扩展自动)
4. 手机屏幕 1 秒内自动刷新

### 4.3 Terminal 在 tc 上
- VS Code 下拉 `Terminal → New Terminal` → 自动开 tc 上的 bash (login shell, PATH 全)
- 跑 `which flutter` / `bash /home/tooyan/nuankebao-agent/tools/dev-status.sh` 等都生效

---

## 5. 排错速查

| 症状 | 根因 | 修复 |
|---|---|---|
| `code` 命令在 lk terminal not found | 没装,或 PATH 没 snap | 装: `sudo snap install code --classic`; PATH 加 `/snap/bin` |
| Connect to Host 时卡 "Setting up SSH Host" | tc 上 Node 没装 / PATH 没 | tc 上 `bash -lc 'node --version'` 验证 |
| 第一次连超时 (>2 min) | tc 上 disk 满 / 网络阻塞 | `ssh tc 'df -h /'` 看空间;`tools/dev-status.sh` 看 |
| 提示 "Permissions for '~/.vscode-server' could not be restored" | 之前的 server 装了一半 | `ssh tc 'rm -rf ~/.vscode-server && rm -rf ~/.vscode-remote-containers'` 后重连 |
| 提示 fingerprint 不对 | 中间人 / SSH config 指错机器 | `ssh-keygen -lf ~/.ssh/lk_for_tc_ed25519` 比对 fingerprint |
| 终端 `which flutter` not found | tc 端 PATH 没生效 | tc 上 `bash -lc 'cat ~/.nuankebao_env'` 看是否加载;重新 `ssh tc` 触发 login shell |
| `Install on SSH: tc` 按钮变灰 | 还没连上 tc | 先 `Ctrl+Shift,P` → `Remote-SSH: Connect to Host` → tc |

---

## 6. 关联

- SSH 桥 / 私钥 / tc onboarding: [`tc-onboarding.md`](tc-onboarding.md)
- 模式切换 (dev ↔ prod): [`AGENTS.md §3 该做项`](../../../AGENTS.md)
- dev 工具脚本: `tools/dev-{stack,status,logs}.sh`
- 系统约定: `AGENTS.md` + `docs/CHARTER.md`