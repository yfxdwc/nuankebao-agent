# 暖客宝 tc-onboarding:从 lk SSH 进 tc 开发 nuankebao

> **写于**: 2026-09-13 (commit 见 git log `tc-full-deploy-2026-09-13`)
> **目的**: 让 lk 上的主人 (mm7) 用 SSH key (无密码) 登录 tc,VS Code Remote-SSH 进去写 nuankebao。
> **拓扑**:
> ```
> lk (192.168.1.200, mm7, 桌面) ──SSH──> tc (hostname=tc, tooyan, dev 服务器)
>                                                ├── flutter_app/  (主产品)
>                                                ├── nuankebao-agent (Next.js + scripts + deploy)
>                                                ├── ~/.nuankebao_env (PATH/JAVA_HOME/ANDROID_HOME)
>                                                └── nuankebao-nextjs.service (systemd, port 3003)
> ```

---

## 1. 一次性:从 tc 把私钥拷到 lk

⚠ **不要把私钥传到公网/中间服务器**,只在 LAN 内手动操作。

**在 lk 上跑** (mm7 用户的 home):

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
# 从 tc 拉私钥 (tc 当前有 tooyan 用户的 key, 现在要拉一个新的 lk_for_tc_ed25519)
scp tooyan@tc:~/.ssh/lk_for_tc_ed25519 ~/.ssh/
chmod 600 ~/.ssh/lk_for_tc_ed25519

# 验证指纹 (防止传输过程中被替换)
ssh-keygen -lf ~/.ssh/lk_for_tc_ed25519
# 期望: SHA256:8BoVYDIv8crHtibnlLWrLyFrwkyBcmTg9242xyfR9f8 (ED25519)
```

如果 tc 当前没有 scp 入口(没有 mm7 → tc 的认证),可以先用 password 一次性 ssh 进去,然后切到 key 方式。

---

## 2. lk 上的 SSH config (`~/.ssh/config`)

```sshconfig
# 暖客宝 tc 服务器 (主人 lk 桌面 → tc dev)
Host tc
    HostName 192.168.1.???      # ⚠ 填 tc 的实际 LAN IP, 主人自己定
    User tooyan
    IdentityFile ~/.ssh/lk_for_tc_ed25519
    IdentitiesOnly yes          # 防 ssh 乱找其他 key
    StrictHostKeyChecking accept-new
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

> ⚠ **必须填 HostName**:目前 tc 的 LAN IP 需要主人确认(可能是 192.168.1.xxx)。如果不确定,在 tc 上跑 `ip -4 addr show | grep inet | grep -v 127.0.0.1` 查。

---

## 3. 第一次验证(从 lk)

```bash
# 测试 SSH 连通性
ssh tc 'whoami && hostname && pwd'

# 期望:
#   tooyan
#   tc
#   /home/tooyan
```

如果 `StrictHostKeyChecking accept-new` 第一次会问是否信任 fingerprint,**比对 fingerprint**:
```
256 SHA256:xxxxxxxxxxx lk-for-tc (ED25519)
```
跟 tc 上的 `ssh-keygen -lf ~/.ssh/lk_for_tc_ed25519.pub` 输出比对,一致再接受。

---

## 4. VS Code Remote-SSH 配(图形化主力开发)

`Ctrl+Shift+P` → `Remote-SSH: Open SSH Configuration File` → 选 `~/.ssh/config`
(上面第 2 节已经写好,VS Code 直接读)

然后 `Ctrl+Shift+P` → `Remote-SSH: Connect to Host` → 选 `tc`
→ 选 Linux
→ 等 VS Code 在 tc 上自动装 Remote-SSH server (~30 秒)
→ 左下角显示 `SSH: tc` 表示已连
→ `File → Open Folder` → `/home/tooyan/nuankebao-agent` (或 `/opt/nuankebao`,软链等价)

**装 VS Code 插件**(在 tc 那边装,跟本机插件独立):
- Dart (`dart-code.dart-code`)
- Flutter (`dart-code.flutter`)
- Tailwind CSS IntelliSense (`bradlc.vscode-tailwindcss`)
- ESLint (`dbaeumer.vscode-eslint`)
- Prettier (`esbenp.prettier-vscode`)

---

## 5. 在 tc 上验证 dev 环境

```bash
# 1. 关键命令能 which 到
which flutter adb java javac pnpm node docker

# 2. Flutter SDK 健康
flutter doctor
# 期望: Flutter + Android toolchain ✅ (Chrome / Linux toolchain 是 nuankebao 范围外, 不在意)

# 3. dev 服务运行中
./tools/dev-status.sh
# 期望: nuankebao-nextjs.service active + nuankebao-postgres Up + 3003/5432 占用 + HTTP 200/307

# 4. Flutter 项目能 pub get
cd /opt/nuankebao/flutter_app && flutter pub get

# 5. (如果有 USB 手机) adb 连机
adb devices
```

