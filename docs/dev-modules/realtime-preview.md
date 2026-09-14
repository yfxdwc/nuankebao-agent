# 暖客宝实时预览窗口 — vibe coding 极简手册

> **写于**: 2026-09-14
> **主人场景**: Vibe coding (AI agent 写代码, 主人盯浏览器看实时预览)
> **核心结论**: **实时预览 = lk 浏览器一个固定窗口**, 不是 VS Code, 不是 SSH

---

## 一句话总结

**打开 lk 浏览器, 输 `http://tc:3003/admin`, 别关。AI agent 改代码 → 浏览器 1-2 秒自动刷新 = 实时预览。**

---

## 主人 vibe coding 时的桌面布局

```
┌─────────────────────────────────────────────────────────────┐
│  lk 桌面 (mm7)                                                  │
│                                                              │
│  ┌─────────────────┐ ┌─────────────────┐                    │
│  │ Browser Tab 1   │ │ Browser Tab 2   │                    │
│  │ tc:3003/admin   │ │ tc:3003/login   │                    │
│  │ [HMR 实时刷新]  │ │ [HMR 实时刷新]  │                    │
│  └─────────────────┘ └─────────────────┘                    │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │ Terminal: pi / Codex / Claude Code                  │ ← 你在这 prompt│
│  │ 你: "改 admin 加个新 widget"                         │              │
│  │ AI: 改代码 → commit → 浏览器自动刷新               │              │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## 浏览器窗口固定打开(不关)

| 优先级 | URL | 用途 |
|---|---|---|
| ★★★★★ | `http://tc:3003/admin` | WEB 域 dashboard,主力预览 |
| ★★★★ | `http://tc:3003/login` | 登录页(改 auth 时盯) |
| ★★★ | `http://tc:3003/app-preview` | Flutter web preview 容器(改 APK 时盯) |
| ★★ | `http://tc:3003/dev` | dev 子页(改 dev tools 时) |

**最少**:开 `http://tc:3003/admin` 一个窗口就够 80% 场景。

## AI agent 工作位置

| 场景 | 跑在哪 |
|---|---|
| **pi** (我, 当前 session) | tc 上 `/home/tooyan/nuankebao-agent`, cwd |
| Codex | lk 上 terminal / 或 tc 上 |
| Claude Code | lk 上 terminal / 或 tc 上 |

**主人只需要**:在 lk 终端跑 `pi`(我已经配好),给 prompt,我改代码。

## 你不需要做的事

- ❌ 不需要开 VS Code Remote-SSH(自动流程用不上)
- ❌ 不需要手动 `Ctrl+S` 保存
- ❌ 不需要看 build log(除非 agent 报错)
- ❌ 不需要 `flutter run`(APK 域开发用,日常 web 改动不需要)

## 你需要做的事

1. **浏览器开 1-4 个 tab**, 不关
3. 在 lk terminal / IDE prompt 给 AI agent 指令
4. 看到浏览器自动刷新 = agent 改完了

## 验证链路(主人开浏览器前先确认服务在跑)

```bash
ssh tc 'bash /home/tooyan/nuankebao-agent/tools/dev-status.sh'
# 期望: nuankebao-nextjs.service active + nuankebao-postgres Up + HTTP 200/307
```

或者从 lk:

```bash
ssh tc 'bash /home/tooyan/nuankebao-agent/tools/dev-status.sh'
```

## 出问题了怎么办

| 现象 | 原因 | 一招修 |
|---|---|---|
| 浏览器 502 / 502 | tc 上 Next.js 挂了 | `ssh tc 'bash /home/tooyan/nuankebao-agent/tools/dev-stack.sh restart'` |
| 浏览器"找不到 tc" | lk /etc/hosts 没配 | `cat /etc/hosts \| grep tc`, 没就 `echo "192.168.1.99 tc" \| sudo tee -a /etc/hosts` |
| 浏览器走代理 502 | no_proxy 没配 | `cat /etc/environment \| grep NO_PROXY`, 确认含 `tc,nuankebao,192.168.1.99` |
| AI agent 改完浏览器没刷新 | Next.js HMR 卡了 | `ssh tc 'bash /home/tooyan/nuankebao-agent/tools/dev-stack.sh restart'` |
| 磁盘满 ENOSPC | `/tmp` 或 `.next` 涨大 | `ssh tc 'du -sh /home/tooyan/nuankebao-agent/.next && rm -rf /home/tooyan/nuankebao-agent/.next/cache'` |

## 进阶: 想手动微调?

打开 VS Code Remote-SSH (详细: [`vscode-remote-ssh.md`](vscode-remote-ssh.md)):
1. lk 桌面启 VS Code
2. `Ctrl+Shift,P` → `Remote-SSH: Connect to Host` → `tc`
3. 打开 `/opt/nuankebao`
4. 装 5 个远程扩展
5. 改代码, 浏览器 HMR 自动刷

**但 vibe coding 流程不需要这个**。

## 关联- SSH 桥 + tc onboarding: [`tc-onboarding.md`](tc-onboarding.md)
- VS Code Remote-SSH (手动开发用): [`vscode-remote-ssh.md`](vscode-remote-ssh.md)
- dev 工具脚本: `tools/dev-stack.sh` `tools/dev-status.sh` `tools/dev-logs.sh`
- 系统约定: [`AGENTS.md`](../../../AGENTS.md)