---

## 6. 日常 dev 流程(从 lk 进 tc)

| 想做的 | 在 lk 上的操作 |
|---|---|
| 写 nuankebao Flutter 代码 | VS Code Remote-SSH 进 tc,改 `flutter_app/lib/**`,保存即 Hot Reload(需要手机 USB 连 lk 或 adb wireless 连到 tc 的 flutter dev server) |
| 写 nuankebao Next.js 代码 | VS Code Remote-SSH 进 tc,改 `src/**`,保存即 HMR(`http://0.0.0.0:3003` 看效果) |
| 跑 db migration | `cd /opt/nuankebao && pnpm db:compat && pnpm db:migrate` |
| 看 dev 服务状态 | `ssh tc './tools/dev-status.sh'` |
| 看 Next.js 日志 | `ssh tc './tools/dev-logs.sh nextjs -f'` |
| 临时停 dev | `ssh tc './tools/dev-stack.sh stop'` |
| 重启 Next.js dev (HMR 不掉) | `ssh tc './tools/dev-stack.sh restart'` |
| 跑 backup 演练 | `ssh tc 'bash deploy/restore_verify.sh'` |
| 接 USB 手机 | 手机 USB 插 **lk**,在 lk 上 `adb devices` 看;或者插 tc 但 tc 是无头 (无 GUI 显示调试屏) |

---

## 7. Android 手机调试拓扑

**推荐:手机 USB 插在 lk,Flutter dev server 在 tc**

```
[手机] ──USB──> [lk (mm7 桌面)]
[ lk ] ──adb connect tc:5555──> [tc (headless, 跑 Flutter dev server + Hot Reload)]
```

**配置步骤**:

1. **lk 上**:手机 USB 插 lk,`adb devices` 看是否识别(可能要装 OEM 驱动)
2. **lk 上**:`adb tcpip 5555`(让手机开 5555 端口监听 wireless ADB)
3. **lk 上**:`adb connect tc:5555` (反向:从 lk 的 adb 客户端连 tc 的 adb server,这是个全局 adb)

或者更简单:
- 手机和 lk 同 WiFi
- `adb connect <phone_ip>:5555` 直接无线连手机 (无需 tc)

实际 nuankebao 现在的 dev-flutter.sh 默认是连 phone (web + phone 并行模式),用法是 `./tools/dev-flutter.sh <phone_ip>`。

---

## 8. 安全红线(主人维护)

- ✅ lk_for_tc_ed25519 私钥 **只在 lk 上**, 不进 git, 不进任何 dotfiles 备份
- ✅ 不要把同一个 key 加到其他机器的 authorized_keys (复用 key 风险)
- ✅ 如果 lk 被偷/送修, 立刻在 tc 上把 `from="192.168.1.200"` 那行 authorized_keys 删掉
- ✅ 改 tc LAN IP 后, lk 的 SSH config `HostName` 要同步更新

---

## 9. 排错速查

| 症状 | 根因 | 修复 |
|---|---|---|
| `ssh tc` 提示 fingerprint 不对 | 中间人 / 私钥复制错 | 跟 tc 上 `ssh-keygen -lf ~/.ssh/lk_for_tc_ed25519.pub` 比对 |
| `ssh tc` 提示 permission denied | pub key 没加 / from 限制 IP 错 | 看 `~/.ssh/authorized_keys` 有没有 `from="192.168.1.200"` 那行 |
| `ssh tc` 提示 connection refused | tc 没开 SSH / 防火墙挡 | tc 上 `sudo systemctl status sshd` + `sudo ufw allow 22/tcp` |
| `which flutter` 在 tc 上 not found | PATH 没生效 | tc 上 `bash -lc 'which flutter'` 测试;`cat ~/.nuankebao_env` 看配置 |
| VS Code Remote-SSH 卡住 | tc 上 .vscode-server 没装 | 在 tc 上删 `~/.vscode-server`,重连 |
| Flutter Hot Reload 不响应 | adb 断了 / 端口占用 | `./tools/dev-status.sh` 看 adb 设备;`pkill -f "flutter run"` 后重启 |

---

## 10. 关联

- 部署栈 (`deploy/`) + 备份 SOP: `deploy/README.md`
- Flutter dev workflow 详细: `docs/adr/0003-flutter-dev-workflow.md`
- 双域 (APK + WEB) 共存架构: `docs/adr/0008-apk-web-domain-spec.md`
- 系统约定 + 命名一致性: `AGENTS.md §6`
- 任务级快照 (改 ≥3 文件前必打): `scripts/task-snapshot.sh`
## 11. 凭证管理 (2026-09-14)

GitHub PAT 不再嵌在 origin URL, 改走 `~/.git-credentials` (chmod 600) + `credential.helper=store` (git config --global).
SKILL.md: ~/.muse/skills/credentials/SKILL.md v2.16 (2026-09-14) 标 GitHub Token 验证活跃.

